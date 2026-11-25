//=====================================================================
//  apb_dot.v  ——  实验七：8×8 LED 点阵数字显示控制器
//---------------------------------------------------------------------
//  功能 :
//    内置 0~9 十个 8×8 字形码（每字符 8 字节，按行存放，bit0 为最左列）；
//    自动逐行扫描，默认行周期 125 us（8 行一轮 1 ms，刷新 1 kHz）；
//    三种模式：字符 / 图形 / 滚动；亮度 8 级（行内 PWM）；1 Hz 闪烁；
//    写字符或写图形后置忙标志，扫完一帧清忙。
//  地址 : APB 编号 7，基址 0x3007_0000
//  寄存器 :
//    0x00 CTRL    RW bit0 使能 / bit1 闪烁 / bit[4:2] 亮度 0~7（0 最暗）
//                     / bit[6:5] 模式 (00 字符 01 图形 10 滚动)
//    0x04 CHAR    RW bit[3:0] 字符码 0~9，写入即装入该字形
//    0x08 ROWDIV  RW 行周期，单位 32 MHz 周期，默认 4000（125 us）
//    0x0C RAM0    RW 图形模式第 0~3 行，每 8 位一行
//    0x10 RAM1    RW 图形模式第 4~7 行
//    0x14 SHIFT   RW bit[3:0] 每多少帧移一列
//    0x18 STATUS  R  bit0 忙 / bit[7:0] 当前行号 / bit[15:8] 帧计数
//    0x1C VERSION R  固定 0x444F_0001 ("DO")
//  端口 : dot_row[7:0] 行选（低有效），dot_col[7:0] 列数据（高有效）
//=====================================================================
module apb_dot (
	input  wire        apb_pclk   ,
	input  wire        apb_prstn  ,
	input  wire        apb_psel   ,
	input  wire [31:0] apb_paddr  ,
	input  wire        apb_pwrite ,
	input  wire        apb_penable,
	input  wire [31:0] apb_pwdata ,
	output wire [31:0] apb_prdata ,
	output wire        apb_pready ,

	output wire [7:0]  dot_row    ,
	output wire [7:0]  dot_col    ,
	output wire        dot_frame_irq   // 每扫完一帧（8 行）出一个单拍脉冲
);

	localparam [7:0] R_CTRL    = 8'h00;
	localparam [7:0] R_CHAR    = 8'h04;
	localparam [7:0] R_ROWDIV  = 8'h08;
	localparam [7:0] R_RAM0    = 8'h0c;
	localparam [7:0] R_RAM1    = 8'h10;
	localparam [7:0] R_SHIFT   = 8'h14;
	localparam [7:0] R_STATUS  = 8'h18;
	localparam [7:0] R_VERSION = 8'h1c;

	reg  [31:0] ctrl;
	reg  [31:0] char_reg;
	reg  [31:0] rowdiv;
	reg  [7:0]  shift_frames;     // 滚动：每多少帧移一列
	reg  [7:0]  fb [0:7];         // 当前帧缓冲，bit0 = 最左列

	reg  [2:0]  row;
	reg  [31:0] row_cnt;
	reg  [2:0]  pwm_ph;
	reg  [31:0] pwm_div;
	reg  [31:0] frame_cnt;
	reg         busy;
	reg  [2:0]  scroll_idx;
	reg  [7:0]  shift_wait;
	reg         frame_end;        // 一帧扫完的当拍脉冲
	reg         busy_set;         // 本拍有写操作需要置忙

	reg  [31:0] prdata;

	wire        wr, rd;
	wire        en, blink_en;
	wire [2:0]  bright;
	wire [1:0]  mode;
	wire [7:0]  row_data;
	wire        col_on;
	wire        blink_off;
	wire [31:0] phase_div;
	wire        row_end;
	wire        phase_end;

	assign wr = apb_psel &  apb_pwrite & apb_penable;
	assign rd = apb_psel & !apb_pwrite & apb_penable;
	assign apb_pready = apb_penable;

	assign en       = ctrl[0];
	assign blink_en = ctrl[1];
	assign bright   = ctrl[4:2];
	assign mode     = ctrl[6:5];

	// ---------------- 0~9 字形码（每字符 8 行，bit0 最左列） ----------------
	function [7:0] font_row;
		input [3:0] ch;
		input [2:0] r;
		begin
			case (ch)
				4'd0: case (r) 3'd0: font_row=8'h3C; 3'd1: font_row=8'h66; 3'd2: font_row=8'h6E;
				                   3'd3: font_row=8'h76; 3'd4: font_row=8'h66; 3'd5: font_row=8'h66;
				                   3'd6: font_row=8'h3C; default: font_row=8'h00; endcase
				4'd1: case (r) 3'd0: font_row=8'h18; 3'd1: font_row=8'h38; 3'd2: font_row=8'h18;
				                   3'd3: font_row=8'h18; 3'd4: font_row=8'h18; 3'd5: font_row=8'h18;
				                   3'd6: font_row=8'h7E; default: font_row=8'h00; endcase
				4'd2: case (r) 3'd0: font_row=8'h3C; 3'd1: font_row=8'h66; 3'd2: font_row=8'h06;
				                   3'd3: font_row=8'h0C; 3'd4: font_row=8'h30; 3'd5: font_row=8'h60;
				                   3'd6: font_row=8'h7E; default: font_row=8'h00; endcase
				4'd3: case (r) 3'd0: font_row=8'h3C; 3'd1: font_row=8'h66; 3'd2: font_row=8'h06;
				                   3'd3: font_row=8'h1C; 3'd4: font_row=8'h06; 3'd5: font_row=8'h66;
				                   3'd6: font_row=8'h3C; default: font_row=8'h00; endcase
				4'd4: case (r) 3'd0: font_row=8'h0C; 3'd1: font_row=8'h1C; 3'd2: font_row=8'h3C;
				                   3'd3: font_row=8'h6C; 3'd4: font_row=8'h7E; 3'd5: font_row=8'h0C;
				                   3'd6: font_row=8'h0C; default: font_row=8'h00; endcase
				4'd5: case (r) 3'd0: font_row=8'h7E; 3'd1: font_row=8'h60; 3'd2: font_row=8'h7C;
				                   3'd3: font_row=8'h06; 3'd4: font_row=8'h06; 3'd5: font_row=8'h66;
				                   3'd6: font_row=8'h3C; default: font_row=8'h00; endcase
				4'd6: case (r) 3'd0: font_row=8'h1C; 3'd1: font_row=8'h30; 3'd2: font_row=8'h60;
				                   3'd3: font_row=8'h7C; 3'd4: font_row=8'h66; 3'd5: font_row=8'h66;
				                   3'd6: font_row=8'h3C; default: font_row=8'h00; endcase
				4'd7: case (r) 3'd0: font_row=8'h7E; 3'd1: font_row=8'h66; 3'd2: font_row=8'h0C;
				                   3'd3: font_row=8'h18; 3'd4: font_row=8'h18; 3'd5: font_row=8'h18;
				                   3'd6: font_row=8'h18; default: font_row=8'h00; endcase
				4'd8: case (r) 3'd0: font_row=8'h3C; 3'd1: font_row=8'h66; 3'd2: font_row=8'h66;
				                   3'd3: font_row=8'h3C; 3'd4: font_row=8'h66; 3'd5: font_row=8'h66;
				                   3'd6: font_row=8'h3C; default: font_row=8'h00; endcase
				4'd9: case (r) 3'd0: font_row=8'h3C; 3'd1: font_row=8'h66; 3'd2: font_row=8'h66;
				                   3'd3: font_row=8'h3E; 3'd4: font_row=8'h06; 3'd5: font_row=8'h0C;
				                   3'd6: font_row=8'h38; default: font_row=8'h00; endcase
				default: font_row = 8'h00;
			endcase
		end
	endfunction

	// ---------------- APB 控制寄存器 ----------------
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			ctrl         <= 32'h0;
			char_reg     <= 32'h0;
			rowdiv       <= 32'd4000;
			shift_frames <= 8'd1;
			busy_set     <= 1'b0;
		end else begin
			busy_set <= wr && ((apb_paddr[7:0] == R_CHAR ) ||
			                   (apb_paddr[7:0] == R_RAM0 ) ||
			                   (apb_paddr[7:0] == R_RAM1 ));
			if (wr) begin
				case (apb_paddr[7:0])
					R_CTRL   : ctrl         <= apb_pwdata;
					R_CHAR   : char_reg     <= {28'd0, apb_pwdata[3:0]};
					R_ROWDIV : rowdiv       <= (apb_pwdata < 32'd8) ? 32'd8 : apb_pwdata;
					R_SHIFT  : shift_frames <= (apb_pwdata[7:0] == 8'd0) ? 8'd1 : apb_pwdata[7:0];
					default : ;
				endcase
			end
		end
	end

	// ---------------- 帧缓冲更新（唯一驱动点） ----------------
	// 滚动源：char_reg 指定字形的第 scroll_idx 列
	wire [7:0] s_row0 = font_row(char_reg[3:0], 3'd0) >> scroll_idx;
	wire [7:0] s_row1 = font_row(char_reg[3:0], 3'd1) >> scroll_idx;
	wire [7:0] s_row2 = font_row(char_reg[3:0], 3'd2) >> scroll_idx;
	wire [7:0] s_row3 = font_row(char_reg[3:0], 3'd3) >> scroll_idx;
	wire [7:0] s_row4 = font_row(char_reg[3:0], 3'd4) >> scroll_idx;
	wire [7:0] s_row5 = font_row(char_reg[3:0], 3'd5) >> scroll_idx;
	wire [7:0] s_row6 = font_row(char_reg[3:0], 3'd6) >> scroll_idx;
	wire [7:0] s_row7 = font_row(char_reg[3:0], 3'd7) >> scroll_idx;

	// 滚动节奏：每 shift_frames 帧移一列
	wire scroll_tick = (shift_wait >= shift_frames - 8'd1);

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			fb[0] <= 8'h00; fb[1] <= 8'h00; fb[2] <= 8'h00; fb[3] <= 8'h00;
			fb[4] <= 8'h00; fb[5] <= 8'h00; fb[6] <= 8'h00; fb[7] <= 8'h00;
		end else if (wr && apb_paddr[7:0] == R_RAM0) begin
			fb[0] <= apb_pwdata[7:0];   fb[1] <= apb_pwdata[15:8];
			fb[2] <= apb_pwdata[23:16]; fb[3] <= apb_pwdata[31:24];
		end else if (wr && apb_paddr[7:0] == R_RAM1) begin
			fb[4] <= apb_pwdata[7:0];   fb[5] <= apb_pwdata[15:8];
			fb[6] <= apb_pwdata[23:16]; fb[7] <= apb_pwdata[31:24];
		end else if (wr && apb_paddr[7:0] == R_CHAR) begin
			fb[0] <= font_row(apb_pwdata[3:0], 3'd0);
			fb[1] <= font_row(apb_pwdata[3:0], 3'd1);
			fb[2] <= font_row(apb_pwdata[3:0], 3'd2);
			fb[3] <= font_row(apb_pwdata[3:0], 3'd3);
			fb[4] <= font_row(apb_pwdata[3:0], 3'd4);
			fb[5] <= font_row(apb_pwdata[3:0], 3'd5);
			fb[6] <= font_row(apb_pwdata[3:0], 3'd6);
			fb[7] <= font_row(apb_pwdata[3:0], 3'd7);
		end else if (frame_end && (mode == 2'b10) && scroll_tick) begin
			fb[0] <= {s_row0[0], fb[0][7:1]};
			fb[1] <= {s_row1[0], fb[1][7:1]};
			fb[2] <= {s_row2[0], fb[2][7:1]};
			fb[3] <= {s_row3[0], fb[3][7:1]};
			fb[4] <= {s_row4[0], fb[4][7:1]};
			fb[5] <= {s_row5[0], fb[5][7:1]};
			fb[6] <= {s_row6[0], fb[6][7:1]};
			fb[7] <= {s_row7[0], fb[7][7:1]};
		end
	end

	// ---------------- 行扫描 + 行内 PWM ----------------
	assign phase_div = (rowdiv >> 3) == 32'd0 ? 32'd1 : (rowdiv >> 3);
	assign row_end   = (row_cnt >= rowdiv - 32'd1);
	assign phase_end = (pwm_div >= phase_div - 32'd1);

	// 滚动节奏判断已在帧缓冲更新前定义为 scroll_tick

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			row        <= 3'd0;
			row_cnt    <= 32'd0;
			pwm_ph     <= 3'd0;
			pwm_div    <= 32'd0;
			frame_cnt  <= 32'd0;
			frame_end  <= 1'b0;
			scroll_idx <= 3'd0;
			shift_wait <= 8'd0;
			busy       <= 1'b0;
		end else begin
			frame_end <= 1'b0;

			// 忙标志：写字符/图形置位，帧结束清除
			if (busy_set)                busy <= 1'b1;
			else if (frame_end)          busy <= 1'b0;

			if (!en) begin
				row     <= 3'd0;
				row_cnt <= 32'd0;
				pwm_ph  <= 3'd0;
				pwm_div <= 32'd0;
				frame_end <= 1'b0;
			end else begin
				// 行内 PWM 相位：把行周期均分 8 份
				if (phase_end) begin
					pwm_div <= 32'd0;
					pwm_ph  <= (pwm_ph == 3'd7) ? 3'd0 : pwm_ph + 3'd1;
				end else begin
					pwm_div <= pwm_div + 32'd1;
				end

				if (row_end) begin
					row_cnt <= 32'd0;
					pwm_ph  <= 3'd0;
					pwm_div <= 32'd0;
					if (row == 3'd7) begin
						row        <= 3'd0;
						frame_cnt  <= frame_cnt + 32'd1;
						frame_end  <= 1'b1;
						scroll_idx <= scroll_idx + 3'd1;
						if (scroll_tick) shift_wait <= 8'd0;
						else             shift_wait <= shift_wait + 8'd1;
					end else begin
						row <= row + 3'd1;
					end
				end else begin
					row_cnt <= row_cnt + 32'd1;
				end
			end
		end
	end

	// ---------------- 显示输出 ----------------
	assign row_data = fb[row];

	// 亮度等级 n：行内前 n/8 的时间点亮；n=0 全灭
	assign col_on = (pwm_ph < bright);

	// 闪烁：1 kHz 帧率下 frame_cnt[9] 约 1 Hz；只关断输出，不清帧内容
	assign blink_off = blink_en & frame_cnt[9];

	assign dot_row = (en && !blink_off) ? ~(8'h01 << row) : 8'hff;
	assign dot_col = (en && !blink_off && col_on) ? row_data : 8'h00;
	assign dot_frame_irq = frame_end;

	always @(*) begin
		if (rd) begin
			case (apb_paddr[7:0])
				R_CTRL    : prdata = ctrl;
				R_CHAR    : prdata = char_reg;
				R_ROWDIV  : prdata = rowdiv;
				R_RAM0    : prdata = {fb[3], fb[2], fb[1], fb[0]};
				R_RAM1    : prdata = {fb[7], fb[6], fb[5], fb[4]};
				R_SHIFT   : prdata = {24'd0, shift_frames};
				R_STATUS  : prdata = {15'd0, frame_cnt[7:0], 5'd0, row, busy};
				R_VERSION : prdata = 32'h444f_0001;
				default   : prdata = 32'b0;
			endcase
		end else begin
			prdata = 32'b0;
		end
	end
	assign apb_prdata = prdata;

endmodule
