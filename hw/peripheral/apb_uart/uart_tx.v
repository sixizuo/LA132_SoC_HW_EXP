module uart_tx (
	input  wire       clk         ,
	input  wire       rstn        ,
	input  wire       tx_start    , // start sending signal
	input  wire       b_tick      , // baudrate tick
	input  wire [7:0] d_in        , // input data
	input  wire       parity_check, // parity check
	output wire       tx          , // output rs232 data
	output reg        tx_done       // transfer finished
);

	// status definition
	localparam [1:0] IDLE_ST  = 2'b00;
	localparam [1:0] START_ST = 2'b01;
	localparam [1:0] DATA_ST  = 2'b11;
	localparam [1:0] STOP_ST  = 2'b10;
	
	// internal signals
	reg [1:0] current_state; 
	reg [1:0] next_state   ; 
	reg [3:0] b_reg        ; // baudrate tick counter
	reg [3:0] b_next       ; 
	reg [2:0] count_reg    ; // data bit counter
	reg [2:0] count_next   ; 
	reg [7:0] data_reg     ; // data register
	reg [7:0] data_next    ; 
	reg tx_reg             ; // output data reg
	reg tx_next            ;
	
	// status machine  
	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			current_state <= IDLE_ST;
			b_reg         <= 4'b0;
			count_reg     <= 3'b0;
			data_reg      <= 8'b0;
			tx_reg        <= 1'b1;
		end else begin
			current_state <= next_state;
			b_reg         <= b_next    ;
			count_reg     <= count_next;
			data_reg      <= data_next ;
			tx_reg        <= tx_next   ;
		end
	end

	// ================================================================ parity check below
	assign eor_value = d_in[6] ^ d_in[5] ^ d_in[4] ^ d_in[3] ^ d_in[2] ^ d_in[1] ^ d_in[0];
	// ================================================================ parity check above

	// next status logic
	always @(*) begin
		next_state = current_state;
		b_next     = b_reg        ;
		count_next = count_reg    ;
		data_next  = data_reg     ;
		tx_next    = tx_reg       ;
		tx_done    = 1'b0         ;

		case (current_state)
			IDLE_ST: begin
				tx_next = 1'b1;
				if (tx_start) begin
					next_state = START_ST;
					b_next = 4'b0;
					// data_next = d_in;
					// ================================================================ parity check below
					if (parity_check == 1'b0) begin
						data_next = d_in;
					end else begin
						data_next[6:0] = d_in[6:0];
						if (eor_value) begin
							data_next[7] = 1'b0;
						end else begin
							data_next[7] = 1'b1;
						end
					end
					// ================================================================ parity check above
				end
			end
			
			START_ST: begin // send start bit
				tx_next = 1'b0;
				if (b_tick) begin
					if (b_reg == 3) begin
						next_state = DATA_ST;
						b_next = 4'b0;
						count_next = 3'b0;
					end else begin
						b_next = b_reg + 1'b1;
					end
				end
			end
			
			DATA_ST: begin // send data serially
				tx_next = data_reg[0];
				if (b_tick) begin
					if (b_reg == 3) begin
						b_next = 4'b0;
						data_next = data_reg >> 1'b1;
						if (count_reg == 7) begin // after sending 8bit, go to 'STOP_ST'
							next_state = STOP_ST;
						end else begin // count the number of data bits already sent
							count_next = count_reg + 1'b1;
						end
					end else begin
						b_next = b_reg + 1'b1;
					end
				end
			end
			
			STOP_ST: begin // send stop bit
				tx_next = 1'b1; // send one stop bit
				if (b_tick) begin
					if (b_reg == 3) begin
						next_state = IDLE_ST;
						tx_done = 1'b1;
					end else begin
						b_next = b_reg + 1'b1;
					end
				end
			end
		endcase
	end
	
	assign tx = tx_reg;

endmodule // uart_tx
