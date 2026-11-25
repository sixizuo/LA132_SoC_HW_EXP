//=====================================================================
//  tb_apb_kbd.v  ——  实验六 矩阵键盘控制器自检激励
//---------------------------------------------------------------------
//  模型 : 用组合逻辑模拟一块 4×4 键盘——被按下的键所在行被拉低时，
//         对应列线读回 0，其余列读回 1；没有按键时列线全 1。
//  覆盖 :
//    1) 复位值与 VERSION
//    2) 无键时 KEY=0xFF、STATUS[0]=0
//    3) 单键确认：键值正确、STATUS[1]=1、kbd_irq 出现且只有一个脉冲
//    4) 按住不放不重复上报；松手后再按产生第二个键值
//    5) KEYMAP 重映射
//    6) DEBOUNCE 改成 2 后确认变快
//    7) RAW 寄存器反映当前行号与列电平
//=====================================================================
`timescale 1ns / 1ps

module tb_apb_kbd;

	localparam CLK_PERIOD = 31.25;

	reg         clk;
	reg         rstn;
	reg         psel, penable, pwrite;
	reg  [31:0] paddr, pwdata;
	wire [31:0] prdata;
	wire        pready;

	reg  [3:0]  kbd_col;   // 键盘模型: 列（由模型拉低）
	wire [3:0]  kbd_row;   // DUT 驱动的行
	wire        kbd_irq;

	// 键盘模型：DUT 把某一行拉低时，该行上被按下的键把所在列拉低
	reg  [1:0]  key_r, key_c;
	reg         key_on;
	always @(*) begin
		if (key_on && (kbd_row[key_r] == 1'b0))
			kbd_col = ~(4'h1 << key_c);
		else
			kbd_col = 4'hf;
	end

	apb_kbd dut (
		.apb_pclk    (clk    ),
		.apb_prstn   (rstn   ),
		.apb_psel    (psel   ),
		.apb_paddr   (paddr  ),
		.apb_pwrite  (pwrite ),
		.apb_penable (penable),
		.apb_pwdata  (pwdata ),
		.apb_prdata  (prdata ),
		.apb_pready  (pready ),
		.kbd_col     (kbd_col),
		.kbd_row     (kbd_row),
		.kbd_irq     (kbd_irq)
	);

	always #(CLK_PERIOD/2) clk = ~clk;

	integer errors = 0;
	integer irq_cnt = 0;

	always @(posedge clk) if (kbd_irq) irq_cnt = irq_cnt + 1;

	task chk;
		input [255:0] name;
		input [31:0]  got;
		input [31:0]  exp;
		begin
			if (got !== exp) begin
				$display("FAIL %0s : got=0x%08x exp=0x%08x (t=%0t)", name, got, exp, $time);
				errors = errors + 1;
			end else begin
				$display("pass %0s : 0x%08x", name, got);
			end
		end
	endtask

	task apb_wr;
		input [31:0] a, d;
		begin
			@(negedge clk);
			psel = 1; penable = 0; pwrite = 1; paddr = a; pwdata = d;
			@(negedge clk);
			penable = 1;
			@(negedge clk);
			psel = 0; penable = 0; pwrite = 0;
			@(negedge clk);
		end
	endtask

	task apb_rd;
		input  [31:0] a;
		output [31:0] d;
		begin
			@(negedge clk);
			psel = 1; penable = 0; pwrite = 0; paddr = a;
			@(negedge clk);
			penable = 1;
			#1 d = prdata;          // APB 主设备在完成沿之前采样，等效真实 CPU 的建立时间
			@(negedge clk);
			psel = 0; penable = 0;
			@(negedge clk);
		end
	endtask

	// 等待 ms 毫秒（32 MHz 下 32000 周期/ms）
	task wait_ms;
		input integer ms;
		integer k;
		begin
			for (k = 0; k < ms * 32000; k = k + 1) @(posedge clk);
		end
	endtask

	localparam A_CTRL  = 32'h3005_0000;
	localparam A_STAT  = 32'h3005_0004;
	localparam A_KEY   = 32'h3005_0008;
	localparam A_MAP0  = 32'h3005_000c;
	localparam A_MAP1  = 32'h3005_0010;
	localparam A_MAP2  = 32'h3005_0014;
	localparam A_MAP3  = 32'h3005_0018;
	localparam A_DEB   = 32'h3005_001c;
	localparam A_RAW   = 32'h3005_0020;
	localparam A_VER   = 32'h3005_0024;

	reg [31:0] rd;

	initial begin
		clk = 0; rstn = 0;
		psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;
		key_r = 0; key_c = 0; key_on = 0;

		repeat (5) @(negedge clk);
		rstn = 1;
		repeat (2) @(negedge clk);

		// 1) 复位值
		apb_rd(A_VER, rd);  chk("VERSION", rd, 32'h4b42_0001);
		apb_rd(A_CTRL, rd); chk("reset CTRL", rd, 32'h0);
		apb_rd(A_DEB, rd);  chk("default DEBOUNCE", rd, 32'h8);
		apb_rd(A_MAP0, rd); chk("default KEYMAP0", rd, 32'h0302_0100);

		// 2) 无键
		apb_wr(A_CTRL, 32'h0000_0003);   // 使能 + 中断，1 ms 扫描
		wait_ms(3);
		apb_rd(A_KEY, rd);  chk("KEY when no key", rd, 32'h0000_00ff);
		apb_rd(A_STAT, rd);
		chk("STATUS[0] no key", rd & 32'h1, 32'h0);
		chk("irq count still 0", irq_cnt, 0);

		// 3) 按 scan code 5 = row1 col1
		key_r = 2'd1; key_c = 2'd1; key_on = 1;
		wait_ms(12);                      // 8 ms 消抖 + 余量
		apb_rd(A_STAT, rd);
		chk("STATUS[0] new key", (rd >> 0) & 1, 1);
		chk("STATUS[1] pressed", (rd >> 1) & 1, 1);
		chk("STATUS[7:4] key",   (rd >> 4) & 4'hf, 4'h5);
		chk("irq pulse count", irq_cnt, 1);
		apb_rd(A_KEY, rd);  chk("KEY value", rd, 32'h5);
		apb_rd(A_KEY, rd);  chk("KEY empty after read", rd, 32'hff);
		apb_rd(A_STAT, rd); chk("STATUS[0] cleared by KEY read", rd & 1, 32'h0);

		// 4) 按住不放，不应重复上报
		wait_ms(20);
		apb_rd(A_STAT, rd); chk("STATUS[0] still 0 while holding", rd & 1, 32'h0);
		chk("irq count still 1", irq_cnt, 1);

		// 松手后再按同一个键
		key_on = 0;
		wait_ms(12);
		apb_rd(A_STAT, rd); chk("STATUS[1] released", (rd >> 1) & 1, 0);
		key_on = 1;
		wait_ms(12);
		apb_rd(A_KEY, rd);  chk("second press KEY", rd, 32'h5);
		chk("irq count now 2", irq_cnt, 2);
		key_on = 0;
		wait_ms(12);

		// 5) KEYMAP 重映射：扫描码 5 映射成 0xAB
		apb_wr(A_MAP1, 32'h0706_ab04);
		key_r = 2'd1; key_c = 2'd1; key_on = 1;
		wait_ms(12);
		apb_rd(A_KEY, rd);  chk("KEY after remap", rd, 32'h0000_00ab);
		key_on = 0;
		wait_ms(12);

		// 另一个键：row3 col2 → 扫描码 0xE
		key_r = 2'd3; key_c = 2'd2; key_on = 1;
		wait_ms(12);
		apb_rd(A_KEY, rd);  chk("scan code 0xE default map", rd, 32'h0000_000e);
		key_on = 0;
		wait_ms(12);

		// 15 号键: row3 col3 → 扫描码 0xF（2026-11-25 修:
		//   原来用 0xF 当"无键"哨兵, 与 15 号键码冲突, 按了没反应）
		key_r = 2'd3; key_c = 2'd3; key_on = 1;
		wait_ms(12);
		apb_rd(A_KEY, rd);  chk("scan code 0xF (key15)", rd, 32'h0000_000f);
		key_on = 0;
		wait_ms(12);

		// 6) DEBOUNCE = 2，确认变快
		apb_wr(A_DEB, 32'h2);
		key_r = 2'd0; key_c = 2'd3; key_on = 1;
		wait_ms(5);                        // 2 轮消抖足够
		apb_rd(A_KEY, rd);  chk("fast debounce key", rd, 32'h0000_0003);
		key_on = 0;
		wait_ms(6);

		// 7) RAW：无键时行号在 0~3 循环、列全 1
		apb_rd(A_RAW, rd);
		chk("RAW col bits all 1", rd & 32'hf, 32'hf);
		$display("   RAW = 0x%08x (row=%0d)", rd, (rd >> 4) & 4'hf);

		// 关闭使能，检查行线全高
		apb_wr(A_CTRL, 32'h0);
		wait_ms(1);
		chk("rows idle high", {28'b0, kbd_row}, 32'hf);

		if (errors == 0)
			$display("\n==== TB_KBD RESULT: PASS (0 errors) ====\n");
		else
			$display("\n==== TB_KBD RESULT: FAIL (%0d errors) ====\n", errors);
		$finish;
	end

	initial begin
		#200000000;
		$display("\n==== TB_KBD TIMEOUT ====\n");
		$finish;
	end

endmodule
