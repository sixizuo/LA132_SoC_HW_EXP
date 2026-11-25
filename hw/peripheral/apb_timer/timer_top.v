`include "../../config.vh"

module timer_top (
	input  wire        apb_pclk   ,
	input  wire        apb_prstn  ,
	input  wire        apb_psel   ,
	input  wire [31:0] apb_paddr  ,
	input  wire        apb_pwrite ,
	input  wire        apb_penable,
	input  wire [31:0] apb_pwdata ,
	output wire [31:0] apb_prdata ,
	output wire        apb_pready ,

	output wire        timer_irq  
);

	reg start;
	reg int_en;
	reg periodic;
	reg [31:0] count;
	reg [31:0] compare;
	reg [31:0] step;
	reg timer_int;
	reg [31:0] prdata;

	wire wr;
	wire rd;
	wire int_trig;

	assign wr = apb_penable & apb_psel & apb_pwrite;
	assign rd = apb_penable & apb_psel &!apb_pwrite;
	assign apb_pready = apb_penable;
	
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			start    <= 1'b0;
			int_en   <= 1'b0;
			periodic <= 1'b0;
		end else if (wr && (apb_paddr[7:0] == `TIMER_CFG)) begin
			start    <= apb_pwdata[0];
			int_en   <= apb_pwdata[1];
			periodic <= apb_pwdata[2];
		end else begin
			start    <= start   ;
			int_en   <= int_en  ;
			periodic <= periodic;
		end
	end

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			count <= 32'h0;
		end else if (wr && (apb_paddr[7:0] == `TIMER_CNT) && !start) begin
			count <= apb_pwdata;
		end else if (start) begin
			count <= count + 1'b1;
		end else if (start == 1'b0) begin
			count <= 32'b0;
		end else begin
			count <= count;
		end
	end

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			compare <= 32'hffff_ffff;
		end else if (wr && (apb_paddr[7:0] == `TIMER_CMP) && !start) begin
			compare <= apb_pwdata;
		end else if (periodic & int_trig) begin
			compare <= compare + step;
		end else begin
			compare <= compare;
		end
	end

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			step <= 32'b0;
		end else if (wr && (apb_paddr[7:0] == `TIMER_STP) && !start) begin
			step <= apb_pwdata;
		end else begin
			step <= step;
		end
	end

	assign int_trig = (count == compare) && start;

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			timer_int <= 1'b0;
		end else if (wr && (apb_paddr[7:0] == `TIMER_CFG) && apb_pwdata[8]) begin
			timer_int <= 1'b0; // write pwdata[8] = 1 to clear the interrupt flag bit
		end else if (int_trig) begin
			timer_int <= 1'b1;
		end else begin
			timer_int <= timer_int;
		end
	end

	always @(*) begin
		if (rd) begin
			case (apb_paddr[7:0])
				`TIMER_CFG: prdata = {23'b0, timer_int, 5'b0, periodic, int_en, start};
				`TIMER_CNT: prdata = count;
				`TIMER_CMP: prdata = compare;
				`TIMER_STP: prdata = step;
				default : prdata = 32'b0;
			endcase
		end else begin
			prdata = 32'b0;
		end
	end
	assign apb_prdata = prdata;

	assign timer_irq = timer_int & int_en;

endmodule // timer_top
