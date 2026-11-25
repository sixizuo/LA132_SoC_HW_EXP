//=====================================================================
//  intc_top16.v  ——  实验一：APB 中断控制器（16 路，位宽参数化）
//---------------------------------------------------------------------
//  来源 : hw/peripheral/apb_intc/intc_top.v（8 路固定写法）
//  改动 :
//    1) 输入从 int_0~int_7 改为 16 位向量 int_in（端口参数化 INT_NUM）；
//    2) 寄存器 int_en/pol/edge/clr/set 与 int_out 全部按 INT_NUM 位宽；
//    3) generate 循环上界改为 INT_NUM；
//    4) 读回值按 (32-INT_NUM) 显式零扩展，不写死 24'b0；
//    5) 寄存器偏移与 one_int_gen 行为完全不变，向下兼容 8 路软件。
//  地址 : APB 编号 2，基址 0x3002_0000，偏移定义见 config.vh
//=====================================================================
`include "../../config.vh"

module intc_top16 #(
	parameter INT_NUM = 16
) (
	input  wire                    apb_pclk   ,
	input  wire                    apb_prstn  ,
	input  wire                    apb_psel   ,
	input  wire [31:0]             apb_paddr  ,
	input  wire                    apb_pwrite ,
	input  wire                    apb_penable,
	input  wire [31:0]             apb_pwdata ,
	output wire [31:0]             apb_prdata ,
	output wire                    apb_pready ,

	input  wire [INT_NUM-1:0]      int_in     ,
	output wire                    intc_irq
);

	reg  [INT_NUM-1:0] int_en  ;
	reg  [INT_NUM-1:0] int_pol ;
	reg  [INT_NUM-1:0] int_edge;
	reg  [INT_NUM-1:0] int_clr ;
	reg  [INT_NUM-1:0] int_set ;
	reg  [31:0]        prdata  ;

	wire [INT_NUM-1:0] int_out ;

	wire wr;
	wire rd;

	assign wr = apb_psel &  apb_pwrite & apb_penable;
	assign rd = apb_psel & !apb_pwrite & apb_penable;
	assign apb_pready = apb_penable;

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			int_en   <= {INT_NUM{1'b0}};
			int_pol  <= {INT_NUM{1'b1}};
			int_edge <= {INT_NUM{1'b0}};
			int_clr  <= {INT_NUM{1'b0}};
			int_set  <= {INT_NUM{1'b0}};
		end else if (wr) begin
			case (apb_paddr[7:0])
				`INT_EN  : int_en   <= apb_pwdata[INT_NUM-1:0];
				`INT_POL : int_pol  <= apb_pwdata[INT_NUM-1:0];
				`INT_EDGE: int_edge <= apb_pwdata[INT_NUM-1:0];
				`INT_CLR : int_clr  <= apb_pwdata[INT_NUM-1:0];
				`INT_SET : int_set  <= apb_pwdata[INT_NUM-1:0];
				default : ;
			endcase
		end else begin
			int_clr <= {INT_NUM{1'b0}};
			int_set <= {INT_NUM{1'b0}};
		end
	end

	always @(*) begin
		if (rd) begin
			case (apb_paddr[7:0])
				`INT_EN  : prdata = {{(32-INT_NUM){1'b0}}, int_en  };
				`INT_POL : prdata = {{(32-INT_NUM){1'b0}}, int_pol };
				`INT_EDGE: prdata = {{(32-INT_NUM){1'b0}}, int_edge};
				`INT_OUT : prdata = {{(32-INT_NUM){1'b0}}, int_out };
				default : prdata = 32'b0;
			endcase
		end else begin
			prdata = 32'b0;
		end
	end
	assign apb_prdata = prdata;

	genvar i;
	generate
		for (i = 0; i < INT_NUM; i = i + 1) begin : g_int
			one_int_gen u_one (
				.clk      (apb_pclk   ),
				.rst      (!apb_prstn ),
				.int_en   (int_en[i]  ),
				.int_pol  (int_pol[i] ),
				.int_edge (int_edge[i]),
				.int_in   (int_in[i]  ),
				.int_clr  (int_clr[i] ),
				.int_set  (int_set[i] ),
				.int_out  (int_out[i] )
			);
		end
	endgenerate

	assign intc_irq = |int_out;

endmodule
