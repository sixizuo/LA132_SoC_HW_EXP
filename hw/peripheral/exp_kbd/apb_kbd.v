//=====================================================================
//  apb_kbd.v  ——  实验六：4×4 矩阵键盘 APB 控制器
//---------------------------------------------------------------------
//  功能 :
//    行线低有效轮流驱动（每行 row_div 个 32 MHz 周期），列线回读；
//    一轮扫完得到一个键码 {row[1:0], col[1:0]}（5'h1F 表示无键，
//    2026-11-25 修正：原 0xF 哨兵与 15 号键码冲突，15 号键报不出来）；
//    连续 DEBOUNCE 轮一致才确认，按下与松开都消抖；
//    确认新键值时给出 8 位键值（经 KEYMAP 映射），并可产生一拍中断脉冲；
//    按住不放只上报一次，松开后再次按下才上报第二个键值。
//  地址 : APB 编号 5，基址 0x3005_0000
//  寄存器 :
//    0x00 CTRL     RW  bit0 使能 / bit1 中断使能 / bit[3:2] 扫描周期
//                      (00=1ms 01=2ms 10=5ms 11=10ms) / bit4 清键值(自清)
//    0x04 STATUS   R   bit0 有新键值 / bit1 当前按下 / bit[7:4] 当前键值
//                      / bit[15:8] 消抖计数 / bit16 键值计数溢出
//    0x08 KEY      R   读键值并清 bit0；无新键值返回 0xFF
//    0x0C KEYMAP0  RW  扫描码 0~3 的映射值，每 8 位一个
//    0x10 KEYMAP1  RW  扫描码 4~7
//    0x14 KEYMAP2  RW  扫描码 8~11
//    0x18 KEYMAP3  RW  扫描码 12~15
//    0x1C DEBOUNCE RW  确认所需连续轮数，默认 8，写 0 按 1 处理
//    0x20 RAW      R   bit[3:0] 列线原始电平 / bit[7:4] 当前行号
//    0x24 VERSION  R   固定 0x4B42_0001 ("KB")
//  端口 : kbd_row[3:0] 行驱动（低有效，接 gpioa[19:16]）
//         kbd_col[3:0] 列采样（低有效，接 gpioa[11:8]，板上上拉）
//
//  2026-11-23 修正方向 : 本板实测 (driver/GPIO/demo_gpio_mode.c) 是
//    gpioa[19:16] 作行驱动, gpioa[11:8] 作列采样 (列有上拉)。
//    原先写成"列驱动/行采样"是反的, 上板后一个键都扫不到。
//=====================================================================
module apb_kbd (
	input  wire        apb_pclk   ,
	input  wire        apb_prstn  ,
	input  wire        apb_psel   ,
	input  wire [31:0] apb_paddr  ,
	input  wire        apb_pwrite ,
	input  wire        apb_penable,
	input  wire [31:0] apb_pwdata ,
	output wire [31:0] apb_prdata ,
	output wire        apb_pready ,

	output wire [3:0]  kbd_row    ,
	input  wire [3:0]  kbd_col    ,
	output wire        kbd_irq
);

	// ---- 寄存器偏移 ----
	localparam [7:0] R_CTRL     = 8'h00;
	localparam [7:0] R_STATUS   = 8'h04;
	localparam [7:0] R_KEY      = 8'h08;
	localparam [7:0] R_KEYMAP0  = 8'h0c;
	localparam [7:0] R_KEYMAP1  = 8'h10;
	localparam [7:0] R_KEYMAP2  = 8'h14;
	localparam [7:0] R_KEYMAP3  = 8'h18;
	localparam [7:0] R_DEBOUNCE = 8'h1c;
	localparam [7:0] R_RAW      = 8'h20;
	localparam [7:0] R_VERSION  = 8'h24;

	// ---- 扫描状态 ----
	localparam [2:0] S_IDLE   = 3'd0;
	localparam [2:0] S_DRIVE  = 3'd1;
	localparam [2:0] S_SAMPLE = 3'd2;
	localparam [2:0] S_JUDGE  = 3'd3;
	localparam [2:0] S_HIT    = 3'd4;

	reg  [31:0] ctrl;
	reg  [31:0] keymap0, keymap1, keymap2, keymap3;
	reg  [31:0] debounce;
	reg         clr_key;       // CTRL[4] 写 1 的当拍标志

	reg  [2:0]  st;
	reg  [2:0]  st_nxt;
	reg  [1:0]  row;
	reg  [31:0] row_cnt;

	reg  [4:0]  cur_code;      // 本轮扫描码。5'h1F = 无键（2026-11-25 改：
	                           //   原来 4'hF 当哨兵, 与键 {行3,列3}=4'hF 冲突,
	                           //   15 号键永远报不出来; 现在加 1 位"见过键"位,
	                           //   16 个键码全部可上报）
	reg  [4:0]  stable_code;   // 已稳定的扫描码
	reg  [7:0]  deb_cnt;       // 连续一致轮数
	reg         pressed;       // 当前处于按下状态（已上报）
	reg  [7:0]  key_val;       // 最近一次确认的键值
	reg         key_valid;     // 有新键值待读
	reg         key_cnt_ovf;   // 键值计数溢出（粘滞）
	reg  [15:0] key_cnt;
	reg         irq_r;

	reg  [31:0] prdata;

	wire        wr;
	wire        rd;
	wire        en;
	wire [1:0]  scan_sel;
	wire [31:0] row_div;
	wire [7:0]  deb_eff;
	wire [7:0]  map_val;
	wire [31:0] keymap_sel;
	wire [31:0] status_val;

	assign wr = apb_psel &  apb_pwrite & apb_penable;
	assign rd = apb_psel & !apb_pwrite & apb_penable;
	assign apb_pready = apb_penable;

	assign en       = ctrl[0];
	assign scan_sel = ctrl[3:2];

	// 每行驻留时间：一轮 1/2/5/10 ms，四行均分
	assign row_div = (scan_sel == 2'b00) ? 32'd8000  :   // 250 us
	                 (scan_sel == 2'b01) ? 32'd16000 :   // 500 us
	                 (scan_sel == 2'b10) ? 32'd40000 :   // 1.25 ms
	                                       32'd80000 ;   // 2.5 ms

	assign deb_eff = (debounce[7:0] == 8'd0) ? 8'd1 : debounce[7:0];

	// ---- 键值映射查表 ----
	assign keymap_sel = (cur_code[3:2] == 2'b00) ? keymap0 :
	                    (cur_code[3:2] == 2'b01) ? keymap1 :
	                    (cur_code[3:2] == 2'b10) ? keymap2 : keymap3;
	assign map_val = keymap_sel[{cur_code[1:0], 3'b000} +: 8];

	// ---- APB 读写 ----
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			ctrl     <= 32'h0000_0000;
			keymap0  <= 32'h0302_0100;   // 默认恒等映射 0,1,2,3
			keymap1  <= 32'h0706_0504;
			keymap2  <= 32'h0b0a_0908;
			keymap3  <= 32'h0f0e_0d0c;
			debounce <= 32'h0000_0008;
			clr_key  <= 1'b0;
		end else begin
			clr_key <= wr && (apb_paddr[7:0] == R_CTRL) && apb_pwdata[4];
			if (wr) begin
				case (apb_paddr[7:0])
					// bit4 是自清的“清键值”命令位，不保存
					R_CTRL     : ctrl     <= {27'd0, 1'b0, apb_pwdata[3:0]};
					R_KEYMAP0  : keymap0  <= apb_pwdata;
					R_KEYMAP1  : keymap1  <= apb_pwdata;
					R_KEYMAP2  : keymap2  <= apb_pwdata;
					R_KEYMAP3  : keymap3  <= apb_pwdata;
					R_DEBOUNCE : debounce <= apb_pwdata;
					default : ;
				endcase
			end
		end
	end

	// ---- 扫描状态机 ----
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			st <= S_IDLE;
		end else begin
			st <= st_nxt;
		end
	end

	always @(*) begin
		st_nxt = st;
		case (st)
			S_IDLE : if (en) st_nxt = S_DRIVE;
			S_DRIVE: if (row_cnt >= row_div - 1'b1) st_nxt = S_SAMPLE;
			S_SAMPLE: st_nxt = (row == 2'd3) ? S_JUDGE : S_DRIVE;
			S_JUDGE: if ((deb_cnt >= deb_eff - 8'd1) && (cur_code != 5'h1f) && !pressed)
			             st_nxt = S_HIT;
			         else
			             st_nxt = S_DRIVE;
			S_HIT  : st_nxt = S_DRIVE;
			default: st_nxt = S_IDLE;
		endcase
	end

	// 行号与行内计数
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			row     <= 2'd0;
			row_cnt <= 32'd0;
		end else if (!en) begin
			row     <= 2'd0;
			row_cnt <= 32'd0;
		end else begin
			case (st)
				S_DRIVE : begin
					if (row_cnt >= row_div - 1'b1) row_cnt <= 32'd0;
					else                          row_cnt <= row_cnt + 1'b1;
				end
				S_SAMPLE: begin
					row_cnt <= 32'd0;
					row     <= row + 1'b1;      // 0→1→2→3→0，4 行一轮
				end
				default : row_cnt <= 32'd0;
			endcase
		end
	end

	// 扫描码收集与消抖判定
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			cur_code    <= 5'h1f;
			stable_code <= 5'h1f;
			deb_cnt     <= 8'd0;
			pressed     <= 1'b0;
			key_val     <= 8'hff;
			key_valid   <= 1'b0;
			key_cnt     <= 16'd0;
			key_cnt_ovf <= 1'b0;
			irq_r       <= 1'b0;
		end else if (!en) begin
			cur_code    <= 5'h1f;
			stable_code <= 5'h1f;
			deb_cnt     <= 8'd0;
			pressed     <= 1'b0;
			irq_r       <= 1'b0;
		end else begin
			irq_r <= 1'b0;

			// CTRL[4]：清键值与溢出
			if (clr_key) begin
				key_valid   <= 1'b0;
				key_cnt_ovf <= 1'b0;
			end
			// 读 KEY：清新键值标志
			if (rd && apb_paddr[7:0] == R_KEY) begin
				key_valid <= 1'b0;
			end

			case (st)
				S_DRIVE : begin
					if (row == 2'd0) cur_code <= 5'h1f;   // 一轮开始，清空
				end
				S_SAMPLE: begin
					// 列线低有效：按优先级取最低的按下列，避免同时多键时码值抖动
					// 5 位编码: bit4=0 表示本轮见过键, 键码全 16 个都合法
					if (cur_code == 5'h1f) begin
						if      (kbd_col[0] == 1'b0) cur_code <= {1'b0, row[1:0], 2'd0};
						else if (kbd_col[1] == 1'b0) cur_code <= {1'b0, row[1:0], 2'd1};
						else if (kbd_col[2] == 1'b0) cur_code <= {1'b0, row[1:0], 2'd2};
						else if (kbd_col[3] == 1'b0) cur_code <= {1'b0, row[1:0], 2'd3};
					end
				end
				S_JUDGE : begin
					if (cur_code == stable_code) begin
						if (deb_cnt < deb_eff - 8'd1) begin
							deb_cnt <= deb_cnt + 1'b1;
						end else if (cur_code != 5'h1f && !pressed) begin
							// 确认新键
							stable_code <= cur_code;
							key_val     <= map_val;
							key_valid   <= 1'b1;
							pressed     <= 1'b1;
							irq_r       <= ctrl[1];
							if (key_cnt == 16'hffff) key_cnt_ovf <= 1'b1;
							key_cnt     <= key_cnt + 1'b1;
						end else if (cur_code == 5'h1f && pressed) begin
							// 确认松手，允许下次上报
							stable_code <= 5'h1f;
							pressed     <= 1'b0;
							deb_cnt     <= 8'd0;
						end
					end else begin
						stable_code <= cur_code;
						deb_cnt     <= 8'd0;
					end
				end
				default : ;
			endcase
		end
	end

	assign kbd_row = (en && (st == S_DRIVE || st == S_SAMPLE)) ? ~(4'h1 << row) : 4'hf;
	assign kbd_irq = irq_r;

	// STATUS 位分配：bit16 溢出 / bit[15:8] 消抖计数 / bit[7:4] 当前键值
	//                 / bit[3:2] 保留 / bit1 按住 / bit0 有新键值
	assign status_val = {15'b0, key_cnt_ovf, deb_cnt, key_val[3:0], 2'b00, pressed, key_valid};

	always @(*) begin
		if (rd) begin
			case (apb_paddr[7:0])
				R_CTRL     : prdata = ctrl;
				R_STATUS   : prdata = status_val;
				R_KEY      : prdata = key_valid ? {24'b0, key_val} : 32'h0000_00ff;
				R_KEYMAP0  : prdata = keymap0;
				R_KEYMAP1  : prdata = keymap1;
				R_KEYMAP2  : prdata = keymap2;
				R_KEYMAP3  : prdata = keymap3;
				R_DEBOUNCE : prdata = debounce;
				R_RAW      : prdata = {24'b0, row, kbd_col};
				R_VERSION  : prdata = 32'h4b42_0001;
				default    : prdata = 32'b0;
			endcase
		end else begin
			prdata = 32'b0;
		end
	end
	assign apb_prdata = prdata;

endmodule
