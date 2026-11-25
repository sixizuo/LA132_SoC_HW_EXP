`include "../../config.vh"

module iic_master_bit_ctrl #(
	parameter IIC_CMD_NOP   = 4'b0000,
	parameter IIC_CMD_START = 4'b0001,
	parameter IIC_CMD_STOP  = 4'b0010,
	parameter IIC_CMD_READ  = 4'b0100,
	parameter IIC_CMD_WRITE = 4'b1000
) (
	input  wire        clk       , // clock
	input  wire        rstn      , // active low

	// control inputs
	input  wire        ena       , // iic core work enable
	input  wire [15:0] clk_cnt   , // iic clock division value
	input  wire [3:0]  cmd       , // iic command
	input  wire        fsm_busy  ,

	// control outputs
	output wire        clk_en    , // iic clock mutiply 4
	output reg         busy      , // iic bus busy
	output reg         al        , // iic bus arbitration lost
	output reg         cmd_complt, // iic command complete flag

	// data signals
	input  wire        din       , 
	output reg         dout      , 
	
	// iic signals
	input  wire        scl_i     , // iic clock line input
	output reg         scl_oen   , // iic clock line output enable
	input  wire        sda_i     , // iic data line input
	output reg         sda_oen     // iic data line output enable
);

	reg [15:0] cnt; // iic clock division counter

	// synchronized scl and sda input
	reg scl_i_m1;
	reg sda_i_m1;
	reg scl_i_m2;
	reg sda_i_m2;

	reg sta_cond; // start condition
	reg sto_cond; // stop condition

	reg scl_oen_m1; // cache scl_oen for one beat
	reg din_m1; // cache din for one beat
	reg cmd_stop; // stop command status
	reg sda_chk; // check sda output: multi-master arbitration

	reg [16:0] bit_status; // iic bit status

	wire slave_wait; // slave ready

	// generate iic clk
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
			cnt <= 16'h0;
		end else if (!(|cnt) || !ena) begin
			cnt <= clk_cnt; // if clk_cnt is 0x13, corresponding to iic clock 100k
        end else if (!slave_wait) begin
			cnt <= cnt - 1'b1;
		end
	end
    assign clk_en = !(|cnt) && !slave_wait; // divide clk by clk_cnt to obtain clk_en: clk_en = clk / clk_cnt

	// synchronize scl and sda input
	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			scl_i_m1 <= 1'b1;
			sda_i_m1 <= 1'b1;
			scl_i_m2 <= 1'b1;
			sda_i_m2 <= 1'b1;
		end else begin
			scl_i_m1 <= scl_i   ;
			sda_i_m1 <= sda_i   ;
			scl_i_m2 <= scl_i_m1;
			sda_i_m2 <= sda_i_m1;
		end
	end

	// detect start condition: detect falling edge on sda while scl is high
	// detect stop condition: detect rising edge on sda while scl is high
	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			sta_cond <= 1'b0;
			sto_cond <= 1'b0;
		end else begin
			sta_cond <= !sda_i_m1 & sda_i_m2 & scl_i_m1;
			sto_cond <= sda_i_m1 & !sda_i_m2 & scl_i_m1;
		end
	end

	// generate dout signal: store sda on rising edge of scl
	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			dout <= 8'b0;
		end else if (scl_i_m1 & !scl_i_m2) begin
			dout <= sda_i_m1;
		end
	end

	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			scl_oen_m1 <= 1'b1;
		end else begin
			scl_oen_m1 <= scl_oen;
		end
	end

	assign slave_wait = scl_oen_m1 && !scl_i_m1;
	// when scl_oen_m1 is 1, scl is in z state, the specific value depends on the external circuit, at this point, scl_i_m1 is 0 means the slave is not ready

	// generate iic bus busy signal
	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			busy <= 1'b0;
		end else begin
			busy <= (sta_cond | busy) & !sto_cond; // if start signal detected, end signal not yet detected, busy is 1
		end
	end

	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			cmd_stop <= 1'b0;
		end else if (clk_en) begin
			cmd_stop <= cmd == IIC_CMD_STOP;
		end
	end

	/*
		generate iic bus arbitration lost signal
		aribitration lost when:
			1. master drives sda high, but the iic data bus(sda) is low
			2. stop detected while not requested
	*/
	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			al <= 1'b0;
		end else begin
			al <= (sda_chk & !sda_i_m1 & sda_oen) | (|bit_status & sto_cond & !cmd_stop);
		end
	end

	// generate status machine
	localparam [16:0] idle    = 17'b0_0000_0000_0000_0000;
	localparam [16:0] start_a = 17'b0_0000_0000_0000_0001;
	localparam [16:0] start_b = 17'b0_0000_0000_0000_0010;
	localparam [16:0] start_c = 17'b0_0000_0000_0000_0100;
	localparam [16:0] start_d = 17'b0_0000_0000_0000_1000;
	localparam [16:0] start_e = 17'b0_0000_0000_0001_0000;
	localparam [16:0] stop_a  = 17'b0_0000_0000_0010_0000;
	localparam [16:0] stop_b  = 17'b0_0000_0000_0100_0000;
	localparam [16:0] stop_c  = 17'b0_0000_0000_1000_0000;
	localparam [16:0] stop_d  = 17'b0_0000_0001_0000_0000;
	localparam [16:0] rd_a    = 17'b0_0000_0010_0000_0000;
	localparam [16:0] rd_b    = 17'b0_0000_0100_0000_0000;
	localparam [16:0] rd_c    = 17'b0_0000_1000_0000_0000;
	localparam [16:0] rd_d    = 17'b0_0001_0000_0000_0000;
	localparam [16:0] wr_a    = 17'b0_0010_0000_0000_0000;
	localparam [16:0] wr_b    = 17'b0_0100_0000_0000_0000;
	localparam [16:0] wr_c    = 17'b0_1000_0000_0000_0000;
	localparam [16:0] wr_d    = 17'b1_0000_0000_0000_0000;

	always @(posedge clk or negedge rstn) begin
		if (!rstn | al) begin
			bit_status <= idle;
			cmd_complt <= 1'b0;
			scl_oen    <= 1'b1;
			sda_oen    <= 1'b1;
			sda_chk    <= 1'b0;
			din_m1     <= 1'b0;
		end else begin
			cmd_complt <= 1'b0;
			if (clk_en) begin
				din_m1 <= din;
				case (bit_status)
					idle: begin
						case (cmd)
							IIC_CMD_START : bit_status <= start_a;
							IIC_CMD_STOP  : bit_status <= stop_a;
							IIC_CMD_WRITE : bit_status <= wr_a;
							IIC_CMD_READ  : bit_status <= rd_a;
							default : bit_status <= idle;
						endcase
						scl_oen <= scl_oen; // keep scl_oen in same state
						sda_oen <= sda_oen; // keep sda_oen in same state
						sda_chk <= 1'b0   ; // don't check sda_oen output
					end

					// start
					start_a: begin
						bit_status <= start_b;
						scl_oen    <= scl_oen; // keep scl_oen in same state 
						sda_oen    <= 1'b1   ; // set sda_oen high
						sda_chk    <= 1'b0   ; // don't check sda_oen output
					end
					start_b: begin
						bit_status <= start_c;
						scl_oen    <= 1'b1     ; // set scl_oen high
						sda_oen    <= 1'b1     ; // set sda_oen high
						sda_chk    <= !fsm_busy; // don't check sda_oen output
					end
					start_c: begin
						bit_status <= start_d;
						scl_oen    <= 1'b1   ; // keep scl_oen high
						sda_oen    <= 1'b0   ; // set sda_oen low
						sda_chk    <= 1'b0   ; // don't check sda_oen output
					end
					start_d: begin
						bit_status <= start_e;
						scl_oen    <= 1'b1   ; // keep scl_oen high
						sda_oen    <= 1'b0   ; // keep sda_oen low
						sda_chk    <= 1'b0   ; // don't check sda_oen output
						cmd_complt <= 1'b1;
					end
					start_e: begin
						case (cmd)
							IIC_CMD_START : bit_status <= start_a;
							IIC_CMD_STOP  : bit_status <= stop_a;
							IIC_CMD_WRITE : bit_status <= wr_a;
							IIC_CMD_READ  : bit_status <= rd_a;
							default : bit_status <= idle;
						endcase
						scl_oen <= 1'b0; // set scl_oen low
						sda_oen <= 1'b0; // keep sda_oen low
						sda_chk <= 1'b0; // don't check sda_oen output
					end
					/*
						scl_oen: x1110
						sda_oen: 11000
					*/

					// stop
					stop_a: begin
						bit_status <= stop_b;
						scl_oen    <= 1'b0; // keep scl_oen low
						sda_oen    <= 1'b0; // set sda_oen low
						sda_chk    <= 1'b0; // don't check sda_oen output
					end
					stop_b: begin
						bit_status <= stop_c;
						scl_oen <= 1'b1; // set scl_oen high
						sda_oen <= 1'b0; // keep sda_oen low
						sda_chk <= 1'b0; // don't check sda_oen output
					end
					stop_c: begin
						bit_status <= stop_d;
						scl_oen    <= 1'b1; // keep scl_oen high
						sda_oen    <= 1'b0; // keep sda_oen low
						sda_chk    <= 1'b0; // don't check sda_oen output
					end
					stop_d: begin
						bit_status    <= idle;
						scl_oen       <= 1'b1; // keep scl_oen high
						sda_oen       <= 1'b1; // set sda_oen high
						sda_chk       <= 1'b0; // don't check sda_oen output
						cmd_complt    <= 1'b1;
					end
					/*
						scl_oen: 0111
						sda_oen: 0001
					*/

					// read
					rd_a: begin
						bit_status <= rd_b;
						scl_oen    <= 1'b0; // keep scl_oen low
						sda_oen    <= 1'b1; // set sda_oen high
						sda_chk    <= 1'b0; // don't check sda_oen output
					end
					rd_b: begin
						bit_status <= rd_c;
						scl_oen    <= 1'b1; // set scl_oen high
						sda_oen    <= 1'b1; // keep sda_oen high
						sda_chk    <= 1'b0; // don't check sda_oen output
					end
					rd_c: begin
						if (scl_i_m2) begin
							bit_status <= rd_d; // clock_synchronization
						end
						scl_oen    <= 1'b1; // keep scl_oen high
						sda_oen    <= 1'b1; // keep sda_oen high
						sda_chk    <= 1'b0; // don't check sda_oen output
						cmd_complt <= 1'b1;
					end
					rd_d: begin
						case (cmd)
							IIC_CMD_START : bit_status <= start_a;
							IIC_CMD_STOP  : bit_status <= stop_a;
							IIC_CMD_WRITE : bit_status <= wr_a;
							IIC_CMD_READ  : bit_status <= rd_a;
							default : bit_status <= idle;
						endcase
						scl_oen <= 1'b0; // set scl_oen low
						sda_oen <= 1'b1; // keep sda_oen high
						sda_chk <= 1'b0; // don't check sda_oen output
					end
					/*
						scl_oen: 0110
						sda_oen: 1111
					*/

					// write
					wr_a: begin
						bit_status <= wr_b  ;
						scl_oen    <= 1'b0  ; // keep scl_oen low
						sda_oen    <= din_m1; // set sda_oen
						sda_chk    <= 1'b0  ; // don't check sda_oen output
					end
					wr_b: begin
						bit_status <= wr_c  ;
						scl_oen    <= 1'b1  ; // set scl_oen high
						sda_oen    <= din_m1; // keep sda_oen
						sda_chk    <= 1'b1  ; // check sda_oen output
					end
					wr_c: begin
						if (scl_i_m2) begin
							bit_status <= wr_d; // clock synchronization
						end
						scl_oen    <= 1'b1  ; // keep scl_oen high
						sda_oen    <= din_m1; // keep sda_oen
						sda_chk    <= 1'b1  ; // check sda_oen output
						cmd_complt <= 1'b1;
					end
					wr_d: begin
						case (cmd)
							IIC_CMD_START : bit_status <= start_a;
							IIC_CMD_STOP  : bit_status <= stop_a;
							IIC_CMD_WRITE : bit_status <= wr_a;
							IIC_CMD_READ  : bit_status <= rd_a;
							default : bit_status <= idle;
						endcase
						scl_oen <= 1'b0  ; // set scl_oen low
						sda_oen <= din_m1; // keep sda_oen
						sda_chk <= 1'b0  ; // don't check sda output
					end
					/*
						scl_oen: 0110
						sda_oen: {din_m1, din_m1, din_m1, din_m1}
					*/
					default : ;
				endcase
			end
		end
	end

endmodule // iic_master_bit_ctrl
