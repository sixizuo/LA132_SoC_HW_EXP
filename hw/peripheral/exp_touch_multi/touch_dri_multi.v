//=====================================================================
//  touch_dri_multi.v  ——  实验八：GT911 多点触摸读取驱动
//---------------------------------------------------------------------
//  来源 : hw/peripheral/apb_touch/touch_dri.v（单点，固定读 4 字节）
//  改动 :
//    1) 状态寄存器 0x814E 的低 4 位作为触点数 N（0~5），上限由 maxpoint
//       限制；
//    2) 坐标区 0x8150 一次连续读 N×8 字节（GT 系列）或 N×4 字节（FT），
//       按 8 字节一组解析：x 低、x 高、y 低、y 高、尺寸低、尺寸高、id、保留；
//    3) 每解析完一个点给出 pt_valid 脉冲与 pt_id/pt_x/pt_y；
//       N 个点全部写完后给出 frame_valid 脉冲；
//    4) 不做原版的坐标位拼接（那是 FT 面板的特殊排布），直接输出原始 x/y，
//       重组交给软件，避免多点串坐标；
//    5) 跨时钟域交给外层 wrapper 用 req/ack 握手处理，本模块只跑 dri_clk。
//=====================================================================
module touch_dri_multi #(
	parameter WIDTH    = 8,
	parameter INIT_RST = 10_000,   // 复位保持时间，单位 1 us（仿真可缩短）
	parameter INIT_DLY = 60_000    // 复位后等待时间，单位 1 us
) (
	input  wire               clk          ,
	input  wire               rst_n        ,

	// iic 接口
	output reg  [6:0]         slave_addr   ,
	output reg                iic_exec     ,
	output reg                iic_rh_wl    ,
	output reg  [15:0]        iic_addr     ,
	output reg  [7:0]         iic_data_w   ,
	output reg                bit_ctrl     ,
	output reg  [WIDTH-1:0]   reg_num      ,
	input  wire [7:0]         iic_data     ,
	input  wire               iic_ack      ,
	input  wire               iic_done     ,
	input  wire               once_done    ,

	// 面板与触摸屏控制
	input  wire [15:0]        lcd_id       ,
	input  wire [3:0]         maxpoint     ,   // 最大上报点数 1~5
	input  wire [31:0]        interval     ,   // 采样间隔，单位 32 MHz 周期
	output reg                touch_rst_n  ,
	input  wire               touch_int_in ,
	output reg                touch_int_dir,
	output reg                touch_int_out,

	// 解析结果（dri_clk 域）
	output reg  [3:0]         pt_id        ,
	output reg  [13:0]        pt_x         ,
	output reg  [13:0]        pt_y         ,
	output reg                pt_valid     ,
	output reg  [3:0]         pt_num       ,   // 本帧点数
	output reg                frame_valid    // 本帧结束脉冲
);

	localparam FT_slave_addr_r = 7'h38;
	localparam FT_bit_ctrl_r   = 1'b0;
	localparam FT_ID_LIB_VERSION = 8'hA1;
	localparam FT_DEVIDE_MODE  = 8'h00;
	localparam FT_ID_MODE      = 8'hA4;
	localparam FT_ID_THGROUP   = 8'h80;
	localparam FT_ID_PERIOD_ACT= 8'h88;
	localparam FT_STATE_REG    = 8'h02;
	localparam FT_TP1_REG      = 8'h03;

	localparam GT_slave_addr_r = 7'h14;
	localparam GT_bit_ctrl_r   = 1'b1;
	localparam GT_STATE_REG    = 16'h814E;
	localparam GT_TP1_REG      = 16'h8150;

	localparam st_idle         = 4'd0;
	localparam st_init         = 4'd1;
	localparam st_get_id       = 4'd2;
	localparam st_cfg_reg      = 4'd3;
	localparam st_check_touch  = 4'd4;
	localparam st_get_coord    = 4'd5;
	localparam st_coord_handle = 4'd6;

	reg [3:0]  cur_status, next_status;
	reg        cnt_1us_en;
	reg [19:0] cnt_1us_cnt;
	reg [15:0] chip_version;
	reg        ft_flag;
	reg [15:0] touch_s_reg;
	reg [15:0] coord_reg;
	reg [3:0]  flow_cnt;
	reg        st_done;

	// 坐标解析
	reg  [5:0] byte_cnt;
	reg  [5:0] total_bytes;
	reg  [3:0] point_idx;
	reg  [15:0] x_tmp, y_tmp;
	reg  [3:0]  id_tmp;
	reg         in_coord;

	// 采样间隔换算成 1 us 计数（interval 单位 32 MHz 周期，除以 32）
	wire [15:0] iv_us = (interval[20:5] == 16'd0) ? 16'd1 : interval[20:5];

	// ---------------- 状态机 ----------------
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) cur_status <= st_idle;
		else        cur_status <= next_status;
	end

	always @(*) begin
		case (cur_status)
			st_idle        : next_status = st_done ? st_init : st_idle;
			st_init        : next_status = st_done ? st_get_id : st_init;
			st_get_id      : next_status = st_done ? (ft_flag ? st_cfg_reg : st_check_touch) : st_get_id;
			st_cfg_reg     : next_status = st_done ? st_check_touch : st_cfg_reg;
			st_check_touch : next_status = st_done ? st_get_coord   : st_check_touch;
			st_get_coord   : next_status = st_done ? st_coord_handle: st_get_coord;
			st_coord_handle: next_status = st_done ? st_check_touch : st_coord_handle;
			default        : next_status = st_idle;
		endcase
	end

	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			cnt_1us_cnt   <= 20'd0;
		end else if (cnt_1us_en) begin
			cnt_1us_cnt   <= cnt_1us_cnt + 1'b1;
		end else begin
			cnt_1us_cnt   <= 20'd0;
		end
	end

	// ---------------- 主流程 ----------------
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			chip_version <= 16'b0;
			ft_flag      <= 1'b0;
			touch_s_reg  <= 16'b0;
			coord_reg    <= 16'b0;
			flow_cnt     <= 4'b0;
			st_done      <= 1'b0;
			cnt_1us_en   <= 1'b0;
			touch_int_dir<= 1'b0;
			touch_int_out<= 1'b0;
			touch_rst_n  <= 1'b0;
			slave_addr   <= 7'b0;
			iic_exec     <= 1'b0;
			iic_rh_wl    <= 1'b0;
			iic_addr     <= 16'b0;
			iic_data_w   <= 8'b0;
			bit_ctrl     <= 1'b0;
			reg_num      <= {WIDTH{1'b0}};
			pt_num       <= 4'd0;
			frame_valid  <= 1'b0;
			byte_cnt     <= 6'd0;
			total_bytes  <= 6'd0;
			point_idx    <= 4'd0;
			x_tmp        <= 16'd0;
			y_tmp        <= 16'd0;
			id_tmp       <= 4'd0;
			in_coord     <= 1'b0;
		end else begin
			iic_exec    <= 1'b0;
			st_done     <= 1'b0;
			frame_valid <= 1'b0;
			pt_valid    <= 1'b0;

			// 与原版一致：分支描述的是“下一状态”的动作，st_done 表示该状态处理完毕
			case (next_status)
				// -------- 上电与 ID 识别 --------
				st_idle : begin
					cnt_1us_en    <= 1'b1;
					touch_int_dir <= 1'b1;
					touch_int_out <= 1'b1;
					if (cnt_1us_cnt >= 10) begin
						st_done    <= 1'b1;
						cnt_1us_en <= 1'b0;
					end
				end
				st_init : begin
					cnt_1us_en <= 1'b1;
					if (cnt_1us_cnt < INIT_RST) begin
						touch_rst_n <= 1'b0;
					end else if (cnt_1us_cnt == INIT_RST) begin
						touch_rst_n <= 1'b1;
					end else if (cnt_1us_cnt == INIT_DLY) begin
						touch_int_dir <= 1'b0;
						cnt_1us_en    <= 1'b0;
						st_done       <= 1'b1;
						flow_cnt      <= 4'd0;
					end
				end
				st_get_id : begin
					case (flow_cnt)
						4'd0 : begin
							if (lcd_id == 16'h4342 || lcd_id == 16'h4384 ||
							    lcd_id == 16'h7084 || lcd_id == 16'h7016) begin
								flow_cnt <= 4'd5;
								ft_flag  <= 1'b0;
							end else begin
								flow_cnt <= flow_cnt + 1'b1;
							end
						end
						4'd1 : begin
							iic_exec   <= 1'b1;
							iic_rh_wl  <= 1'b1;
							iic_addr   <= FT_ID_LIB_VERSION;
							reg_num    <= 8'd2;
							slave_addr <= FT_slave_addr_r;
							bit_ctrl   <= FT_bit_ctrl_r;
							flow_cnt   <= flow_cnt + 1'b1;
						end
						4'd2 : begin
							if (once_done) begin
								chip_version[15:8] <= iic_data;
								flow_cnt <= flow_cnt + 1'b1;
							end else if (iic_done && iic_ack) begin
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
							if (chip_version == 16'h3003 || chip_version == 16'h0001 ||
							    chip_version == 16'h0002 || chip_version == 16'h0000)
								ft_flag <= 1'b1;
							else
								ft_flag <= 1'b0;
						end
						4'd5 : begin
							st_done  <= 1'b1;
							flow_cnt <= 4'd0;
							if (ft_flag) begin
								touch_s_reg <= FT_STATE_REG;
								coord_reg   <= FT_TP1_REG;
								bit_ctrl    <= FT_bit_ctrl_r;
								slave_addr  <= FT_slave_addr_r;
							end else begin
								touch_s_reg <= GT_STATE_REG;
								coord_reg   <= GT_TP1_REG;
								bit_ctrl    <= GT_bit_ctrl_r;
								slave_addr  <= GT_slave_addr_r;
							end
						end
						default : ;
					endcase
				end
				// -------- FT 系列寄存器配置 --------
				st_cfg_reg : begin
					case (flow_cnt)
						4'd0 : begin iic_exec<=1'b1; iic_rh_wl<=1'b0; iic_addr<=FT_DEVIDE_MODE;
						              iic_data_w<=8'd0; reg_num<=8'd1; flow_cnt<=flow_cnt+1'b1; end
						4'd1 : if (iic_done) flow_cnt <= iic_ack ? flow_cnt - 1'b1 : flow_cnt + 1'b1;
						4'd2 : begin iic_exec<=1'b1; iic_rh_wl<=1'b0; iic_addr<=FT_ID_MODE;
						              iic_data_w<=8'd0; reg_num<=8'd1; flow_cnt<=flow_cnt+1'b1; end
						4'd3 : if (iic_done) flow_cnt <= iic_ack ? flow_cnt - 1'b1 : flow_cnt + 1'b1;
						4'd4 : begin iic_exec<=1'b1; iic_rh_wl<=1'b0; iic_addr<=FT_ID_THGROUP;
						              iic_data_w<=8'd22; reg_num<=8'd1; flow_cnt<=flow_cnt+1'b1; end
						4'd5 : if (iic_done) flow_cnt <= iic_ack ? flow_cnt - 1'b1 : flow_cnt + 1'b1;
						4'd6 : begin iic_exec<=1'b1; iic_rh_wl<=1'b0; iic_addr<=FT_ID_PERIOD_ACT;
						              iic_data_w<=8'd12; reg_num<=8'd1; flow_cnt<=flow_cnt+1'b1; end
						4'd7 : if (iic_done) begin
						            if (iic_ack) flow_cnt <= flow_cnt - 1'b1;
						            else begin flow_cnt <= 4'd0; st_done <= 1'b1; end
						        end
						default : ;
					endcase
				end
				// -------- 读状态：点数 --------
				st_check_touch : begin
					case (flow_cnt)
						4'd0 : begin
							cnt_1us_en <= 1'b1;
							if (cnt_1us_cnt >= iv_us) begin
								flow_cnt   <= flow_cnt + 1'b1;
								cnt_1us_en <= 1'b0;
							end
						end
						4'd1 : begin
							iic_exec  <= 1'b1;
							iic_rh_wl <= 1'b1;
							iic_addr  <= touch_s_reg;
							reg_num   <= 8'd1;
							flow_cnt  <= flow_cnt + 1'b1;
						end
						4'd2 : begin
							// iic_ack == 0 表示从设备应答，可以前进；否则退回去重读
							if (iic_done) flow_cnt <= iic_ack ? flow_cnt - 1'b1 : flow_cnt + 1'b1;
						end
						4'd3 : begin
							flow_cnt <= flow_cnt + 1'b1;
							// 取点数并钳位到 maxpoint（0 表示无触摸）
							if (ft_flag) begin
								pt_num <= (iic_data[3:0] == 4'd0) ? 4'd0 : 4'd1;
							end else if (iic_data[7] && iic_data[3:0] != 4'd0) begin
								if (iic_data[3:0] > maxpoint) pt_num <= maxpoint;
								else                          pt_num <= iic_data[3:0];
							end else begin
								pt_num <= 4'd0;
							end
						end
						4'd4 : begin
							iic_exec   <= 1'b1;
							iic_rh_wl  <= 1'b0;
							iic_addr   <= touch_s_reg;
							iic_data_w <= 8'd0;          // 清状态，否则不会产生下一帧
							reg_num    <= 8'd1;
							flow_cnt   <= flow_cnt + 1'b1;
						end
						4'd5 : begin
							if (iic_done) begin
								if (iic_ack == 1'b0) begin
									st_done  <= (pt_num != 4'd0);
									flow_cnt <= 4'd0;
								end else begin
									flow_cnt <= flow_cnt - 1'b1;
								end
							end
						end
						default : ;
					endcase
				end
				// -------- 按 N 读坐标区并逐字节解析 --------
				st_get_coord : begin
					if (flow_cnt == 4'd0) begin
						total_bytes <= ft_flag ? ({2'b00, pt_num} << 2) : ({2'b00, pt_num} << 3);
						byte_cnt    <= 6'd0;
						point_idx   <= 4'd0;
						in_coord    <= 1'b1;
						iic_exec    <= 1'b1;
						iic_rh_wl   <= 1'b1;
						iic_addr    <= coord_reg;
						reg_num     <= ft_flag ? ({4'd0, pt_num} << 2) : ({4'd0, pt_num} << 3);
						flow_cnt    <= 4'd1;
					end else if (flow_cnt == 4'd1) begin
						if (once_done) begin
							// 按组解析：GT 8 字节 / FT 4 字节
							if (ft_flag) begin
								case (byte_cnt[1:0])
									2'd0: x_tmp[7:0]  <= iic_data;
									2'd1: x_tmp[15:8] <= iic_data;
									2'd2: y_tmp[7:0]  <= iic_data;
									2'd3: begin
										y_tmp[15:8] <= iic_data;
										// FT：x/y 低 4 位与高字节互换（原版处理）
										pt_id    <= 4'd0;
										pt_x     <= {4'd0, y_tmp[3:0], y_tmp[15:8]};
										pt_y     <= {4'd0, x_tmp[3:0], x_tmp[15:8]};
										pt_valid <= 1'b1;
										point_idx<= point_idx + 1'b1;
									end
								endcase
							end else begin
								case (byte_cnt[2:0])
									3'd0: x_tmp[7:0]  <= iic_data;
									3'd1: x_tmp[15:8] <= iic_data;
									3'd2: y_tmp[7:0]  <= iic_data;
									3'd3: y_tmp[15:8] <= iic_data;
									3'd6: id_tmp      <= iic_data[3:0];
									3'd7: begin
										pt_id    <= id_tmp;
										pt_x     <= x_tmp[13:0];
										pt_y     <= y_tmp[13:0];
										pt_valid <= 1'b1;
										point_idx<= point_idx + 1'b1;
									end
									default : ;
								endcase
							end

							if (byte_cnt == total_bytes - 6'd1) begin
								flow_cnt <= 4'd2;          // 全部字节读完
							end else begin
								byte_cnt <= byte_cnt + 6'd1;
							end
						end else if (iic_done && !iic_ack) begin
							flow_cnt <= 4'd2;              // 无应答，本轮放弃
						end
					end else begin
						st_done  <= 1'b1;
						flow_cnt <= 4'd0;
					end
				end
				st_coord_handle : begin
					st_done     <= 1'b1;
					frame_valid <= 1'b1;                   // 一帧结束，外层据此更新点数
					in_coord    <= 1'b0;
				end
				default : ;
			endcase
		end
	end

endmodule
