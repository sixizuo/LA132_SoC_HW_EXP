module baudgen (
	input  wire       clk          ,
	input  wire       rstn         ,
	input  wire [1:0] baudtick_ctrl,
	output wire       baudtick     
);

	reg [9:0] counting_targets;
	reg [21:0] count_reg;

	wire [21:0] count_next;
	
	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			count_reg <= 22'b0;
		end else begin
			count_reg <= count_next;
		end
	end

	// baudrate = 9600 = 32 MHz / (832 * 4)
	// baudrate = 19200 = 32 MHz / (416 * 4)
	// baudrate = 38400 = 32 MHz / (208 * 4)
	// baudrate = 115200 = 32 MHz / (69 * 4)
	always @(*) begin
		case (baudtick_ctrl)
			2'b00 : counting_targets = 832;
			2'b01 : counting_targets = 416;
			2'b10 : counting_targets = 208;
			2'b11 : counting_targets = 69 ;
		endcase
	end

	assign count_next = ((count_reg == counting_targets) ? 22'b0 : count_reg + 1'b1);
	assign baudtick = ((count_reg == counting_targets) ? 1'b1 : 1'b0);
	
endmodule // baudgen
