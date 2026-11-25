`include "../../config.vh"

module iic_master_byte_ctrl (
	input  wire        clk     , // clock
	input  wire        rstn    , // low active

	// control inputs
	input  wire        ena     , // core work enable
	input  wire [15:0] clk_cnt , // clock division value

	// command inputs
	input  wire        start   , // start command
	input  wire        stop    , // stop command
	input  wire        read    , // read command
	input  wire        write   , // write command
	input  wire        ack_in  , // master ack value
	input  wire        recover , // bus lock recover command
	
	// status outputs
	output wire        iic_busy, // bus busy
	output wire        iic_al  , // bus lost arbitration
	output reg         done    , // one iic operation completed, such as start, stop, read one byte, write one byte
	output reg         ack_out , // ack received by master 
	
	// data signals
	input  wire [7:0]  din     ,
	output wire [7:0]  dout    ,

	// iic signals
	input  wire        scl_i   ,
	output wire        scl_oen ,
	input  wire        sda_i   ,
	output wire        sda_oen 
);

	parameter IIC_CMD_NOP   = 4'b0000;
	parameter IIC_CMD_START = 4'b0001;
	parameter IIC_CMD_STOP  = 4'b0010;
	parameter IIC_CMD_READ  = 4'b0100;
	parameter IIC_CMD_WRITE = 4'b1000;

	// status machine
	localparam ST_IDLE    = 3'h0; // idle status
	localparam ST_START   = 3'h1; // start status
	localparam ST_STOP    = 3'h2; // stop status
	localparam ST_READ    = 3'h3; // read status
	localparam ST_WRITE   = 3'h4; // write status
	localparam ST_ACK     = 3'h5; // ack status
	localparam ST_RECOVER = 3'h6; // bus lock recover status

	reg [3:0] core_cmd; // iic command
	
	reg [7:0] sr; // shift register
	reg shift; // shift flag

	reg ld; // load iic transmit byte data and load bit count value
    reg [3:0] bit_value; // bit count value
	reg [3:0] bit_cnt; // bit count

    reg im_busy;

    reg [2:0] c_status; // command status
    reg [2:0] next_c_status; // next command status
	reg [4:0] toack_status; // ack command status

	wire clk_en; // command status clock
	wire cmd_complt; // command complete flag

	reg core_txd; // iic transmit bit data
	wire core_rxd; // iic receive bit data
	wire cnt_done; // iic transmit or receive bit done

	wire st_idle    ;
	wire st_start   ;
	wire st_read    ;
	wire st_write   ;
	wire st_ack     ;
	wire st_stop    ;
	wire st_recover ;
	wire nst_idle   ;
	wire nst_start  ;
	wire nst_read   ;
	wire nst_write  ;
	wire nst_ack    ;
	wire nst_stop   ;
	wire nst_recover;

	iic_master_bit_ctrl #(
		.IIC_CMD_NOP   (IIC_CMD_NOP  ),
		.IIC_CMD_START (IIC_CMD_START),
		.IIC_CMD_STOP  (IIC_CMD_STOP ),
		.IIC_CMD_WRITE (IIC_CMD_WRITE),
		.IIC_CMD_READ  (IIC_CMD_READ )
	) iic_master_bit_ctrl_inst (
		.clk        (clk       ),
		.rstn       (rstn      ),

		.ena        (ena       ),
		.clk_cnt    (clk_cnt   ),

		.cmd        (core_cmd  ),
		.fsm_busy   (im_busy   ),
		.clk_en     (clk_en    ),
		.cmd_complt (cmd_complt), // when a command is completed, cmd_complt is 1, otherwise cmd_complt is 0
		.busy       (iic_busy  ),
		.al         (iic_al    ),

		.din        (core_txd  ),
		.dout       (core_rxd  ),
		
		.scl_i      (scl_i     ),
		.scl_oen    (scl_oen   ),
		.sda_i      (sda_i     ),
		.sda_oen    (sda_oen   )
	);

	// assign shift register sr to output signal dout
	assign dout = sr;

	// generate shift register
	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			sr <= 8'b0;
		end else if (ld) begin
			sr <= din;
		end else if (shift) begin
			sr <= {sr[6:0], core_rxd};
			// sr[7] changes when shift = 1, namely, when write or read complete
		end
	end

	// generate iic bit counter
	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			bit_cnt <= 3'b0;
		end else if (ld) begin
			bit_cnt <= bit_value;
		end else if (shift) begin
			bit_cnt <= bit_cnt - 1'b1;
		end
	end
	assign cnt_done = !(|bit_cnt);
    
    always @(posedge clk or negedge rstn) begin
		if (!rstn | iic_al) begin
			c_status <= ST_IDLE;
		end else begin
			c_status <= next_c_status;
		end
	end

    always @(posedge clk or negedge rstn) begin
		if (!rstn | iic_al) begin
			im_busy <= 1'b0;
		end else if ((c_status == ST_START) & cmd_complt) begin
			im_busy <= 1'b1;
		end else if ((c_status == ST_STOP) & cmd_complt) begin
			im_busy <= 1'b0;
		end
	end

    always @(*) begin
		next_c_status = c_status;
		case (c_status)
			ST_IDLE : begin
				if (clk_en) begin
					if (start) begin
						if (!iic_busy | im_busy) begin
							next_c_status = ST_START; // if start fails, it will continue to start
						end
					end else if (stop) begin
						next_c_status = ST_STOP;
					end else if (read) begin
						next_c_status = ST_READ;
					end else if (write) begin
						next_c_status = ST_WRITE;
					end else if (recover) begin
						next_c_status = ST_RECOVER;
					end
				end
			end
			ST_START : begin
				if (cmd_complt) begin
					if (read) begin
						next_c_status = ST_READ;
					end else if (write) begin
						next_c_status = ST_WRITE;
					end
				end
			end
			ST_STOP : begin
				if (cmd_complt) begin
					next_c_status = ST_IDLE;
				end
			end
			ST_READ : begin
				if (cmd_complt) begin
					if (cnt_done) begin
						next_c_status = ST_ACK;
					end
				end
			end
			ST_WRITE : begin
				if (cmd_complt) begin
					if (cnt_done) begin
						next_c_status = ST_ACK;
					end
				end
			end
			ST_ACK : begin
				if (cmd_complt) begin
					if (stop) begin 
						next_c_status = ST_STOP;
					end else begin
						next_c_status = ST_IDLE;
					end
				end
			end
			ST_RECOVER : begin
				if (cmd_complt & cnt_done) begin
                    next_c_status = ST_STOP;
				end
			end
			default : next_c_status = ST_IDLE;
		endcase
	end

	assign st_idle     = c_status == ST_IDLE   ;
	assign st_start    = c_status == ST_START  ;
	assign st_read     = c_status == ST_READ   ;
	assign st_write    = c_status == ST_WRITE  ;
	assign st_ack      = c_status == ST_ACK    ;
	assign st_stop     = c_status == ST_STOP   ;
	assign st_recover  = c_status == ST_RECOVER;
	assign nst_idle    = next_c_status == ST_IDLE   ;
	assign nst_start   = next_c_status == ST_START  ;
	assign nst_read    = next_c_status == ST_READ   ;
	assign nst_write   = next_c_status == ST_WRITE  ;
	assign nst_ack     = next_c_status == ST_ACK    ;
	assign nst_stop    = next_c_status == ST_STOP   ;
	assign nst_recover = next_c_status == ST_RECOVER;

    always @(posedge clk or negedge rstn) begin
		if (!rstn || iic_al) begin
			toack_status <= ST_IDLE;
		end else if (nst_ack & !st_ack) begin
			toack_status <= c_status; // toack_status <= ST_READ or ST_WRITE
		end
	end

    always @(*) begin
        shift = (st_read | st_write | st_recover) & cmd_complt;
        ld = (st_idle & (nst_read | nst_write | nst_recover)) | (st_start & cmd_complt);
        bit_value = (st_idle & nst_recover) ? 4'h8 : 4'h7;
		done = (st_idle & nst_start) | (!st_idle & nst_idle);
        core_txd = st_ack                    ? ack_in : sr[7];
        core_cmd = st_idle                   ? IIC_CMD_NOP   :
                   st_start                  ? IIC_CMD_START :
                   st_stop                   ? IIC_CMD_STOP  :
				   st_read                   ? IIC_CMD_READ  :
				   st_write                  ? IIC_CMD_WRITE :
				   st_recover                ? IIC_CMD_READ  :
		          (toack_status == ST_READ)  ? IIC_CMD_WRITE :
		          (toack_status == ST_WRITE) ? IIC_CMD_READ  :
									           IIC_CMD_NOP   ;
    end

    always @(posedge clk or negedge rstn) begin
		if (!rstn || iic_al) begin
			ack_out <= 1'b0;
		end else if (st_ack & cmd_complt) begin
			ack_out <= core_rxd;
		end
	end

endmodule // iic_master_byte_ctrl
