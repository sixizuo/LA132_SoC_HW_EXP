`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: adc_9280_top
//
// 说明 (2026-11-04 修改):
//   原来 FIFO 的读使能由软件写 CSR 的 bit2 电平、再用 fifo_rd_en_gen 取上升沿产生,
//   每读一个字节软件要写 3 次 CSR。现在改成:
//     - fifo_rd_en 由上层 (APB 读握手状态机) 直接给出, 是"读一个字节"的单拍脉冲;
//     - 对外输出 fifo_empty / fifo_full, 让 APB 侧能判断数据是否可取,
//       从而支持"读数据口自动出数"和"DMA 连续搬数"两种方式。
//   ctrl[2] (旧软件的软件读触发) 保留但不参与逻辑, 兼容老代码。
//
//////////////////////////////////////////////////////////////////////////////////

module adc_9280_top(
     input  wire        clk
    ,input  wire        reset_n
    ,input  wire [31:0] prescale
    ,input  wire [2:0]  ctrl            // bit0 采样使能, bit1 FIFO 软复位, bit2 保留(旧软件读触发)
    ,output wire        fifo_full
    ,output wire        fifo_empty
    ,input  wire        fifo_rd_en      // 单拍读脉冲: 从 FIFO 弹出一个字节
    ,output wire [7:0]  fifo_data_out   // FIFO 输出 (标准 FIFO, rd_en 后下一拍有效)
    ,input  wire [7:0]  ADC_DATA
    ,output wire        ADC_CLK
    ,input  wire        ADC_OTR
    );

    wire       en;
    wire       srst;
    wire [7:0] fifo_in_data;
    wire       fifo_wr_en;

    assign en   = ctrl[0];
    assign srst = ctrl[1];

    ADC_3PA9280_driver adc_9280(
        .clk            (clk          ),
        .rst_n          (reset_n      ),
        .prescale       (prescale     ),
        .en             (en           ),
        .adc_data       (ADC_DATA     ),
        .DATA           (fifo_in_data ),
        .SCLK_3PA1030   (ADC_CLK      ),
        .conv_done      (fifo_wr_en   )
    );

    fifo_adc_9280 adc_fifo (
        .clk        (clk           ),
        .srst       (srst          ),
        .din        (fifo_in_data  ),
        .wr_en      (fifo_wr_en    ),
        .rd_en      (fifo_rd_en    ),
        .dout       (fifo_data_out ),
        .full       (fifo_full     ),
        .empty      (fifo_empty    )
    );

endmodule
