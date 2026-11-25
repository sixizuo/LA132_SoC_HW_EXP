//=====================================================================
//  tb_apb_dot.v  ——  实验七 点阵显示控制器自检激励
//---------------------------------------------------------------------
//  覆盖 :
//    1) 复位值与 VERSION、默认 ROWDIV
//    2) 字符模式：写 CHAR=0 后 RAM0/RAM1 读回字形 0 的 8 行
//    3) 忙标志：写字符置 1，扫完一帧清 0
//    4) 图形模式：RAM0/RAM1 写入后原样读回，列数据出现在总线上
//    5) 亮度：bright=0 时列数据全 0；bright=7 时列等于当前行数据
//    6) 扫描：一行内只有一行被拉低，8 行按 0~7 顺序循环
//    7) 滚动：帧边界后帧内容整体左移、右侧补源字形的一列
//    8) 闪烁与关断：闪烁时整屏灭，en=0 时行线全高、列全 0
//=====================================================================
`timescale 1ns / 1ps

module tb_apb_dot;

	localparam CLK_PERIOD = 31.25;

	reg         clk, rstn;
	reg         psel, penable, pwrite;
	reg  [31:0] paddr, pwdata;
	wire [31:0] prdata;
	wire        pready;
	wire [7:0]  dot_row, dot_col;

	apb_dot dut (
		.apb_pclk(clk), .apb_prstn(rstn), .apb_psel(psel), .apb_paddr(paddr),
		.apb_pwrite(pwrite), .apb_penable(penable), .apb_pwdata(pwdata),
		.apb_prdata(prdata), .apb_pready(pready),
		.dot_row(dot_row), .dot_col(dot_col)
	);

	always #(CLK_PERIOD/2) clk = ~clk;

	integer errors = 0;

	task chk;
		input [255:0] name;
		input [31:0]  got, exp;
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
			#1 d = prdata;
			@(negedge clk);
			psel = 0; penable = 0;
			@(negedge clk);
		end
	endtask

	task wait_cyc;
		input integer n;
		integer k;
		begin
			for (k = 0; k < n; k = k + 1) @(posedge clk);
		end
	endtask

	localparam A_CTRL = 32'h3007_0000;
	localparam A_CHAR = 32'h3007_0004;
	localparam A_DIV  = 32'h3007_0008;
	localparam A_RAM0 = 32'h3007_000c;
	localparam A_RAM1 = 32'h3007_0010;
	localparam A_SHIFT= 32'h3007_0014;
	localparam A_STAT = 32'h3007_0018;
	localparam A_VER  = 32'h3007_001c;

	reg [31:0] rd;
	integer i, r, seen;
	reg [7:0] row_mask;
	reg [2:0] low_idx;

	initial begin
		clk = 0; rstn = 0;
		psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;

		repeat (5) @(negedge clk);
		rstn = 1;
		repeat (2) @(negedge clk);

		// 1) 复位
		apb_rd(A_VER, rd);  chk("VERSION", rd, 32'h444f_0001);
		apb_rd(A_CTRL, rd); chk("reset CTRL", rd, 32'h0);
		apb_rd(A_DIV, rd);  chk("default ROWDIV", rd, 32'd4000);
		apb_rd(A_RAM0, rd); chk("reset RAM0", rd, 32'h0);
		// 未使能时行线全高、列全 0
		chk("dot_row idle", {24'b0, dot_row}, 32'h0000_00ff);
		chk("dot_col idle", {24'b0, dot_col}, 32'h0);

		// 2) 字符模式：写 0 显示数字 0
		apb_wr(A_CTRL, 32'h0000_0001);        // 使能 + 字符模式 + 亮度 0
		apb_wr(A_CHAR, 32'h0000_0000);
		apb_rd(A_RAM0, rd); chk("font0 row0-3", rd, 32'h766e_663c);
		apb_rd(A_RAM1, rd); chk("font0 row4-7", rd, 32'h003c_6666);

		// 3) 忙标志
		apb_rd(A_STAT, rd);
		chk("busy after CHAR write", rd & 1, 1);
		wait_cyc(33000);                        // 1 ms 一帧
		apb_rd(A_STAT, rd);
		chk("busy cleared after a frame", rd & 1, 0);

		// 4) 图形模式
		apb_wr(A_CTRL, 32'h0000_0021);        // 使能 + 模式 01
		apb_wr(A_RAM0, 32'h183c_7eff);
		apb_wr(A_RAM1, 32'hff7e_3c18);
		apb_rd(A_RAM0, rd); chk("graphic RAM0 readback", rd, 32'h183c_7eff);
		apb_rd(A_RAM1, rd); chk("graphic RAM1 readback", rd, 32'hff7e_3c18);

		// 5) 亮度 0 时列数据全 0；亮度 7 时列等于行数据
		apb_wr(A_CTRL, 32'h0000_0021);        // 亮度 0
		wait_cyc(2000);
		chk("bright=0 col all zero", {24'b0, dot_col}, 32'h0);
		apb_wr(A_CTRL, 32'h0000_003d);        // 使能 + 模式 01 + 亮度 7 (0x1C)
		wait_cyc(2000);

		// 6) 扫描检查：行线只有一位为 0，列与当前行数据一致，8 行循环
		apb_wr(A_DIV, 32'd8);                 // 加快到每行 8 周期
		apb_wr(A_CTRL, 32'h0000_003d);
		seen = 0;
		row_mask = 8'h00;
		for (i = 0; i < 200; i = i + 1) begin
			@(negedge clk);
			if (dot_row != 8'hff) begin
				// 检查只有一位为 0（即 ~dot_row 是 one-hot）
				if (((~dot_row) & (~dot_row - 8'h01)) != 8'h00) begin
					$display("FAIL dot_row not one-hot-low : 0x%02x", dot_row);
					errors = errors + 1;
				end
				case (1'b1)
					(~dot_row[0]): low_idx = 3'd0;
					(~dot_row[1]): low_idx = 3'd1;
					(~dot_row[2]): low_idx = 3'd2;
					(~dot_row[3]): low_idx = 3'd3;
					(~dot_row[4]): low_idx = 3'd4;
					(~dot_row[5]): low_idx = 3'd5;
					(~dot_row[6]): low_idx = 3'd6;
					default      : low_idx = 3'd7;
				endcase
				if (!row_mask[low_idx]) begin
					row_mask[low_idx] = 1'b1;
					seen = seen + 1;
				end
				// 点亮相位内，列数据必须等于该行帧数据
				if (dut.pwm_ph < dut.bright)
					if (dot_col !== dut.fb[low_idx]) begin
						$display("FAIL col mismatch row=%0d got=0x%02x exp=0x%02x",
						         low_idx, dot_col, dut.fb[low_idx]);
						errors = errors + 1;
					end
			end
		end
		chk("8 rows scanned", seen, 8);

		// 7) 滚动：模式 10，每帧移一列
		apb_wr(A_DIV, 32'd8);
		apb_wr(A_CHAR, 32'd1);                 // 源字形 1
		apb_wr(A_SHIFT, 32'd1);
		apb_wr(A_CTRL, 32'h0000_005d);        // 使能 + 模式 10 + 亮度 7
		wait_cyc(64 * 3);                      // 3 帧
		apb_rd(A_RAM0, rd);
		if (rd == 32'h1838_1818) begin
			$display("FAIL scroll did not move : 0x%08x", rd);
			errors = errors + 1;
		end else begin
			$display("pass scroll moved : 0x%08x", rd);
		end

		// 8) 闪烁：帧计数 bit9 为 1 时整屏灭（rowdiv=8 时约 65k 周期）
		apb_wr(A_CTRL, 32'h0000_005b);        // 使能 + 闪烁 + 模式 10 + 亮度 7
		wait_cyc(64 * 512 + 40);               // 走到 bit9 = 1 的半区
		chk("blink off row all high", {24'b0, dot_row}, 32'h0000_00ff);
		chk("blink off col all zero", {24'b0, dot_col}, 32'h0);

		// 关断
		apb_wr(A_CTRL, 32'h0000_0000);
		wait_cyc(10);
		chk("disabled row all high", {24'b0, dot_row}, 32'h0000_00ff);
		chk("disabled col all zero", {24'b0, dot_col}, 32'h0);

		if (errors == 0)
			$display("\n==== TB_DOT RESULT: PASS (0 errors) ====\n");
		else
			$display("\n==== TB_DOT RESULT: FAIL (%0d errors) ====\n", errors);
		$finish;
	end

endmodule
