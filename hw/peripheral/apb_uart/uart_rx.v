module uart_rx (
	input  wire       clk         ,
	input  wire       rstn        ,
	input  wire       b_tick      , // baudrate tick
	input  wire       rx          , // input rs232 data
	input  wire       parity_check, // parity check
	output reg        rx_done     , // transfer completed
	output wire [7:0] dout          // output data
);

	// status definition
	localparam [1:0] IDLE_ST  = 2'b00;
	localparam [1:0] START_ST = 2'b01;
	localparam [1:0] DATA_ST  = 2'b10;
	localparam [1:0] STOP_ST  = 2'b11;

	// internal signals
	reg [1:0] current_state;
	reg [1:0] next_state   ;
	reg [3:0] b_reg        ; // baudrate tick counter
	reg [3:0] b_next       ;
	reg [2:0] count_reg    ; // data bit counter
	reg [2:0] count_next   ;
	reg [7:0] data_reg     ; // data register
	reg [7:0] data_next    ;

	// status machine
	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			current_state <= IDLE_ST;
			b_reg         <= 4'b0;
			count_reg     <= 3'b0;
			data_reg      <= 8'b0;
		end else begin
			current_state <= next_state;
			b_reg         <= b_next    ;
			count_reg     <= count_next;
			data_reg      <= data_next ;
		end
	end

	// next status logic
	always @(*) begin
		next_state = current_state;
		b_next     = b_reg        ;
		count_next = count_reg    ;
		data_next  = data_reg     ;
		rx_done    = 1'b0         ;

		case (current_state)
			IDLE_ST: begin
				if (!rx) begin
					next_state = START_ST;
					b_next = 4'b0;
				end
			end
			START_ST: begin
				if (b_tick) begin
					// 2026-10-31 fix: was "b_reg == 3" (4 ticks = 1 full bit),
					// which put the first sample at start_edge + 2 bits, i.e.
					// exactly on the b0/b1 boundary. Board bit time is 8.75us
					// (114286 baud) vs PC 8.68us (115200), 0.79% slower, so the
					// sample slipped into b1 and the byte was read as
					// (b>>1)|0x80 (whole frame shifted by one bit).
					// "b_reg == 1" (2 ticks = 0.5 bit) puts samples at
					// +0.5/+1.5/.../+9.5 bit, the centre of every bit.
					if (b_reg == 1) begin
						next_state = DATA_ST;
						b_next = 4'b0;
						count_next = 3'b0;
					end else begin
						b_next = b_reg + 1'b1;
					end
				end
			end
			DATA_ST: begin
				if (b_tick) begin
					if (b_reg == 3) begin
						b_next = 4'b0;
						data_next = {rx, data_reg[7:1]};
						if (count_next == 7) begin // after receiving 8bit, go to STOP_ST
							next_state = STOP_ST;
						end else begin
							count_next = count_reg + 1'b1;
						end
					end else begin
						b_next = b_reg + 1'b1;
					end
				end
			end
			STOP_ST: begin // one stop bit
				if (b_tick) begin
					if (b_reg == 3) begin
						next_state = IDLE_ST;
						// rx_done = 1'b1;
						// ================================================================ parity check below
						if (parity_check == 1'b0) begin
							rx_done = 1'b1;
						end else begin
							if ((data_reg[7] ^ data_reg[6] ^ data_reg[5] ^ data_reg[4] ^ data_reg[3] ^
								data_reg[2] ^ data_reg[1] ^ data_reg[0]) == 1'b1) begin
								rx_done = 1'b1;
							end else begin
								rx_done = 1'b0;
							end
						end
						// ================================================================ parity check above
					end else begin
						b_next = b_reg + 1'b1;
					end
				end
			end
		endcase
	end

	assign dout = data_reg;
	
endmodule // uart_rx
