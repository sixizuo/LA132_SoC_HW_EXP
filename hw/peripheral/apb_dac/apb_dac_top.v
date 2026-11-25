`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/17 10:59:10
// Design Name: 
// Module Name: apb_dac_top
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


module dac_9708_top (
    input  wire        apb_pclk   ,
    input  wire        apb_prstn  ,
    input  wire        apb_psel   ,
    input  wire [31:0] apb_paddr  ,
    input  wire        apb_pwrite ,
    input  wire        apb_penable,
    input  wire [3:0]  apb_pstrb  ,
    input  wire [31:0] apb_pwdata ,
    output wire [31:0] apb_prdata ,
	output wire        apb_pready ,
	
	output [7:0] dac_data,
    output dac_clk        
);
    reg [14:0] Fword;
    reg [14:0] Pword;
    reg [2:0] Aword;
    reg [14:0] addr_in;
    reg [7:0] data_in;
    reg dac_we;
	reg [31:0] div_freq;
	reg en;

	reg [31:0] prdata;

	wire wr;
	wire rd;
	wire start;
	wire direction;

	assign wr = apb_penable & apb_psel & apb_pwrite;
	assign rd = apb_penable & apb_psel &!apb_pwrite;
	assign apb_pready = apb_penable;

//---------------------------------------------------------------------
//  APB 字节选通 (2026-11-04 修正)
//---------------------------------------------------------------------
//  本 SoC 的 CPU 写波形 RAM 用的是字节写 (`*(volatile unsigned char*)`),
//  AXI->APB 桥只透传 wstrb 与未对齐地址: 数据放在**与地址低 2 位对应的
//  字节通道**里。原实现无条件取 pwdata[7:0] 且不看 pstrb, 于是只有
//  addr[1:0]==0 的字节写数据正确, 其余都写入 0 ->
//      DDS 输出波形出现 "间隔 0 / 重影", 且当 Fword 为 4 的倍数时
//      (地址恒落在 4 的倍数上) 恰好看不出来。
//  这里按 pstrb 选通道取字节, 并把地址低 2 位按通道补齐 (地址本身已
//  字节对齐时等价于直通)。
//---------------------------------------------------------------------
	wire [1:0] byte_off = apb_pstrb[0] ? 2'd0 :
	                      apb_pstrb[1] ? 2'd1 :
	                      apb_pstrb[2] ? 2'd2 : 2'd3;

	wire [7:0] wr_byte  = apb_pstrb[0] ? apb_pwdata[7:0]   :
	                      apb_pstrb[1] ? apb_pwdata[15:8]  :
	                      apb_pstrb[2] ? apb_pwdata[23:16] : apb_pwdata[31:24];
	
//	assign dac_we = apb_penable & apb_psel & apb_pwrite & apb_paddr[15];
	
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			div_freq <= 32'b1;
			en     <= 32'b0;
			Fword <= 'h32;
			Pword <= 'h0;
			Aword <='h0;
			addr_in <= 15'd0;
			data_in <= 8'd0;
			dac_we  <= 1'b0;
		end else if (wr) begin
			casex (apb_paddr[15:0])
				`DAC_DIV_FREQ : div_freq <= apb_pwdata;
				`DAC_EN     : en     <= apb_pwdata[0];
				`DAC_FWORD  : Fword <= apb_pwdata[14:0];
				`DAC_PWORD  : Pword <= apb_pwdata[14:0];
				`DAC_AWORD  : Aword <= apb_pwdata[2:0];
				`DAC_DATA  : begin
					addr_in <= apb_paddr[14:0] | {12'd0, byte_off};
					data_in <= wr_byte;
					dac_we  <= |apb_pstrb;
				end
				default : ;
			endcase
		end else begin
			div_freq <= div_freq;
			en     <= en    ;
			Fword <= Fword;
			Pword <= Pword;
			Aword <= Aword;
			addr_in <= 'd0;
			data_in <= 'd0;
			dac_we<=0;
		end
	end

	always @(*) begin
		if (rd) begin
			case (apb_paddr[15:0])
				`DAC_DIV_FREQ : prdata = div_freq;
				`DAC_FWORD     : prdata = {17'd0,Fword};
				`DAC_PWORD    : prdata = {17'd0,Pword};
				`DAC_AWORD    : prdata = {29'd0,Aword};
				`DAC_EN       : prdata = {30'd0,en};
				default: prdata = 32'b0;
			endcase
		end else begin
			prdata = 32'b0;
		end
	end
	assign apb_prdata = prdata;
	
	reg DAC_CLK_DIV;
	reg [31:0] cnt;
	always @(posedge apb_pclk or negedge apb_prstn) begin
	if(~apb_prstn)
	   begin
	   DAC_CLK_DIV <='b0;
	   cnt <= 'b0;
	   end
	   else if(cnt<div_freq)
	       cnt<=cnt+1;
	       else begin
	       cnt<=0;
	       DAC_CLK_DIV<=~DAC_CLK_DIV;
	       end
	end
DAC_TOP #(15,8) U_DAC(
.clk(apb_pclk)
,.rst_n(apb_prstn)
,.EN(en)
,.Fword(Fword)
,.Pword(Pword)
,.Aword(Aword)
,.addr_in(addr_in)
,.data_in(data_in)
,.we(dac_we)
,.dac_clk(DAC_CLK_DIV)
,.DA_WRT(dac_clk)
,.DA_Data(dac_data)
);
endmodule // pwm_top
