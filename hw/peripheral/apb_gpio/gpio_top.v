`include "../../config.vh"

module gpio_top (
    input  wire        apb_pclk   ,
    input  wire        apb_prstn  ,
    input  wire        apb_psel   ,
    input  wire [31:0] apb_paddr  ,
    input  wire [ 3:0] apb_pstrb  ,
	input  wire        apb_pwrite ,
    input  wire        apb_penable,
    input  wire [31:0] apb_pwdata ,
    output wire [31:0] apb_prdata ,
	output wire        apb_pready ,

    output wire [63:0] gpio_oe    ,
    output wire [63:0] gpio_o     ,
	input  wire [63:0] gpio_i     ,
	
	output wire        gpio_irq   
);
	
	reg [31:0] gpioa_oe;
	reg [31:0] gpioa_o ;
	reg [31:0] gpioa_i ;
	reg [31:0] gpiob_oe;
	reg [31:0] gpiob_o ;
	reg [31:0] gpiob_i ;

	reg [31:0] prdata;

	// ================================================================ for gpio interrupt below
	reg  [31:0] exint_en      ;
	reg  [31:0] exint_pol     ;
	reg  [31:0] exint_edge    ;
	reg  [31:0] exint_two_edge;
	reg  [31:0] exint_clr     ;
	wire [31:0] exint_out     ;
	// ================================================================ for gpio interrupt above

	wire wr;
	wire rd;
	
	wire [31:0] wmask = {{8{apb_pstrb[3]}},{8{apb_pstrb[2]}},{8{apb_pstrb[1]}},{8{apb_pstrb[0]}}};

	assign wr = apb_psel & apb_pwrite & apb_penable;
	assign rd = apb_psel & !apb_pwrite & apb_penable;
	assign apb_pready = apb_penable;

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			gpioa_oe <= 32'b0;
			gpioa_o  <= 32'b0;
			gpiob_oe <= 32'b0;
			gpiob_o  <= 32'b0;
			// ================================================================ for gpio interrupt below
			exint_en       <= 32'b0;
			exint_pol      <= 32'hffff_ffff;
			exint_edge     <= 32'b0;
			exint_clr      <= 32'b0;
			exint_two_edge <= 32'b0;
			// ================================================================ for gpio interrupt above
		end else if (wr) begin
			case ({apb_paddr[7:2], 2'b00})
				`GPIOA_OE : gpioa_oe <= (apb_pwdata & wmask) | (gpioa_oe & ~wmask);
				`GPIOA_O  : gpioa_o  <= (apb_pwdata & wmask) | (gpioa_o  & ~wmask);
				`GPIOB_OE : gpiob_oe <= (apb_pwdata & wmask) | (gpiob_oe & ~wmask);
				`GPIOB_O  : gpiob_o  <= (apb_pwdata & wmask) | (gpiob_o  & ~wmask);
				// ================================================================ for gpio interrupt below
				`EXINT_EN       : exint_en       <= (apb_pwdata & wmask) | (exint_en       & ~wmask);
				`EXINT_POL      : exint_pol      <= (apb_pwdata & wmask) | (exint_pol      & ~wmask);
				`EXINT_EDGE     : exint_edge     <= (apb_pwdata & wmask) | (exint_edge     & ~wmask);
				`EXINT_OUT_CLR  : exint_clr      <= (apb_pwdata & wmask) | (exint_clr      & ~wmask);
				`EXINT_TWO_EDGE : exint_two_edge <= (apb_pwdata & wmask) | (exint_two_edge & ~wmask);
				// ================================================================ for gpio interrupt above
				default : ;
			endcase
		end else begin
			gpioa_oe <= gpioa_oe;
			gpioa_o  <= gpioa_o ;
			gpiob_oe <= gpiob_oe;
			gpiob_o  <= gpiob_o ;
			// ================================================================ for gpio interrupt below
			exint_en       <= exint_en      ;
			exint_pol      <= exint_pol     ;
			exint_edge     <= exint_edge    ;
			exint_clr      <= 32'b0         ;
			exint_two_edge <= exint_two_edge;
			// ================================================================ for gpio interrupt above
		end
	end
	always @(*) begin
		gpioa_i = gpio_i[31:0];
		gpiob_i = gpio_i[63:32];
	end

	always @(*) begin
		if (rd) begin
			case ({apb_paddr[7:2], 2'b00})
				`GPIOA_OE : prdata = gpioa_oe;
				`GPIOA_O  : prdata = gpioa_o ;
				`GPIOA_I  : prdata = gpioa_i ;
				`GPIOB_OE : prdata = gpiob_oe;
				`GPIOB_O  : prdata = gpiob_o ;
				`GPIOB_I  : prdata = gpiob_i ;
				// ================================================================ for gpio interrupt below
				`EXINT_EN       : prdata = exint_en      ;
				`EXINT_POL      : prdata = exint_pol     ;
				`EXINT_EDGE     : prdata = exint_edge    ;
				`EXINT_OUT_CLR  : prdata = exint_out     ;
				`EXINT_TWO_EDGE : prdata = exint_two_edge;
				// ================================================================ for gpio interrupt above
				default : prdata = 32'b0;
			endcase
		end else begin
			prdata = 32'b0;
		end
	end
//	assign apb_prdata = prdata;
    assign apb_prdata = prdata >> {apb_paddr[1:0], 3'b000};
	assign gpio_oe = {gpiob_oe, gpioa_oe};
	assign gpio_o = {gpiob_o, gpioa_o};
	// ================================================================ for gpio interrupt below
	wire [31:0] exint_in = {gpiob_i[15:0], gpioa_i[15:0]};

	genvar i;
	generate
		for (i = 0; i < 32; i = i + 1) begin : gen_exint
		one_exint_gen exint_num (.clk(apb_pclk), .rst(!apb_prstn), .exint_en(exint_en[i]), .exint_pol(exint_pol[i]), 
								.exint_edge(exint_edge[i]), .exint_two_edge(exint_two_edge[i]), .exint_in(exint_in[i]), 
								.exint_clr(exint_clr[i]), .exint_out(exint_out[i]));
		end
	endgenerate

	assign gpio_irq = |exint_out;
	// ================================================================ for gpio interrupt above

//	ila_dma ila (
//	.clk(apb_pclk), // input wire clk
//	.probe0(apb_penable), // input wire [0:0]  probe0  
//	.probe1(apb_psel), // input wire [0:0]  probe1 
//	.probe2(apb_paddr), // input wire [31:0]  probe2 
//	.probe3(wmask), // input wire [31:0]  probe3 
//	.probe4(apb_prdata), // input wire [31:0]  probe4 
//	.probe5(apb_pready), // input wire [0:0]  probe5 
//	.probe6(apb_pwrite), // input wire [0:0]  probe6 
//	.probe7(apb_pstrb) // input wire [3:0]  probe7
//);

endmodule // gpio_top
