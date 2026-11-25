`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/15 15:19:55
// Design Name: 
// Module Name: DAC_TOP
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module DAC_TOP#(
parameter ADDR_WIDTH = 15,
parameter DATA_WIDTH = 8
)(
    input clk ,/*DAC系统时钟*/
    input rst_n ,/*系统复位*/
    input EN ,/*DDS模块使能*/
    input [ADDR_WIDTH-1:0] Fword ,/*频率控制字*/
    input [ADDR_WIDTH-1:0] Pword ,/*相位控制字*/
    input [2:0] Aword ,/*幅度控制字*/
    input [14:0] addr_in,
    input [7:0] data_in,
    input we,
    input dac_clk,
    output DA_WRT ,/*DA数据输出时钟*/
    output [DATA_WIDTH-1:0] DA_Data /*D输出输出A*/
    );
    wire [ADDR_WIDTH-1:0] Rom_Addr;
    wire [DATA_WIDTH-1:0] Rom_Data;
     DDS #(15,8) DDS_U0(
         .clk(dac_clk)
         ,.rst_n(rst_n)
         ,.EN(EN)
         ,.Fword(Fword)
         ,.Pword(Pword)
         ,.Aword(Aword)
         ,.Rom_Data(Rom_Data)
         ,.Rom_Addr(Rom_Addr)
         ,.DA_WRT(DA_WRT)
         ,.DA_Data(DA_Data)  
         ); 
 //--------------------------------------------------------------------
 //  波形查找表: 原 DDS_RAM 是 dist_mem_gen (32768x8, 异步读, 占约 4K LUT)。
 //  异步读时 dpo 紧随 Rom_Addr 变化, 与 DAC 锁存沿同沿 -> 采样竞争。
 //  改为 blk_mem_gen (256Kb -> 8 个 BRAM36, 端口 B 输出寄存/同步读),
 //  初始化文件仍是 coe/sine_32768.coe, 上电即有正弦表。
 //--------------------------------------------------------------------
 DDS_BRAM ram_u1 (
  .clka(clk),          // input  wire       写口时钟 (APB)
  .wea(we),            // input  wire [0:0] 写使能
  .addra(addr_in),     // input  wire [14:0]
  .dina(data_in),      // input  wire [7:0]
  .clkb(clk),          // input  wire       读口时钟
  .addrb(Rom_Addr),    // input  wire [14:0]
  .doutb(Rom_Data)     // output wire [7:0]  同步读, 1 拍延迟
);
endmodule
