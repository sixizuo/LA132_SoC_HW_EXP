//=====================================================================
//  spi_stream_top.v  ——  实验九：FIFO 型 SPI AD/DA 流式控制器
//---------------------------------------------------------------------
//  结构 :
//     外层 APB 从设备（0x300A_0000，寄存器见下）
//       ├─ 采样定时器（递减计数，fs = 32 MHz / DIV）
//       ├─ AD 采样状态机（按表 11-22）
//       ├─ DA 发送状态机
//       ├─ RX FIFO 64×32 / TX FIFO 32×32（分布式 RAM）
//       └─ 内部 APB 主机 —— 只驱动原 spi_top 的 DATA / SPSR，
//          SPI 比特时序、分频器完全沿用原控制器，一行时序都不改
//  SPI 引擎参数（由本模块使能后自动写入，不暴露给软件）:
//     AD 模式: SPCR = 8'hDC, SPER = 8'h40, SOFTCS = 8'hE1 (ADC128S102, bit4 片选常低)
//     DA 模式: SPCR = 8'hD8, SPER = 8'h40, SOFTCS 空闲 = 8'hF2 (TLV5618A, bit5 片选)
//     AD/DA 模式切换时状态机自动回 S_CFG0 重配一遍。
//  DA 帧 (TLV5618A, 16 bit = 2 字节):
//     SOFTCS=0xD2 (bit5 拉低选中) -> 发高字节 -> 发低字节 -> SOFTCS=0xF2 (拉高锁存)
//     整个"选中-发送-释放"流程由状态机自动完成, 软件只管往 TX FIFO 写数。
//  寄存器 :
//     0x00 CTRL     RW bit0 使能 / bit1 0=AD 1=DA / bit2 中断使能 / bit3 回环
//     0x04 DIV      RW 采样分频，fs = 32M/DIV，小于 64 按 64 处理
//     0x08 DATA     RW 写压入 TX FIFO（回环时直接进 RX FIFO）/ 读弹出 RX FIFO
//     0x0C STATUS   R  bit0 RX 非空 / bit1 RX 半满 / bit2 RX 满
//                      bit3 TX 空 / bit4 TX 满 / bit5 忙
//     0x10 CNT      R  已完成采样数，写任意值清零
//     0x14 CH       RW ADC 通道号 0~7
//     0x18 FIFO_LVL R  [7:0] RX 条数，[15:8] TX 条数
//     0x1C VERSION  R  固定 0x5350_0003
//  说明 :
//     · 传输完成判据用 “TX 空 且 非忙”（spsr[2] && !spsr[4]），不是只看
//       spsr[2]。wfempty 在字节被取走、开始移位时就已置 1，此时数据还没
//       发完，只看它会读到上一帧的结果。
//     · DIV 钳位到 ≥64，否则状态机追不上定时器，实际采样率不可控。
//     · 采样请求用“挂起标记 + 立即消费”：一旦状态机空下来就补采，绝不
//       丢点；追不上时表现为背靠背采样，CNT 如实反映实际速率。
//=====================================================================
module spi_stream_top (
	input  wire        apb_pclk   ,
	input  wire        apb_prstn  ,
	input  wire        apb_psel   ,
	input  wire [31:0] apb_paddr  ,
	input  wire        apb_pwrite ,
	input  wire        apb_penable,
	input  wire [31:0] apb_pwdata ,
	output wire [31:0] apb_prdata ,
	output wire        apb_pready ,

	output wire [3:0]  spi_clk    ,
	input  wire [3:0]  spi_miso   ,
	output wire [3:0]  spi_mosi   ,
	output wire [3:0]  spi_csn    ,
	output wire [7:0]  spi_mul    ,

	output wire        stream_irq
);

	// ---------------- 寄存器地址 ----------------
	localparam [7:0] R_CTRL    = 8'h00;
	localparam [7:0] R_DIV     = 8'h04;
	localparam [7:0] R_DATA    = 8'h08;
	localparam [7:0] R_STATUS  = 8'h0c;
	localparam [7:0] R_CNT     = 8'h10;
	localparam [7:0] R_CH      = 8'h14;
	localparam [7:0] R_LVL     = 8'h18;
	localparam [7:0] R_VERSION = 8'h1c;

	// 原 spi_top 的寄存器偏移
	localparam [7:0] S_SPCR = 8'h00;
	localparam [7:0] S_SPSR = 8'h04;
	localparam [7:0] S_DATA = 8'h08;
	localparam [7:0] S_SPER = 8'h0c;
	localparam [7:0] S_CS   = 8'h14;

	// ---------------- 状态编码 ----------------
	localparam [3:0] S_CFG0  = 4'd0;    // 写 SPCR
	localparam [3:0] S_CFG1  = 4'd1;    // 写 SPER
	localparam [3:0] S_CFG2  = 4'd2;    // 写 SOFTCS
	localparam [3:0] S_IDLE  = 4'd3;
	localparam [3:0] S_CMD   = 4'd4;    // 发通道命令字节
	localparam [3:0] S_WAIT1 = 4'd5;    // 等第 1 字节完成
	localparam [3:0] S_RD1   = 4'd6;    // 读高字节
	localparam [3:0] S_TX2   = 4'd7;    // 发第 2 字节
	localparam [3:0] S_WAIT2 = 4'd8;    // 等第 2 字节完成
	localparam [3:0] S_RD2   = 4'd9;    // 读低字节并入队
	localparam [3:0] S_DA_H  = 4'd10;   // DA：发高字节
	localparam [3:0] S_DA_W1 = 4'd11;
	localparam [3:0] S_DA_L  = 4'd12;   // DA：发低字节
	localparam [3:0] S_DA_W2 = 4'd13;
	localparam [3:0] S_CS_ON = 4'd14;   // DA：写 SOFTCS=0xD2 拉低 TLV5618A 片选
	localparam [3:0] S_CS_OFF= 4'd15;   // DA：写 SOFTCS=0xF2 拉高片选, 16 位锁存

	// ---------------- 所有寄存器声明 ----------------
	reg  [1:0]  mst;
	reg         mst_wr;
	reg  [7:0]  mst_addr, mst_wdata, mst_rdata;
	reg         mi_done;
	reg         mi_start, mi_wr;
	reg  [7:0]  mi_addr, mi_wdata;

	reg  [3:0]  ctrl;
	reg  [15:0] div_val;
	reg  [2:0]  ch_sel;
	reg  [31:0] samp_cnt;

	reg  [31:0] rx_mem [0:63];
	reg  [5:0]  rx_wptr, rx_rptr;
	reg  [6:0]  rx_cnt;

	reg  [31:0] tx_mem [0:31];
	reg  [5:0]  tx_wptr, tx_rptr;
	reg  [6:0]  tx_cnt;

	reg  [15:0] tick;
	reg         samp_req;

	reg  [3:0]  st;
	reg         issued;
	reg         cfg_done;
	reg         da_md_d;       // 上次配置时是哪种模式, 用来检测 AD/DA 切换
	reg  [7:0]  rx_hi;
	reg  [15:0] da_word;
	reg         da_pop;
	reg         cnt_inc;
	reg         rx_push_eng;
	reg  [31:0] rx_push_data;

	reg  [31:0] prdata;

	// ---------------- 外层 APB 访问译码 ----------------
	wire wr = apb_psel &  apb_pwrite & apb_penable;
	wire rd = apb_psel & !apb_pwrite & apb_penable;
	assign apb_pready = apb_penable;

	wire en     = ctrl[0];
	wire da_md  = ctrl[1];
	wire irq_en = ctrl[2];
	wire loop   = ctrl[3];

	// ---------------- 内部 APB 主机 ----------------
	localparam [1:0] M_IDLE = 2'd0;
	localparam [1:0] M_SET  = 2'd1;
	localparam [1:0] M_ACC  = 2'd2;
	localparam [1:0] M_END  = 2'd3;

	wire [7:0] mi_rdata = mst_rdata;
	wire       mi_ready = (mst == M_IDLE);

	wire        in_psel    = (mst == M_SET) || (mst == M_ACC);
	wire        in_penable = (mst == M_ACC);
	wire [31:0] in_prdata;

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			mst       <= M_IDLE;
			mst_wr    <= 1'b0;
			mst_addr  <= 8'd0;
			mst_wdata <= 8'd0;
			mst_rdata <= 8'd0;
			mi_done   <= 1'b0;
		end else begin
			mi_done <= 1'b0;
			case (mst)
				M_IDLE : if (mi_start) begin
					mst       <= M_SET;
					mst_wr    <= mi_wr;
					mst_addr  <= mi_addr;
					mst_wdata <= mi_wdata;
				end
				M_SET  : mst <= M_ACC;
				M_ACC  : begin
					if (!mst_wr) mst_rdata <= in_prdata[7:0];
					mst <= M_END;
				end
				M_END  : begin
					mi_done <= 1'b1;
					mst     <= M_IDLE;
				end
				default: mst <= M_IDLE;
			endcase
		end
	end

	// ---------------- 原 SPI 控制器（时序不改） ----------------
	spi_top u_spi (
		.apb_pclk    (apb_pclk          ),
		.apb_prstn   (apb_prstn         ),
		.apb_psel    (in_psel           ),
		.apb_paddr   ({24'd0, mst_addr} ),
		.apb_pwrite  (mst_wr            ),
		.apb_penable (in_penable        ),
		.apb_pwdata  ({24'd0, mst_wdata}),
		.apb_prdata  (in_prdata         ),
		.apb_pready  (                  ),
		.spi_clk     (spi_clk           ),
		.spi_miso    (spi_miso          ),
		.spi_mosi    (spi_mosi          ),
		.spi_csn     (spi_csn           ),
		.spi_mul     (spi_mul           ),
		.spi_irq     (                  )
	);

	// ---------------- 控制寄存器 ----------------
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			ctrl     <= 4'd0;
			div_val  <= 16'd3200;
			ch_sel   <= 3'd0;
			samp_cnt <= 32'd0;
		end else begin
			if (wr) begin
				case (apb_paddr[7:0])
					R_CTRL : ctrl    <= apb_pwdata[3:0];
					R_DIV  : div_val <= (apb_pwdata[15:0] < 16'd64) ? 16'd64
					                                                : apb_pwdata[15:0];
					R_CH   : ch_sel  <= apb_pwdata[2:0];
					R_CNT  : samp_cnt <= 32'd0;         // 写任意值清零
					default : ;
				endcase
			end
			if (cnt_inc) samp_cnt <= samp_cnt + 32'd1;
		end
	end

	// ---------------- FIFO ----------------
	wire rx_empty = (rx_cnt == 7'd0);
	wire rx_half  = (rx_cnt >= 7'd32);
	wire rx_full  = (rx_cnt == 7'd64);
	wire tx_empty = (tx_cnt == 7'd0);
	wire tx_full  = (tx_cnt == 7'd32);
	wire [31:0] rx_dout = rx_mem[rx_rptr];
	wire [31:0] tx_dout = tx_mem[tx_rptr];

	wire apb_data_rd = rd && (apb_paddr[7:0] == R_DATA);
	wire apb_data_wr = wr && (apb_paddr[7:0] == R_DATA);

	wire rx_pop     = apb_data_rd && !rx_empty;
	wire rx_push_lb = apb_data_wr && loop && !rx_full;    // 回环：写直接进 RX
	wire tx_push    = apb_data_wr && !loop && !tx_full;
	wire tx_pop_eng = da_md && da_pop;

	wire        rx_push     = rx_push_lb | rx_push_eng;
	wire [31:0] rx_push_val = rx_push_eng ? rx_push_data : apb_pwdata;

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			rx_wptr <= 6'd0; rx_rptr <= 6'd0; rx_cnt <= 7'd0;
			tx_wptr <= 6'd0; tx_rptr <= 6'd0; tx_cnt <= 7'd0;
		end else begin
			// ---- RX ----
			if (rx_push) begin
				rx_mem[rx_wptr] <= rx_push_val;
				rx_wptr <= rx_wptr + 6'd1;
			end
			if (rx_pop) rx_rptr <= rx_rptr + 6'd1;
			case ({rx_push, rx_pop})
				2'b10  : rx_cnt <= rx_cnt + 7'd1;
				2'b01  : rx_cnt <= rx_cnt - 7'd1;
				default: ;
			endcase

			// ---- TX ----
			if (tx_push) begin
				tx_mem[tx_wptr] <= apb_pwdata;
				tx_wptr <= tx_wptr + 6'd1;
			end
			if (tx_pop_eng) tx_rptr <= tx_rptr + 6'd1;
			case ({tx_push, tx_pop_eng})
				2'b10  : tx_cnt <= tx_cnt + 7'd1;
				2'b01  : tx_cnt <= tx_cnt - 7'd1;
				default: ;
			endcase
		end
	end

	// ---------------- 采样定时器 ----------------
	wire samp_tick = en && (tick == 16'd0);
	wire samp_go   = en && !da_md && samp_req && (st == S_IDLE);
	wire da_go     = en &&  da_md && samp_req && (st == S_IDLE) && !tx_empty;

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn)         tick <= 16'd0;
		else if (!en)           tick <= 16'd0;
		else if (tick == 16'd0) tick <= div_val - 16'd1;
		else                    tick <= tick - 16'd1;
	end

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn)              samp_req <= 1'b0;
		else if (!en)                samp_req <= 1'b0;
		else if (samp_tick)          samp_req <= 1'b1;
		else if (samp_go | da_go)    samp_req <= 1'b0;
	end

	// ---------------- 主状态机 ----------------
	//  每个状态都按同一节奏工作：先等主机空闲发出一次访问（issued=1），
	//  再等这次访问完成（mi_done）后决定下一步。不能“在 mi_done 当拍
	//  再发下一个请求”——那一拍主机还在 M_END，请求会被丢掉。
	wire [7:0] cmd_byte = {2'b00, ch_sel, 3'b000};  // ADC128S102 通道地址在 D13~D11
	wire done_ok = (mi_rdata[2] && !mi_rdata[4]);   // TX 空 且 非忙

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			st           <= S_CFG0;
			cfg_done     <= 1'b0;
			issued       <= 1'b0;
			da_md_d      <= 1'b0;
			rx_hi        <= 8'd0;
			da_word      <= 16'd0;
			da_pop       <= 1'b0;
			cnt_inc      <= 1'b0;
			mi_start     <= 1'b0;
			mi_wr        <= 1'b0;
			mi_addr      <= 8'd0;
			mi_wdata     <= 8'd0;
			rx_push_eng  <= 1'b0;
			rx_push_data <= 32'd0;
		end else begin
			mi_start    <= 1'b0;
			da_pop      <= 1'b0;
			cnt_inc     <= 1'b0;
			rx_push_eng <= 1'b0;

			if (!en) begin
				st       <= S_CFG0;
				cfg_done <= 1'b0;
				issued   <= 1'b0;
				da_md_d  <= 1'b0;
			end else begin
				case (st)
					// ---- 使能后自动配置原 SPI 控制器：写 SPCR ----
					//  AD 用 0xDC, DA 用 0xD8 (原 demo 的板级真值, CPOL/CPHA 相同)
					S_CFG0 : if (!issued) begin
						if (mi_ready) begin
							mi_start <= 1'b1; mi_wr <= 1'b1;
							mi_addr  <= S_SPCR; mi_wdata <= da_md ? 8'hd8 : 8'hdc;
							issued   <= 1'b1;
						end
					end else if (mi_done) begin
						issued <= 1'b0;
						st     <= S_CFG1;
					end
					// ---- 写 SPER ----
					S_CFG1 : if (!issued) begin
						if (mi_ready) begin
							mi_start <= 1'b1; mi_wr <= 1'b1;
							mi_addr  <= S_SPER; mi_wdata <= 8'h40;
							issued   <= 1'b1;
						end
					end else if (mi_done) begin
						issued <= 1'b0;
						st     <= S_CFG2;
					end
					// ---- 写 SOFTCS，配置完成 ----
					//  AD: 0xE1 (ADC128S102 片选常低, 原板级真值)
					//  DA: 0xF2 (两路片选全释放, TLV5618A 空闲态)
					S_CFG2 : if (!issued) begin
						if (mi_ready) begin
							mi_start <= 1'b1; mi_wr <= 1'b1;
							mi_addr  <= S_CS;   mi_wdata <= da_md ? 8'hf2 : 8'he1;
							issued   <= 1'b1;
						end
					end else if (mi_done) begin
						issued   <= 1'b0;
						cfg_done <= 1'b1;
						da_md_d  <= da_md;
						st       <= S_IDLE;
					end
					// ---- 空闲 ----
					S_IDLE : begin
						issued <= 1'b0;
						if (da_md != da_md_d) begin
							st <= S_CFG0;          // AD/DA 切换: 重配 SPI 引擎
						end else if (da_go) begin
							da_word <= tx_dout[15:0];
							da_pop  <= 1'b1;
							st      <= S_CS_ON;
						end else if (samp_go) begin
							st <= S_CMD;
						end
					end
					// ---- AD：发通道命令字节 ----
					S_CMD : if (!issued) begin
						if (mi_ready) begin
							mi_start <= 1'b1; mi_wr <= 1'b1;
							mi_addr  <= S_DATA; mi_wdata <= cmd_byte;
							issued   <= 1'b1;
						end
					end else if (mi_done) begin
						issued <= 1'b0;
						st     <= S_WAIT1;
					end
					// ---- 轮询等第 1 字节完成 ----
					S_WAIT1 : if (!issued) begin
						if (mi_ready) begin
							mi_start <= 1'b1; mi_wr <= 1'b0; mi_addr <= S_SPSR;
							issued   <= 1'b1;
						end
					end else if (mi_done) begin
						issued <= 1'b0;
						if (done_ok) st <= S_RD1;
					end
					// ---- 读高字节 ----
					S_RD1 : if (!issued) begin
						if (mi_ready) begin
							mi_start <= 1'b1; mi_wr <= 1'b0; mi_addr <= S_DATA;
							issued   <= 1'b1;
						end
					end else if (mi_done) begin
						rx_hi  <= mi_rdata;
						issued <= 1'b0;
						st     <= S_TX2;
					end
					// ---- 发第 2 字节 ----
					S_TX2 : if (!issued) begin
						if (mi_ready) begin
							mi_start <= 1'b1; mi_wr <= 1'b1;
							mi_addr  <= S_DATA; mi_wdata <= 8'h00;
							issued   <= 1'b1;
						end
					end else if (mi_done) begin
						issued <= 1'b0;
						st     <= S_WAIT2;
					end
					// ---- 轮询等第 2 字节完成 ----
					S_WAIT2 : if (!issued) begin
						if (mi_ready) begin
							mi_start <= 1'b1; mi_wr <= 1'b0; mi_addr <= S_SPSR;
							issued   <= 1'b1;
						end
					end else if (mi_done) begin
						issued <= 1'b0;
						if (done_ok) st <= S_RD2;
					end
					// ---- 读低字节并入队 ----
					S_RD2 : if (!issued) begin
						if (mi_ready) begin
							mi_start <= 1'b1; mi_wr <= 1'b0; mi_addr <= S_DATA;
							issued   <= 1'b1;
						end
					end else if (mi_done) begin
						// 16 位结果取低 12 位：{hi[3:0], lo[7:0]}
						rx_push_data <= {20'd0, rx_hi[3:0], mi_rdata[7:0]};
						rx_push_eng  <= 1'b1;
						cnt_inc      <= 1'b1;
						issued       <= 1'b0;
						st           <= S_IDLE;
					end
					// ---- DA：发高字节 ----
					S_DA_H : if (!issued) begin
						if (mi_ready) begin
							mi_start <= 1'b1; mi_wr <= 1'b1;
							mi_addr  <= S_DATA; mi_wdata <= da_word[15:8];
							issued   <= 1'b1;
						end
					end else if (mi_done) begin
						issued <= 1'b0;
						st     <= S_DA_W1;
					end
					S_DA_W1 : if (!issued) begin
						if (mi_ready) begin
							mi_start <= 1'b1; mi_wr <= 1'b0; mi_addr <= S_SPSR;
							issued   <= 1'b1;
						end
					end else if (mi_done) begin
						issued <= 1'b0;
						if (done_ok) st <= S_DA_L;
					end
					// ---- DA：发低字节 ----
					S_DA_L : if (!issued) begin
						if (mi_ready) begin
							mi_start <= 1'b1; mi_wr <= 1'b1;
							mi_addr  <= S_DATA; mi_wdata <= da_word[7:0];
							issued   <= 1'b1;
						end
					end else if (mi_done) begin
						issued <= 1'b0;
						st     <= S_DA_W2;
					end
					S_DA_W2 : if (!issued) begin
						if (mi_ready) begin
							mi_start <= 1'b1; mi_wr <= 1'b0; mi_addr <= S_SPSR;
							issued   <= 1'b1;
						end
					end else if (mi_done) begin
						issued <= 1'b0;
						// 与 AD 的 S_WAIT2 一致: 只等 done_ok, 不做任何回退。
						// 旧代码超时回退 S_DA_W1, 而 W1 看到 done_ok 又跳回
						// S_DA_L, 会把低字节反复重发 (仿真实测死循环)。
						if (done_ok) begin
							st <= S_CS_OFF;    // 2 字节发完, 拉高片选让 DAC 锁存
						end
					end
					// ---- DA：写 SOFTCS=0xD2, 拉低 TLV5618A 片选 ----
					S_CS_ON : if (!issued) begin
						if (mi_ready) begin
							mi_start <= 1'b1; mi_wr <= 1'b1;
							mi_addr  <= S_CS;   mi_wdata <= 8'hd2;
							issued   <= 1'b1;
						end
					end else if (mi_done) begin
						issued <= 1'b0;
						st     <= S_DA_H;
					end
					// ---- DA：写 SOFTCS=0xF2, 拉高片选, 16 位帧在上升沿锁存 ----
					S_CS_OFF : if (!issued) begin
						if (mi_ready) begin
							mi_start <= 1'b1; mi_wr <= 1'b1;
							mi_addr  <= S_CS;   mi_wdata <= 8'hf2;
							issued   <= 1'b1;
						end
					end else if (mi_done) begin
						issued   <= 1'b0;
						cnt_inc  <= 1'b1;
						st       <= S_IDLE;
					end
					default : st <= S_IDLE;
				endcase
			end
		end
	end

	// ---------------- 读数据选择 ----------------
	always @(*) begin
		if (rd) begin
			case (apb_paddr[7:0])
				R_CTRL    : prdata = {28'd0, ctrl};
				R_DIV     : prdata = {16'd0, div_val};
				R_DATA    : prdata = rx_empty ? 32'hffff_ffff : rx_dout;
				R_STATUS  : prdata = {26'd0, (st != S_IDLE), tx_full, tx_empty,
				                             rx_full, rx_half, !rx_empty};
				R_CNT     : prdata = samp_cnt;
				R_CH      : prdata = {29'd0, ch_sel};
				R_LVL     : prdata = {18'd0, tx_cnt, rx_cnt};
				R_VERSION : prdata = 32'h5350_0003;
				default   : prdata = 32'd0;
			endcase
		end else begin
			prdata = 32'd0;
		end
	end
	assign apb_prdata = prdata;

	assign stream_irq = irq_en & rx_half;

endmodule
