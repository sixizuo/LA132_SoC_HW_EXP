`include "../../config.vh"

module intc_top (
	input  wire        apb_pclk   ,
	input  wire        apb_prstn  ,
	input  wire        apb_psel   ,
	input  wire [31:0] apb_paddr  ,
	input  wire        apb_pwrite ,
	input  wire        apb_penable,
	input  wire [31:0] apb_pwdata ,
	output wire [31:0] apb_prdata ,
	output wire        apb_pready ,


	input  wire        int_0      ,
	input  wire        int_1      ,
	input  wire        int_2      ,
	input  wire        int_3      ,
	input  wire        int_4      ,
	input  wire        int_5      ,
	input  wire        int_6      ,
	input  wire        int_7      ,
	output wire        intc_irq   
);

	reg [7:0] int_en  ;
	reg [7:0] int_pol ;
	reg [7:0] int_edge;
	reg [7:0] int_clr ;
	reg [7:0] int_set ;
	reg [31:0] prdata  ;
	
	// Multiplexing register configuration (2bit for one MUL)
	wire wr;
	wire rd;
	wire [7:0] int_in ;
	wire [7:0] int_out;

	assign wr = apb_psel & apb_pwrite & apb_penable;
	assign rd = apb_psel & !apb_pwrite & apb_penable;
	assign apb_pready = apb_penable;


	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			int_en   <= 8'b00000000;
			int_pol  <= 8'b11111111;
			int_edge <= 8'b00000000;
			int_clr  <= 8'b00000000;
			int_set  <= 8'b00000000;
		end else if (wr) begin
			case (apb_paddr[7:0])
				`INT_EN  : int_en   <= apb_pwdata[7:0];
				`INT_POL : int_pol  <= apb_pwdata[7:0];
				`INT_EDGE: int_edge <= apb_pwdata[7:0];
				`INT_CLR : int_clr  <= apb_pwdata[7:0];
				`INT_SET : int_set  <= apb_pwdata[7:0];
				default : ;
			endcase
		end else begin
			int_en   <= int_en  ;
			int_pol  <= int_pol ;
			int_edge <= int_edge;
			int_clr  <= 8'b00000000;
			int_set  <= 8'b00000000;
		end
	end

	always @(*) begin
		if (rd) begin
			case (apb_paddr[7:0])
				`INT_EN  : prdata = {24'b0, int_en};
				`INT_POL : prdata = {24'b0, int_pol};
				`INT_EDGE: prdata = {24'b0, int_edge};
				`INT_OUT : prdata = {24'b0, int_out};
				default : prdata = 32'b0;
			endcase
		end else begin
			prdata = 32'b0;
		end
	end
	assign apb_prdata = prdata;

	assign int_in = {int_7, int_6, int_5, int_4, int_3, int_2, int_1, int_0};

	genvar i;
	generate
		for (i = 0; i <= 7; i = i + 1) begin : int_gen
			one_int_gen intc_int (
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


endmodule // intc_top
