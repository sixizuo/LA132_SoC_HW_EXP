module iic_sync_module #(
	parameter WIDTH   = 1,
	parameter NEGEDGE = 1
)(
	input  wire                clock   ,
	input  wire [WIDTH - 1 :0] async_in,
	output wire [WIDTH - 1 :0] sync_out
);

	reg [WIDTH - 1 :0] sync_stage0;
	reg [WIDTH - 1 :0] sync_stage1;

	generate
		if (NEGEDGE) begin: stage0_negedge
			always @(negedge clock) begin // falling edge
				sync_stage0 <= async_in;
			end
		end else begin: stage0_posedge
			always @(posedge clock) begin // rising edge
				sync_stage0 <= async_in;
			end
		end
	endgenerate

	always @(posedge clock) begin // rising edge --> reduce sync delay
		sync_stage1 <= sync_stage0;
	end
	assign sync_out = sync_stage1;

endmodule // iic_sync_module
