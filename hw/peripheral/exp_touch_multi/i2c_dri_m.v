module iic_dri_m #(
    parameter CLK_FREQ = 32_000_000, // iic_dri_m module driver clock frequency
    parameter IIC_FREQ = 250_000   , // iic clock frequency
    parameter WIDTH    = 8           // the bit width of data transmitted in one read or write operation of iic
) (
    input  wire               clk       ,
    input  wire               rst_n     ,
    
	// iic interface
    input  wire [6:0]         slave_addr, // device address
    input  wire               iic_exec  , // trigger execution signal
    input  wire               iic_rh_wl , // read and write control signals
    input  wire [15:0]        iic_addr  , // device internal address
    input  wire [7:0]         iic_data_w, // the data to be written
    input  wire               bit_ctrl  , // word address bit control (0:8b, 1:16b)
    input  wire [WIDTH - 1:0] reg_num   , // the number of registers transmitted in one read or write operation of iic
    output reg  [7:0]         iic_data  , // read out data
    output reg                iic_done  , // operation completed
    output reg                once_done , // one read or write operation completed
    output reg                scl       , // scl clock signal
    input  wire               sda_in    , // sda input signal
    output reg                sda_out   , // sda output signal
    output reg                sda_dir   , // sda direction control
    output reg                ack       , // response flag
    
	// user interface
    output reg                dri_clk     // drive clock
);

	localparam  st_idle    = 8'b0000_0001; // idle status
	localparam  st_sladdr  = 8'b0000_0010; // send device address (slave address)
	localparam  st_addr16  = 8'b0000_0100; // send a 16 bit address
	localparam  st_addr8   = 8'b0000_1000; // send an 8 bit address
	localparam  st_data_wr = 8'b0001_0000; // write data (8-bit)
	localparam  st_addr_rd = 8'b0010_0000; // send read address 
	localparam  st_data_rd = 8'b0100_0000; // read data (8-bit)
	localparam  st_stop    = 8'b1000_0000; // end iic operation

	reg               st_done    ;
	reg               wr_flag    ;
	reg [ 6:0]        cnt        ;
	reg [ 7:0]        cur_status ;
	reg [ 7:0]        next_status;
	reg [15:0]        addr_t     ;
	reg [ 7:0]        data_r     ;
	reg [ 7:0]        data_wr_t  ;
	reg [ 9:0]        clk_cnt    ;
	reg [WIDTH - 1:0] reg_cnt    ;

	wire [8:0] clk_divide;
	wire reg_done;

	assign clk_divide = (CLK_FREQ / IIC_FREQ) >> 2; // (32_000_000 / 250_000) >> 2 = 128 >> 2 = 32
	assign reg_done = (reg_cnt == reg_num) ? 1'b1 : 1'b0;

	// generate a driving clock with four times the frequency of scl for iic to drive the operation of iic
	always @(posedge clk or negedge rst_n) begin
		if (rst_n == 1'b0) begin
			clk_cnt <= 10'b0;
			dri_clk <= 1'b1;
		end else if (clk_cnt == clk_divide - 1'b1) begin
			clk_cnt <= 10'b0;
			dri_clk <= !dri_clk; // 32_000_000 / 32 = 1_000_000
		end else begin
			clk_cnt <= clk_cnt + 1'b1;
		end
	end

	always @(posedge dri_clk or negedge rst_n) begin
		if (!rst_n) begin
			reg_cnt <= 'b0;
		end else if (once_done) begin
			reg_cnt <= reg_cnt + 1'b1;
		end else if (iic_done) begin
			reg_cnt <= 'b0;
		end
	end

	// three stage status machine
	// synchronous timing description status transition
	always @(posedge dri_clk or negedge rst_n) begin
		if (rst_n == 1'b0) begin
			cur_status <= st_idle;
		end else begin
			cur_status <= next_status;
		end
	end

	// combine logic to determine status transition conditions
	always @( * ) begin
		case (cur_status)
			st_idle: begin // idle status
				if (iic_exec) begin
					next_status = st_sladdr;
				end else begin
					next_status = st_idle;
				end
			end
			st_sladdr: begin
				if (st_done) begin
					if (!ack) begin
						if (bit_ctrl) begin // determine whether it is a 16 bit or 8-bit address
							next_status = st_addr16;
						end else begin
							next_status = st_addr8;
						end
					end else begin
						next_status = st_stop;
					end
				end else begin
					next_status = st_sladdr;
				end
			end
			st_addr16: begin // send a 16 bit address
				if (st_done) begin
					if (!ack) begin
						next_status = st_addr8;
					end else begin
						next_status = st_stop;
					end
				end else begin
					next_status = st_addr16;
				end
			end
			st_addr8: begin // send an 8-bit address
				if (st_done) begin
					if (!ack) begin
						if (wr_flag == 1'b0) begin // read and write judgment
							next_status = st_data_wr;
						end else begin
							next_status = st_addr_rd;
						end
					end else begin
						next_status = st_stop;
					end 
				end else begin
					next_status = st_addr8;
				end
			end
			st_data_wr: begin // write data (8-bit)
				if (st_done) begin
					if (reg_done) begin
						next_status = st_stop;
					end else begin
						next_status = st_data_wr;
					end
				end else begin
					next_status = st_data_wr;
				end
			end
			st_addr_rd: begin // write address for reading data
				if (st_done) begin
					if (!ack) begin
						next_status = st_data_rd;
					end else begin
						next_status = st_stop;
					end
				end else begin
					next_status = st_addr_rd;
				end
			end
			st_data_rd: begin // read data (8 bit)
				if (st_done) begin
					if (reg_done) begin
						next_status = st_stop;
					end else begin
						next_status = st_data_rd;
					end
				end else begin
					next_status = st_data_rd;
				end
			end
			st_stop: begin // end iic operation
				if (st_done) begin
					next_status = st_idle;
				end else begin
					next_status = st_stop;
				end
			end
			default: begin
				next_status= st_idle;
			end
		endcase
	end

	// sequential circuit description status output
	always @(posedge dri_clk or negedge rst_n) begin
		if (rst_n == 1'b0) begin // reset and initial
			scl       <= 1'b1;
			sda_out   <= 1'b1;
			sda_dir   <= 1'b1;
			iic_done  <= 1'b0;
			ack       <= 1'b0;
			cnt       <= 7'b0;
			st_done   <= 1'b0;
			once_done <= 1'b0;
			data_r    <= 8'b0;
			iic_data  <= 8'b0;
			wr_flag   <= 1'b0;
			addr_t    <= 16'b0;
			data_wr_t <= 8'b0;
		end else begin
			st_done   <= 1'b0;
			once_done <= 1'b0;
			cnt       <= cnt + 1'b1;
			case (cur_status)
				st_idle: begin // idle status
					scl      <= 1'b1;
					sda_out  <= 1'b1;
					sda_dir  <= 1'b1;
					iic_done <= 1'b0;
					cnt      <= 7'b0;
					if (iic_exec) begin
						wr_flag   <= iic_rh_wl;
						addr_t    <= iic_addr;
						data_wr_t <= iic_data_w;
					end
				end
				st_sladdr: begin // write device address
					case (cnt)
						7'd1 : begin
							sda_dir <= 1'b1;
							sda_out <= 1'b0;
						end
						7'd3 : scl <= 1'b0;
						7'd4 : sda_out <= slave_addr[6];
						7'd5 : scl <= 1'b1;
						7'd7 : scl <= 1'b0;
						7'd8 : sda_out <= slave_addr[5];
						7'd9 : scl <= 1'b1;
						7'd11: scl <= 1'b0;
						7'd12: sda_out <= slave_addr[4];
						7'd13: scl <= 1'b1;
						7'd15: scl <= 1'b0;
						7'd16: sda_out <= slave_addr[3];
						7'd17: scl <= 1'b1;
						7'd19: scl <= 1'b0;
						7'd20: sda_out <= slave_addr[2];
						7'd21: scl <= 1'b1;
						7'd23: scl <= 1'b0;
						7'd24: sda_out <= slave_addr[1];
						7'd25: scl <= 1'b1;
						7'd27: scl <= 1'b0;
						7'd28: sda_out <= slave_addr[0];
						7'd29: scl <= 1'b1;
						7'd31: scl <= 1'b0;
						7'd32: sda_out <= 1'b0;
						7'd33: scl <= 1'b1;
						7'd35: scl <= 1'b0;
						7'd36: begin
							sda_dir <= 1'b0; // slave response
							sda_out <= 1'b1;
						end
						7'd37: begin 
							scl <= 1'b1; 
							ack <= sda_in;
						end
						7'd42: st_done <= 1'b1;
						7'd43: begin
							scl <= 1'b0;
							cnt <= 1'b0;
						end
						default : ;
					endcase
				end
				st_addr16: begin // write the top 8 bits of the register address
					case (cnt)
						7'b0 : begin
							sda_dir <= 1'b1;
							sda_out <= addr_t[15];
						end
						7'd1 : scl <= 1'b1;
						7'd3 : scl <= 1'b0;
						7'd4 : sda_out <= addr_t[14];
						7'd5 : scl <= 1'b1;
						7'd7 : scl <= 1'b0;
						7'd8 : sda_out <= addr_t[13];
						7'd9 : scl <= 1'b1;
						7'd11: scl <= 1'b0;
						7'd12: sda_out <= addr_t[12];
						7'd13: scl <= 1'b1;
						7'd15: scl <= 1'b0;
						7'd16: sda_out <= addr_t[11];
						7'd17: scl <= 1'b1;
						7'd19: scl <= 1'b0;
						7'd20: sda_out <= addr_t[10];
						7'd21: scl <= 1'b1;
						7'd23: scl <= 1'b0;
						7'd24: sda_out <= addr_t[9];
						7'd25: scl <= 1'b1;
						7'd27: scl <= 1'b0;
						7'd28: sda_out <= addr_t[8];
						7'd29: scl <= 1'b1;
						7'd31: scl <= 1'b0;
						7'd32: begin
							sda_dir <= 1'b0; // slave response
							sda_out <= 1'b1;
						end
						7'd33:  begin 
							scl <= 1'b1; 
							ack <= sda_in;
						end
						7'd38: st_done <= 1'b1;
						7'd39: begin
							scl <= 1'b0;
							cnt <= 1'b0;
						end
						default : ;
					endcase
				end
				st_addr8: begin // write the lower 8 bits of the register address
					case (cnt)
						7'b0: begin
							sda_dir <= 1'b1;
							sda_out <= addr_t[7];
						end
						7'd1 : scl <= 1'b1;
						7'd3 : scl <= 1'b0;
						7'd4 : sda_out <= addr_t[6];
						7'd5 : scl <= 1'b1;
						7'd7 : scl <= 1'b0;
						7'd8 : sda_out <= addr_t[5];
						7'd9 : scl <= 1'b1;
						7'd11: scl <= 1'b0;
						7'd12: sda_out <= addr_t[4];
						7'd13: scl <= 1'b1;
						7'd15: scl <= 1'b0;
						7'd16: sda_out <= addr_t[3];
						7'd17: scl <= 1'b1;
						7'd19: scl <= 1'b0;
						7'd20: sda_out <= addr_t[2];
						7'd21: scl <= 1'b1;
						7'd23: scl <= 1'b0;
						7'd24: sda_out <= addr_t[1];
						7'd25: scl <= 1'b1;
						7'd27: scl <= 1'b0;
						7'd28: sda_out <= addr_t[0];
						7'd29: scl <= 1'b1;
						7'd31: scl <= 1'b0;
						7'd32: begin
							sda_dir <= 1'b0; // slave response
							sda_out <= 1'b1;
						end
						7'd33:  begin 
							scl <= 1'b1; 
							ack <= sda_in;
						end
						7'd38: st_done <= 1'b1;
						7'd39: begin
							scl <= 1'b0;
							cnt <= 1'b0;
						end
						default : ;
					endcase
				end
				st_data_wr: begin // write data (8 bit)
					case (cnt)
						7'b0: begin
							sda_dir   <= 1'b1;
							sda_out   <= iic_data_w[7];
							data_wr_t <= iic_data_w;
						end
						7'd1 : scl <= 1'b1;
						7'd3 : scl <= 1'b0;
						7'd4 : sda_out <= data_wr_t[6];
						7'd5 : scl <= 1'b1;
						7'd7 : scl <= 1'b0;
						7'd8 : sda_out <= data_wr_t[5];
						7'd9 : scl <= 1'b1;
						7'd11: scl <= 1'b0;
						7'd12: sda_out <= data_wr_t[4];
						7'd13: scl <= 1'b1;
						7'd15: scl <= 1'b0;
						7'd16: sda_out <= data_wr_t[3];
						7'd17: scl <= 1'b1;
						7'd19: scl <= 1'b0;
						7'd20: sda_out <= data_wr_t[2];
						7'd21: scl <= 1'b1;
						7'd23: scl <= 1'b0;
						7'd24: sda_out <= data_wr_t[1];
						7'd25: scl <= 1'b1;
						7'd27: scl <= 1'b0;
						7'd28: sda_out <= data_wr_t[0];
						7'd29: scl <= 1'b1;
						7'd31: scl <= 1'b0;
						7'd32: begin
							sda_dir   <= 1'b0; // slave response
							sda_out   <= 1'b1;
							once_done <= 1'b1;
						end
						7'd33:  begin 
							scl <= 1'b1; 
							ack <= sda_in;
						end
						7'd38: st_done <= 1'b1;
						7'd39: begin
							scl <= 1'b0;
							cnt <= 1'b0;
						end
						default : ;
					endcase
				end
				st_addr_rd: begin // write address for reading data
					case (cnt)
						7'b0 : begin
							sda_dir <= 1'b1;
							sda_out <= 1'b1;
						end
						7'd1 : scl <= 1'b1;
						7'd2 : sda_out <= 1'b0;
						7'd3 : scl <= 1'b0;
						7'd4 : sda_out <= slave_addr[6];
						7'd5 : scl <= 1'b1;
						7'd7 : scl <= 1'b0;
						7'd8 : sda_out <= slave_addr[5];
						7'd9 : scl <= 1'b1;
						7'd11: scl <= 1'b0;
						7'd12: sda_out <= slave_addr[4];
						7'd13: scl <= 1'b1;
						7'd15: scl <= 1'b0;
						7'd16: sda_out <= slave_addr[3];
						7'd17: scl <= 1'b1;
						7'd19: scl <= 1'b0;
						7'd20: sda_out <= slave_addr[2];
						7'd21: scl <= 1'b1;
						7'd23: scl <= 1'b0;
						7'd24: sda_out <= slave_addr[1];
						7'd25: scl <= 1'b1;
						7'd27: scl <= 1'b0;
						7'd28: sda_out <= slave_addr[0];
						7'd29: scl <= 1'b1;
						7'd31: scl <= 1'b0;
						7'd32: sda_out <= 1'b1;
						7'd33: scl <= 1'b1;
						7'd35: scl <= 1'b0;
						7'd36: begin
							sda_dir <= 1'b0; // slave response
							sda_out <= 1'b1;
						end
						7'd37:  begin 
							scl <= 1'b1; 
							ack <= sda_in;
						end
						7'd42: st_done <= 1'b1;
						7'd43: begin
							scl <= 1'b0;
							cnt <= 1'b0;
						end
						default : ;
					endcase
				end
				st_data_rd: begin // read data (8 bit)
					case (cnt)
						7'b0: sda_dir <= 1'b0;
						7'd1: begin
							data_r[7] <= sda_in;
							scl       <= 1'b1;
						end
						7'd3: scl <= 1'b0;
						7'd5: begin
							data_r[6] <= sda_in;
							scl       <= 1'b1 ;
						end
						7'd7: scl <= 1'b0;
						7'd9: begin
							data_r[5] <= sda_in;
							scl       <= 1'b1;
						end
						7'd11: scl <= 1'b0;
						7'd13: begin
							data_r[4] <= sda_in;
							scl       <= 1'b1;
						end
						7'd15: scl <= 1'b0;
						7'd17: begin
							data_r[3] <= sda_in;
							scl       <= 1'b1;
						end
						7'd19: scl <= 1'b0;
						7'd21: begin
							data_r[2] <= sda_in;
							scl       <= 1'b1;
						end
						7'd23: scl <= 1'b0;
						7'd25: begin
							data_r[1] <= sda_in;
							scl       <= 1'b1;
						end
						7'd27: scl <= 1'b0;
						7'd29: begin
							data_r[0] <= sda_in;
							scl       <= 1'b1;
						end
						7'd31: scl <= 1'b0;
						7'd32: begin                       
							if (reg_cnt == reg_cnt - 1'b1) begin
								sda_dir <= 1'b1; // mster no response
								sda_out <= 1'b1;
							end else begin
								sda_dir <= 1'b1; // mster response
								sda_out <= 1'b0;
							end
						end
						7'd33: begin
							scl       <= 1'b1;
							once_done <= 1'b1;
							iic_data  <= data_r;
						end
						7'd38: st_done <= 1'b1;
						7'd39: begin
							scl <= 1'b0;
							cnt <= 1'b0;    
						end
						default : ;
					endcase
				end
				st_stop: begin // End IIC operation
					case (cnt)
						7'b0: begin
							sda_dir <= 1'b1;
							sda_out <= 1'b0;
						end
						7'd1: scl     <= 1'b1;
						7'd3: sda_out <= 1'b1;
						7'd5: st_done <= 1'b1;
						7'd6: begin
							cnt      <= 1'b0;
							iic_done <= 1'b1; // transmit iic end signal to upper module
						end
						default : ;
					endcase
				end
			endcase
		end
	end

endmodule
