module one_exint_gen (
	input  wire clk           ,
	input  wire rst           ,
	input  wire exint_en      ,
	input  wire exint_pol     ,
	input  wire exint_edge    ,
	input  wire exint_two_edge,
	input  wire exint_in      ,
	input  wire exint_clr     ,
	output wire exint_out     
);

	reg exint_delay;
	reg exint_lt;
	reg count;

	wire inv_int;
	wire level_int;

	always @(posedge clk) begin
		if (rst) begin
			exint_delay <= 1'b0;
		end else begin
			exint_delay <= exint_in;
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			count <= 1'b0;
		end	else if (exint_in != exint_delay && exint_in == exint_pol) begin
			count <= 1'b1;
		end else begin
			count <= count;
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			exint_lt <= 1'b0;
		end	else if (exint_two_edge == 1'b1 && exint_in != exint_delay && count == 1'b1) begin//双边沿
			exint_lt <= 1'b1;
		end	else if (exint_two_edge == 1'b0 && exint_in != exint_delay && exint_in == exint_pol && count == 1'b1) begin//pol=1上升沿，0下降沿
			exint_lt <= 1'b1;
		end else if (exint_clr) begin
			exint_lt <= 1'b0;
		end else begin
			exint_lt <= exint_lt;
		end
	end

	assign inv_int = !(exint_pol ^ exint_in);
	assign level_int = exint_edge ? exint_lt : inv_int;
	assign exint_out = exint_en & level_int;

endmodule // one_exint_gen
