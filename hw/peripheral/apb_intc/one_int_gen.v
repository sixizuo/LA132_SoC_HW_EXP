module one_int_gen (
	input  wire clk     ,
	input  wire rst     ,

	input  wire int_en  ,
	input  wire int_pol ,
	input  wire int_edge,
	input  wire int_in  ,
	input  wire int_clr ,
	input  wire int_set ,
	output wire int_out 
);

	reg int_delay;
	reg int_lt;
	reg count;
	reg int_force;

	wire inv_int;
	wire level_int; 

	always @(posedge clk) begin
		if (rst) begin
			int_force <= 1'b0;
		end else begin
			if (int_set) begin
				int_force <= 1'b1;
			end else if (int_clr) begin
				int_force <= 1'b0;
			end else begin
				int_force <= int_force;
			end
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			int_delay <= 1'b0;
		end else begin
			int_delay <= int_in;
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			count <= 1'b0;
		end	else if (int_in != int_delay && int_in == int_pol) begin
			count <= 1'b1;
		end else begin
			count <= count;
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			int_lt <= 1'b0;
		end	else if (int_in != int_delay && int_in == int_pol && count == 1'b1) begin
			int_lt <= 1'b1;
		end else if (int_clr) begin
			int_lt <= 1'b0;
		end else begin
			int_lt <= int_lt;
		end
	end

	assign inv_int = !(int_pol ^ int_in);
	assign level_int = int_edge ? int_lt : inv_int;
	assign int_out = (int_en & level_int) | int_force;

endmodule // one_int_gen
