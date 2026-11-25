`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/13 11:21:38
// Design Name: 
// Module Name: DDS
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


module DDS#(
parameter ADDR_WIDTH = 15,
parameter DATA_WIDTH = 8
)(
input clk ,/*DAC系统时钟*/
input rst_n ,/*系统复位*/
input EN ,/*DDS模块使能*/
input [ADDR_WIDTH-1:0] Fword ,/*频率控制字*/
input [ADDR_WIDTH-1:0] Pword ,/*相位控制字*/
input [2:0] Aword ,/*幅度控制字*/
input [DATA_WIDTH-1:0] Rom_Data ,/*ROM输出值*/
output reg [ADDR_WIDTH-1:0] Rom_Addr ,/*ROM地址*/
output DA_WRT ,/*DA数据输出时钟*/
output [DATA_WIDTH-1:0] DA_Data /*D输出输出A*/
);
reg [31:0] Fre_acc;
/*----------DAC 数据输出寄存 (2026-11-04 修正) ----------*/
//  原来 DA_Data 直接取 Rom_Data>>>Aword。DDS_RAM 早期实现是异步读,
//  Rom_Addr 与 DAC 锁存沿 (DA_WRT) 同一时钟沿变化, 查表数据要几 ns 才
//  稳定 -> DAC 在数据翻转窗口里采样, 波形出现重影/毛刺。
//  这里在 dac_clk 下降沿打一拍: 地址在上升沿更新 -> 整个高电平半周期给
//  查表数据稳定 -> 上升沿时 DAC 采到的一定是稳定值。
reg [DATA_WIDTH-1:0] dac_data_r;
assign DA_Data = dac_data_r;
/*---------------相位累加器------------------*/
always @(posedge clk or negedge rst_n)
if(!rst_n)
	Fre_acc <= 32'd0;
else if(!EN)
	Fre_acc <= 32'd0;
else
	Fre_acc <= Fre_acc + Fword;
/*----------生成查找表地址---------------------*/
always @(posedge clk or negedge rst_n)
if(!rst_n)
	Rom_Addr <= 'd0;
else if(!EN)
	Rom_Addr <= 'd0;
else
//Rom_Addr <= Fre_acc[31:32-ADDR_WIDTH] + Pword;//
	Rom_Addr <= Fre_acc[ADDR_WIDTH-1:0] + Pword;
/*----------DAC 数据寄存 (下降沿) ----------*/
always @(negedge clk or negedge rst_n)
if(!rst_n)
	dac_data_r <= {DATA_WIDTH{1'b0}};
else if(!EN)
	dac_data_r <= {DATA_WIDTH{1'b0}};
else
	dac_data_r <= Rom_Data>>>Aword;
/*----------输出DA时钟----------*/
//  不再用 EN 组合门控时钟 (门控时钟直接出引脚会产生毛刺, 可能误锁存一
//  个采样点); 关闭时数据被清零, DAC 采到 0。
assign DA_WRT = clk;
endmodule
