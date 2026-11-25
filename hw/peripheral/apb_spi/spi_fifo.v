module spi_fifo #(
	parameter dw = 8
) (
	input             clk  ,
	input             rstn ,
	input             wr   ,
	input  [dw - 1:0] din  ,
	input             rd   ,
	output [dw - 1:0] dout ,
	input             clr  ,
	output            full ,
	output            empty
);

	reg [dw - 1:0] mem[0:3];
	reg [1:0] wp;
	reg [1:0] rp;
	reg gb;

	wire [1:0] wp_p1;
	wire [1:0] rp_p1;
	
	assign wp_p1 = wp + 1'b1;
	assign rp_p1 = rp + 1'b1;

	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			wp <= 2'b0;
		end else if (clr) begin
			wp <= 2'b0;
		end else if (wr) begin
			wp <= wp_p1;
		end else begin
			wp <= wp;
		end
	end

	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin 
			rp <=  2'b0;
		end else if (clr) begin
			rp <=  2'b0;
		end else if (rd) begin
			rp <=  rp_p1;
		end else begin
			rp <= rp;
		end
	end

	// fifo input
	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin 
			mem[0] <= 'b0;
			mem[1] <= 'b0;
			mem[2] <= 'b0;
			mem[3] <= 'b0;
		end else if (wr) begin 
			mem[wp] <= din;
		end
	end

	// fifo output
	assign dout = mem[rp];
	
	// fifo status
	assign empty = (wp == rp) & !gb;
	assign full  = (wp == rp) & gb;

	// guard bit
	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			gb <= 1'b0;
		end else if (clr) begin
			gb <= 1'b0;
		end else if ((wp_p1 == rp) & wr) begin
			gb <= 1'b1;
		end else if (rd) begin
			gb <= 1'b0;
		end else begin
			gb <= gb;
		end
	end

endmodule // spi_fifo
