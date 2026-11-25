`include "../../config.vh"

//////////////////////////////////////////////////////////////////////////////////
// Module Name: ADC_9280_apb
//
// 说明 (2026-11-04 修改):
//   原实现: 软件必须先写 CSR bit2 拉高/拉低, 由 fifo_rd_en_gen 取上升沿产生 fifo_rd_en,
//           然后再读数据口拿数据 —— 每读 1 个字节要写 3 次 CSR, 且 DMA 无法参与。
//   现实现: 读数据口(ADC_DATA)这个动作本身就产生 FIFO 弹出脉冲, 分两级:
//           1) APB 直接读:  读 0x300B0008 自动返回 FIFO 里最老的一个字节并弹出;
//           2) DMA 搬运:    DMAC 以"源地址不递增 + 8bit"方式反复读同一个地址,
//                          每读一次弹一个字节, 不需要 CPU 干预。
//          FIFO 空时 apb_pready 拉低(插入等待), 数据一到位即完成传输;
//          连续空 4096 个 pclk 仍未取到数据则强制完成传输(返回 0x00)并置粘滞错误位,
//          避免总线永久挂死。
//
// 寄存器 (基地址 0x300B0000):
//   0x00 DIV_FREQ  采样分频
//   0x04 CSR       写: bit0 采样使能, bit1 FIFO 软复位, bit2 保留(旧软件读触发),
//                     bit3 写 1 清粘滞错误位
//                  读: bit0 FIFO 满, bit1 ADC 超量程(OTR), bit2 数据就绪(可直接读),
//                     bit3 粘滞错误(FIFO 空导致读超时), bit4 FIFO 空
//                     bit3 的清除: 下一次成功取到数据会自动清, 也可以写 CSR 时
//                     让 pwdata[3]=1 清(此时 pwdata[2:0] 要带上原 ctrl 值)
//   0x08 DATA      FIFO 数据口: 每读一次自动弹出一个字节
//
//////////////////////////////////////////////////////////////////////////////////

module ADC_9280_apb (
    input  wire        apb_pclk   ,
    input  wire        apb_prstn  ,
    input  wire        apb_psel   ,
    input  wire [31:0] apb_paddr  ,
    input  wire        apb_pwrite ,
    input  wire        apb_penable,
    input  wire [31:0] apb_pwdata ,
    output wire [31:0] apb_prdata ,
    output wire        apb_pready ,

    input  wire [7:0]  adc_data,
    input  wire        adc_otr,
    output wire        adc_clk
);

    localparam [7:0] REG_DIV  = `ADC_DIV_FREQ;      // 0x00
    localparam [7:0] REG_CSR  = `ADC_CSR;           // 0x04
    localparam [7:0] REG_DATA = `ADC_DATA;          // 0x08

    // 读握手状态机
    localparam [1:0] S_IDLE  = 2'd0,                // 流水线空, 若 FIFO 有数据则弹出
                     S_FETCH = 2'd1,                // 等 FIFO 的 dout 有效(标准 FIFO 1 拍延迟)
                     S_READY = 2'd2;                // 手里有一个字节, 可以交给总线

    localparam [11:0] TO_MAX = 12'hFFF;             // FIFO 空时的等待上限(4096 拍)

    reg [31:0] div_freq;
    reg [2:0]  ctrl;

    // ADC 核 / FIFO 状态
    wire [7:0] fifo_data_out;
    wire       fifo_full;
    wire       fifo_empty;

    reg [1:0]  st;
    reg [7:0]  hold;            // 已从 FIFO 取出、等待总线搬走的字节
    reg        err_sticky;      // FIFO 空导致读超时(粘滞, CSR bit3 写 1 清除)
    reg [11:0] to_cnt;

    wire wr = apb_psel & apb_penable &  apb_pwrite;
    wire rd = apb_psel & apb_penable & ~apb_pwrite;

    wire sel_div  = (apb_paddr[7:0] == REG_DIV );
    wire sel_csr  = (apb_paddr[7:0] == REG_CSR );
    wire sel_data = (apb_paddr[7:0] == REG_DATA);

    //--------------------------------------------------------------------------------
    // FIFO 读握手: 数据口的一次读 = 弹出并返回一个字节
    //--------------------------------------------------------------------------------
    wire data_ready = (st == S_READY);              // 手里有数据
    wire consume    = rd & sel_data &  data_ready;  // 本次读被接受, 消费掉 hold
    wire stall      = rd & sel_data & ~data_ready;  // 数据没准备好, 插入等待
    wire to_hit     = (to_cnt == TO_MAX);           // 等太久了, 强行完成

    // 只在 S_IDLE 时发弹出脉冲: 此时检查 empty 是最新值, 不会在空 FIFO 上误弹
    wire fifo_rd_en = (st == S_IDLE) & ~fifo_empty;

    always @(posedge apb_pclk or negedge apb_prstn) begin
        if (!apb_prstn) begin
            st   <= S_IDLE;
            hold <= 8'd0;
        end else if (ctrl[1]) begin              // FIFO 软复位: 流水线一起清空
            st   <= S_IDLE;
            hold <= 8'd0;
        end else begin
            case (st)
                S_IDLE  : if (~fifo_empty) st <= S_FETCH;
                S_FETCH : begin
                              hold <= fifo_data_out;   // 标准 FIFO: rd_en 后下一拍 dout 有效
                              st   <= S_READY;
                          end
                S_READY : if (consume) st <= S_IDLE;   // 交给总线后回到空闲, 下一拍补数
                default : st <= S_IDLE;
            endcase
        end
    end

    // FIFO 空时读超时计数
    always @(posedge apb_pclk or negedge apb_prstn) begin
        if (!apb_prstn)                 to_cnt <= 12'd0;
        else if (!stall)                to_cnt <= 12'd0;
        else if (to_cnt != TO_MAX)      to_cnt <= to_cnt + 1'b1;
    end

    // 粘滞错误位: 置位=读数据口时 FIFO 空超时; 清除=CSR bit3 写 1 / FIFO 软复位 / 下一次成功取到数据
    always @(posedge apb_pclk or negedge apb_prstn) begin
        if (!apb_prstn)                                        err_sticky <= 1'b0;
        else if (ctrl[1])                                      err_sticky <= 1'b0;
        else if (wr & sel_csr & apb_pwdata[3])                 err_sticky <= 1'b0;
        else if (consume)                                      err_sticky <= 1'b0;
        else if (stall & to_hit)                               err_sticky <= 1'b1;
    end

    //--------------------------------------------------------------------------------
    // 控制寄存器
    //--------------------------------------------------------------------------------
    always @(posedge apb_pclk or negedge apb_prstn) begin
        if (!apb_prstn) begin
            div_freq <= 32'd8;      // 默认分频 8 (32MHz/8 = 4MSPS), 不能是 0:
                                    // 0 会让下游 prescale-1 下溢成 0xFFFFFFFF,
                                    // 分频计数器永远到不了终点 -> 不出数
            ctrl     <= 3'd0;
        end else if (wr) begin
            case (apb_paddr[7:0])
                REG_DIV : div_freq <= apb_pwdata;
                REG_CSR : ctrl     <= apb_pwdata[2:0];   // bit3 是 W1C 清错误位, 不保存
                default : ;
            endcase
        end
    end

    //--------------------------------------------------------------------------------
    // 读数据 / 读握手
    //   数据口: 有数据或已超时才给 pready; 其余寄存器保持原来的 1 拍等待
    //--------------------------------------------------------------------------------
    reg [31:0] prdata;

    always @(*) begin
        if (rd) begin
            case (apb_paddr[7:0])
                REG_DIV  : prdata = div_freq;
                REG_CSR  : prdata = {27'd0, fifo_empty, err_sticky, data_ready, adc_otr, fifo_full};
                REG_DATA : prdata = {24'd0, to_hit ? 8'h00 : hold};
                default  : prdata = 32'd0;
            endcase
        end else begin
            prdata = 32'd0;
        end
    end

    assign apb_prdata = prdata;
    assign apb_pready = sel_data ? (apb_penable & (data_ready | to_hit))
                                 :  apb_penable;

    //--------------------------------------------------------------------------------
    // ADC 核 + FIFO
    //--------------------------------------------------------------------------------
    adc_9280_top u0(
        .clk            (apb_pclk     ),
        .reset_n        (apb_prstn    ),
        .prescale       (div_freq     ),
        .ctrl           (ctrl[2:0]    ),
        .fifo_full      (fifo_full    ),
        .fifo_empty     (fifo_empty   ),
        .fifo_rd_en     (fifo_rd_en   ),
        .fifo_data_out  (fifo_data_out),
        .ADC_DATA       (adc_data     ),
        .ADC_CLK        (adc_clk      ),
        .ADC_OTR        (adc_otr      )
    );

endmodule
