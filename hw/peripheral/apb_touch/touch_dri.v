module touch_dri #(
	parameter WIDTH = 8 // the bit width of data transmitted in one read or write operation of iic
) (
    input  wire               clk          , 
    input  wire               rst_n        , 

    // iic interface
    output reg  [6:0]         slave_addr   , // device address
    output reg                iic_exec     , // trigger execution signal
    output reg                iic_rh_wl    , // read and write control signals
    output reg  [15:0]        iic_addr     , // device internal address
    output reg  [7:0]         iic_data_w   , // the data to be written
    output reg                bit_ctrl     , // byte address bit control (0:8b, 1:16b)
    output reg  [WIDTH - 1:0] reg_num      , // the number of registers transmitted in one read or write operation of iic
    input  wire [7:0]         iic_data     , // read out data
    input  wire               iic_ack      , // response signal
    input  wire               iic_done     , // operation completed
    input  wire               once_done    , // one read or write operation completed

    // lcd related ports
    input  wire [15:0]        lcd_id       , 
    output reg                touch_valid  , // touch valid signal
    output reg  [15:0]        tp_x_coord   , // coordinates of the touch point in the x direction
    output reg  [15:0]        tp_y_coord   , // coordinates of the touch point in the y direction                 
    output reg                touch_rst_n  , // touch screen reset, active low
    input  wire               touch_int_in , // interrupt input signal
    output reg                touch_int_dir, // interrupt direction control signal
    output reg                touch_int_out  // interrupt output signal
);

	// FT series
	localparam FT_slave_addr_r   = 7'h38;       // FT series device address
	localparam FT_bit_ctrl_r     = 1'b0;        // FT series bit control

	localparam FT_ID_LIB_VERSION = 8'hA1;       // edition
	localparam FT_DEVIDE_MODE    = 8'h00;       // mode control register
	localparam FT_ID_MODE        = 8'hA4;       // FT interrupt mode control register
	localparam FT_ID_THGROUP     = 8'h80;       // touch the effective value setting register
	localparam FT_ID_PERIOD_ACT  = 8'h88;       // activate state cycle setting register
	localparam FT_STATE_REG      = 8'h02;       // touch status register
	localparam FT_TP1_REG        = 8'h03;       // first touch point data address

	// GT series
	localparam GT_slave_addr_r   = 7'h14;       // GT series device address
	localparam GT_bit_ctrl_r     = 1'b1;        // GT series position control

	localparam GT_STATE_REG      = 16'h814E;    // touch status register
	localparam GT_TP1_REG        = 16'h8150;    // first touch point data address

	localparam st_idle           = 7'b000_0001; // idle state
	localparam st_init           = 7'b000_0010; // power on initialization
	localparam st_get_id         = 7'b000_0100; // obtain touch chip ID
	localparam st_cfg_reg        = 7'b000_1000; // configure registers
	localparam st_check_touch    = 7'b001_0000; // detecting touch status
	localparam st_get_coord      = 7'b010_0000; // obtain the coordinates of the touch point
	localparam st_coord_handle   = 7'b100_0000; // processing coordinate data for touches of different sizes

	reg [6:0]  cur_status  ;
	reg [6:0]  next_status ;

	reg        cnt_1us_en  ; // enable timing
	reg [19:0] cnt_1us_cnt ; // timer counter
	reg [15:0] chip_version; // chip version number
	reg        ft_flag     ; // the flag of FT series chips
	reg [15:0] touch_s_reg ; // touch status register
	reg [15:0] coord_reg   ; // touch point coordinate register
	reg [15:0] tp_x_coord_t; // temporary coordinates of touch point in X direction
	reg [15:0] tp_y_coord_t; // temporary coordinates of touch point in Y direction
	reg [3:0]  flow_cnt    ; // process counter
	reg        st_done     ; // status completion signal

	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			cnt_1us_cnt <= 20'd0;
		end else if (cnt_1us_en) begin
			cnt_1us_cnt <= cnt_1us_cnt + 1'b1;
		end else begin
			cnt_1us_cnt <= 20'd0;
		end
	end

	always @ (posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			cur_status <= st_idle;
		end else begin
			cur_status <= next_status;
		end
	end

	always @(*) begin
		case (cur_status)
			st_idle : begin
				if (st_done) begin
					next_status = st_init;
				end else begin
					next_status = st_idle;
				end
			end
			st_init : begin
				if (st_done) begin
					next_status = st_get_id; 
				end else begin
					next_status = st_init;
				end
			end
			st_get_id : begin
				if (st_done) begin
					if (ft_flag) begin // only FT series requires register configuration
						next_status = st_cfg_reg;
					end else begin
						next_status = st_check_touch;
					end
				end else begin
					next_status = st_get_id;
				end
			end       
			st_cfg_reg : begin
				if (st_done) begin
					next_status = st_check_touch;
				end else begin
					next_status = st_cfg_reg;
				end
			end
			st_check_touch: begin
				if (st_done) begin
					next_status = st_get_coord;
				end else begin
					next_status = st_check_touch;
				end
			end
			st_get_coord : begin
				if (st_done) begin
					next_status = st_coord_handle;
				end else begin
					next_status = st_get_coord;
				end
			end
			st_coord_handle : begin
				if (st_done) begin
					next_status = st_check_touch;
				end else begin
					next_status = st_coord_handle;
				end
			end
			default: begin
				next_status = st_idle;
			end
		endcase
	end

	always @ (posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			cnt_1us_en    <= 1'b0;
			chip_version  <= 16'b0;
			ft_flag       <= 1'b0;
			touch_s_reg   <= 16'b0;
			coord_reg     <= 16'b0;
			tp_x_coord_t  <= 16'b0;
			tp_y_coord_t  <= 16'b0;
			flow_cnt      <= 4'b0;
			st_done       <= 1'b0;
			touch_int_dir <= 1'b0;
			touch_int_out <= 1'b0;

			slave_addr    <= 7'b0;
			iic_exec      <= 1'b0;
			iic_rh_wl     <= 1'b0;
			iic_addr      <= 16'b0;
			iic_data_w    <= 8'b0;
			bit_ctrl      <= 1'b0;
			reg_num       <= 1'b0;

			touch_valid   <= 1'b0;
			tp_x_coord    <= 16'b0;
			tp_y_coord    <= 16'b0;
			touch_rst_n   <= 1'b0;
		end else begin
			iic_exec <= 1'b0;
			st_done <= 1'b0;
			case (next_status)
				st_idle : begin
					cnt_1us_en <= 1'b1;
					touch_int_dir <= 1'b1; // touch int port direction set to output
					touch_int_out <= 1'b1; // touch int port outputs high level
					if (cnt_1us_cnt >= 10) begin
						st_done    <= 1'b1;
						cnt_1us_en <= 1'b0;
					end
				end
				st_init : begin
					cnt_1us_en <= 1'b1;
					if (cnt_1us_cnt < 10_000) begin // delay 10 ms
						touch_rst_n <= 1'b0; // start reset
					end else if (cnt_1us_cnt == 10_000) begin
						touch_rst_n <= 1'b1; // finish reset
					end else if (cnt_1us_cnt == 60_000) begin // delay again 50ms (60_000-10_000)
						touch_int_dir <= 1'b0; // set the int pin as a floating input
						cnt_1us_en    <= 1'b0;
						st_done       <= 1'b1;
						flow_cnt      <= 4'd0;
					end    
				end
				st_get_id : begin
					case (flow_cnt)
						4'd0 : begin
							if (lcd_id == 16'h4342 || lcd_id == 16'h4384 || lcd_id == 16'h7084 || lcd_id == 16'h7016) begin 
								// these ids are the GT series
								flow_cnt <= 4'd5;
								ft_flag  <= 1'b0; // 'ft_flag = 0' indicates that the touch chip belongs to the GT series
							end else begin
								flow_cnt <= flow_cnt + 1'b1;
							end
						end
						4'd1 : begin // read FT series version number
							iic_exec   <= 1'b1;
							iic_rh_wl  <= 1'b1;
							iic_addr   <= FT_ID_LIB_VERSION;
							reg_num    <= 'd2;
							slave_addr <= FT_slave_addr_r;
							bit_ctrl   <= FT_bit_ctrl_r;
							flow_cnt   <= flow_cnt + 1'b1;
						end
						4'd2 : begin
							if (once_done) begin
								chip_version[15:8] <= iic_data;
								flow_cnt <= flow_cnt + 1'b1;
							end else if (iic_done && iic_ack) begin // no response, indicating GT series
								chip_version <= "GT";
								flow_cnt     <= 4'd4;
							end
						end
						4'd3 : begin
							if (iic_done) begin
								chip_version[7:0] <= iic_data;
								flow_cnt          <= flow_cnt + 1'b1;
							end
						end
						4'd4 : begin
							flow_cnt <= flow_cnt + 1'b1;
							if (chip_version == 16'h3003 || chip_version == 16'h0001  
								|| chip_version == 16'h0002 || chip_version == 16'h0000) begin
								// these ids are the FT series
								ft_flag <= 1'b1; // 'ft_flag = 1' indicates that the touch chip is from the FT series
							end else begin
								ft_flag <= 1'b0; // 'ft_flag = 0' indicates that the touch chip is from the GT series
							end
						end
						4'd5 : begin
							st_done  <= 1'b1;
							flow_cnt <= 4'd0;
							if (ft_flag) begin // configure parameters as FT series
								touch_s_reg <= FT_STATE_REG;
								coord_reg   <= FT_TP1_REG;
								bit_ctrl    <= FT_bit_ctrl_r;
								slave_addr  <= FT_slave_addr_r;
							end else begin // configure parameters as GT series
								touch_s_reg <= GT_STATE_REG;
								coord_reg   <= GT_TP1_REG;
								bit_ctrl    <= GT_bit_ctrl_r;
								slave_addr  <= GT_slave_addr_r;
							end                        
						end
						default : ;
					endcase    
				end
				st_cfg_reg : begin
					case (flow_cnt)
						// configure FT series
						4'd0 : begin
							iic_exec   <= 1'b1;
							iic_rh_wl  <= 1'b0;
							iic_addr   <= FT_DEVIDE_MODE;   
							iic_data_w <= 8'd0;            
							reg_num    <= 'd1;
							flow_cnt   <= flow_cnt + 1'b1;
						end                          
						4'd1 : begin
							if (iic_done) begin
								if (iic_ack == 1'b0) begin
									flow_cnt <= flow_cnt + 1'b1;
								end else begin
									flow_cnt <= flow_cnt - 1'b1;
								end
							end
						end
						4'd2 : begin
							iic_exec   <= 1'b1;
							iic_rh_wl  <= 1'b0;
							iic_addr   <= FT_ID_MODE;
							iic_data_w <= 8'd0;
							reg_num    <= 'd1;
							flow_cnt   <= flow_cnt + 1'b1;
						end
						4'd3 : begin
							if (iic_done) begin
								if (iic_ack == 1'b0) begin
									flow_cnt <= flow_cnt + 1'b1;
								end else begin
									flow_cnt <= flow_cnt - 1'b1;
								end
							end
						end
						4'd4 : begin
							iic_exec   <= 1'b1;
							iic_rh_wl  <= 1'b0;
							iic_addr   <= FT_ID_THGROUP;
							iic_data_w <= 8'd22;
							reg_num    <= 'd1;
							flow_cnt   <= flow_cnt + 1'b1;
						end
						4'd5 : begin
							if (iic_done) begin
								if (iic_ack == 1'b0) begin
									flow_cnt <= flow_cnt + 1'b1;
								end else begin
									flow_cnt <= flow_cnt - 1'b1;
								end
							end
						end
						4'd6 : begin
							iic_exec   <= 1'b1;
							iic_rh_wl  <= 1'b0;
							iic_addr   <= FT_ID_PERIOD_ACT;    
							iic_data_w <= 8'd12;
							reg_num    <= 'd1;
							flow_cnt   <= flow_cnt + 1'b1;
						end
						4'd7 : begin
							if (iic_done) begin
								if (iic_ack == 1'b0) begin
									flow_cnt <= 'd0;
									st_done  <= 1'b1;
								end else begin
									flow_cnt <= flow_cnt - 1'b1;
								end
							end
						end
						default : ;
					endcase                       
				end
				st_check_touch : begin
					case (flow_cnt)
						4'd0: begin // delay
							cnt_1us_en <= 1'b1;
							if (cnt_1us_cnt == 20_000) begin
								flow_cnt   <= flow_cnt + 1'b1;
								cnt_1us_en <= 1'b0;
							end
						end
						4'd1 : begin
							iic_exec  <= 1'b1;
							iic_rh_wl <= 1'b1;
							iic_addr  <= touch_s_reg; // read touch point status
							reg_num   <= 'd1;
							flow_cnt  <= flow_cnt + 1'b1;
						end
						4'd2 : begin
							if (iic_done) begin
								if (iic_ack == 1'b0) begin
									flow_cnt <= flow_cnt + 1'b1;
								end else begin
									flow_cnt <= flow_cnt - 1'b1;
								end
							end
						end
						4'd3 : begin
							flow_cnt <= flow_cnt + 1'b1;
							if (ft_flag) begin
								if (iic_data[3:0] > 4'd0 && iic_data[3:0] <= 4'd5) begin
									touch_valid <= 1'b1; // touch detected
								end else begin
									touch_valid <= 1'b0; // touch not detected
								end
							end else begin
								if (iic_data[7]== 1'b1 && iic_data[3:0] > 4'd0 && iic_data[3:0] <= 4'd5) begin
									touch_valid <= 1'b1; // touch detected
								end else begin
									touch_valid <= 1'b0; // touch not detected
								end
							end
						end
						4'd4 : begin
							iic_exec   <= 1'b1;
							iic_rh_wl  <= 1'b0;
							iic_addr   <= touch_s_reg;
							iic_data_w <= 8'd0; // Clear touch mark
							reg_num    <= 'd1;
							flow_cnt   <= flow_cnt + 1'b1;
						end
						4'd5 : begin
							if (iic_done) begin
								if (iic_ack == 1'b0) begin
									st_done <= touch_valid;
									flow_cnt <= 1'b0;
								end else begin
									flow_cnt <= flow_cnt - 1'b1;
								end
							end
						end
						default : ;
					endcase    
				end
				st_get_coord : begin
					case (flow_cnt)
						4'd0 : begin
							iic_exec  <= 1'b1;
							iic_rh_wl <= 1'b1;
							iic_addr  <= coord_reg; // obtain x and y direction coordinate points
							reg_num   <= 'd4; // read four registers consecutively
							flow_cnt  <= flow_cnt + 1'b1;
						end
						4'd1 : begin
							if (once_done) begin
								if (iic_ack == 1'b0) begin
									tp_x_coord_t[7:0] <= iic_data;
									flow_cnt          <= flow_cnt + 1'b1;
								end else begin
									flow_cnt <= 1'b0;
								end
							end
						end
						4'd2 : begin
							if (once_done) begin
								flow_cnt           <= flow_cnt + 1'b1;
								tp_x_coord_t[15:8] <= iic_data;
							end
						end
						4'd3 : begin
							if (once_done) begin
								flow_cnt          <= flow_cnt + 1'b1;
								tp_y_coord_t[7:0] <= iic_data;    
							end
						end
						4'd4 : begin
							if (once_done) begin
								st_done            <= 1'b1;
								flow_cnt           <= 'd0;
								tp_y_coord_t[15:8] <= iic_data;
							end
						end
						default : ;
					endcase    
				end
				st_coord_handle : begin
					st_done <= 1'b1;
					if (ft_flag) begin // FT series requires data processing
						tp_x_coord <= {4'd0, tp_y_coord_t[3:0], tp_y_coord_t[15:8]};
						tp_y_coord <= {4'd0, tp_x_coord_t[3:0], tp_x_coord_t[15:8]};
					end else begin
						tp_x_coord <= tp_x_coord_t;
						tp_y_coord <= tp_y_coord_t;                        
					end
				end
				default : ;
			endcase
		end
	end

endmodule 
