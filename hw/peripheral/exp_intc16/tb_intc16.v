//=====================================================================
//  tb_intc16.v  ——  实验一 16 路中断控制器自检激励
//---------------------------------------------------------------------
//  覆盖 :
//    1) 复位值（EN=0 / POL=0xFFFF / EDGE=0）
//    2) 16 位寄存器的写入与读回（含高位、零扩展）
//    3) 软件强制置位 SET / 清除 CLR，逐位遍历
//    4) 电平模式：POL=1 高有效、POL=0 低有效
//    5) 边沿模式：单次上升沿锁存，CLR 撤销
//    6) intc_irq = |int_out 的相或行为
//    7) 未接源（int_in 恒 0）时 EN 写 1 也不置位
//  运行 : xvlog/xelab/xsim，见 sim/run_xsim.sh
//=====================================================================
`timescale 1ns / 1ps

module tb_intc16;

	localparam CLK_PERIOD = 31.25;   // 32 MHz

	reg         clk;
	reg         rstn;
	reg  [15:0] int_in;

	reg         psel;
	reg         penable;
	reg         pwrite;
	reg  [31:0] paddr;
	reg  [31:0] pwdata;
	wire [31:0] prdata;
	wire        pready;
	wire        irq;

	intc_top16 #(.INT_NUM(16)) dut (
		.apb_pclk    (clk    ),
		.apb_prstn   (rstn   ),
		.apb_psel    (psel   ),
		.apb_paddr   (paddr  ),
		.apb_pwrite  (pwrite ),
		.apb_penable (penable),
		.apb_pwdata  (pwdata ),
		.apb_prdata  (prdata ),
		.apb_pready  (pready ),
		.int_in      (int_in ),
		.intc_irq    (irq    )
	);

	always #(CLK_PERIOD/2) clk = ~clk;

	integer errors = 0;
	integer i;

	task chk;
		input [255:0] name;
		input [31:0]  got;
		input [31:0]  exp;
		begin
			if (got !== exp) begin
				$display("FAIL %0s : got=0x%08x exp=0x%08x  (t=%0t)", name, got, exp, $time);
				errors = errors + 1;
			end else begin
				$display("pass %0s : 0x%08x", name, got);
			end
		end
	endtask

	task apb_wr;
		input [31:0] a;
		input [31:0] d;
		begin
			@(negedge clk);
			psel = 1'b1; penable = 1'b0; pwrite = 1'b1;
			paddr = a; pwdata = d;
			@(negedge clk);
			penable = 1'b1;
			@(negedge clk);
			psel = 1'b0; penable = 1'b0; pwrite = 1'b0;
			@(negedge clk);
		end
	endtask

	task apb_rd;
		input  [31:0] a;
		output [31:0] d;
		begin
			@(negedge clk);
			psel = 1'b1; penable = 1'b0; pwrite = 1'b0;
			paddr = a;
			@(negedge clk);
			penable = 1'b1;
			@(negedge clk);
			d = prdata;
			psel = 1'b0; penable = 1'b0;
			@(negedge clk);
		end
	endtask

	localparam A_EN   = 32'h3002_0000;
	localparam A_POL  = 32'h3002_0004;
	localparam A_EDGE = 32'h3002_0008;
	localparam A_CLR  = 32'h3002_000c;
	localparam A_SET  = 32'h3002_0010;
	localparam A_OUT  = 32'h3002_0014;

	reg [31:0] rd;

	initial begin
		clk = 1'b0; rstn = 1'b0;
		psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;
		int_in = 16'h0000;

		repeat (5) @(negedge clk);
		rstn = 1'b1;
		repeat (2) @(negedge clk);

		// ---- 1) 复位值 ----
		apb_rd(A_EN,  rd); chk("reset EN",   rd, 32'h0000_0000);
		apb_rd(A_POL, rd); chk("reset POL",  rd, 32'h0000_ffff);
		apb_rd(A_EDGE,rd); chk("reset EDGE", rd, 32'h0000_0000);
		apb_rd(A_OUT, rd); chk("reset OUT",  rd, 32'h0000_0000);

		// ---- 2) 16 位寄存器读回 ----
		apb_wr(A_EN,   32'h0000_ffff);
		apb_rd(A_EN,   rd); chk("EN readback",   rd, 32'h0000_ffff);
		apb_wr(A_POL,  32'h0000_5555);
		apb_rd(A_POL,  rd); chk("POL readback",  rd, 32'h0000_5555);
		apb_wr(A_EDGE, 32'h0000_aaaa);
		apb_rd(A_EDGE, rd); chk("EDGE readback", rd, 32'h0000_aaaa);
		// 写全 1 但 int_in=0：寄存器可写，INT_OUT 不应被拉高（电平模式）
		apb_wr(A_POL,  32'h0000_ffff);
		apb_wr(A_EDGE, 32'h0000_0000);
		apb_rd(A_OUT,  rd); chk("OUT after EN=FFFF, int_in=0", rd, 32'h0000_0000);
		chk("irq low", {31'b0, irq}, 32'h0);

		// ---- 3) 软件强制置位 / 清除，逐位遍历 ----
		apb_wr(A_EN, 32'h0000_0000);
		for (i = 0; i < 16; i = i + 1) begin
			apb_wr(A_SET, 32'h1 << i);
			apb_rd(A_OUT, rd);
			chk("SET bit", rd, 32'h1 << i);
			apb_wr(A_CLR, 32'h1 << i);
			apb_rd(A_OUT, rd);
			chk("CLR bit", rd, 32'h0000_0000);
		end

		// ---- 4) 电平模式 ----
		apb_wr(A_EN,   32'h0000_0003);
		apb_wr(A_POL,  32'h0000_0003);   // bit0/1 高有效
		apb_wr(A_EDGE, 32'h0000_0000);
		int_in[0] = 1'b1;
		@(negedge clk);
		apb_rd(A_OUT, rd); chk("level bit0 high", rd, 32'h0000_0001);
		chk("irq high", {31'b0, irq}, 32'h1);
		int_in[1] = 1'b1;
		@(negedge clk);
		apb_rd(A_OUT, rd); chk("level bit1 high", rd, 32'h0000_0003);
		int_in[0] = 1'b0;
		@(negedge clk);
		apb_rd(A_OUT, rd); chk("level bit0 low", rd, 32'h0000_0002);
		int_in[1] = 1'b0;
		@(negedge clk);
		apb_rd(A_OUT, rd); chk("level all low", rd, 32'h0000_0000);

		// 低有效：POL=0 时输入为 0 才有效
		apb_wr(A_POL, 32'h0000_0000);
		@(negedge clk);
		apb_rd(A_OUT, rd); chk("level pol=0, in=0 active", rd, 32'h0000_0003);
		int_in[0] = 1'b1;
		@(negedge clk);
		apb_rd(A_OUT, rd); chk("level pol=0, in=1 inactive", rd, 32'h0000_0002);
		int_in = 16'h0000;
		apb_wr(A_POL, 32'h0000_ffff);

		// ---- 5) 边沿模式 ----
		apb_wr(A_EN,   32'h0000_000f);   // 必须包含 bit2/bit3，否则锁存被 EN 屏蔽
		apb_wr(A_EDGE, 32'h0000_000f);
		apb_wr(A_POL,  32'h0000_000f);
		int_in[2] = 1'b0;
		repeat (2) @(negedge clk);
		apb_rd(A_OUT, rd); chk("edge pre", rd, 32'h0000_0000);
		// 单个上升沿，脉宽 3 拍
		int_in[2] = 1'b1;
		repeat (3) @(negedge clk);
		int_in[2] = 1'b0;
		repeat (3) @(negedge clk);
		apb_rd(A_OUT, rd); chk("edge latch after single rising", rd, 32'h0000_0004);
		// 输入已回落，锁存位应保持
		repeat (5) @(negedge clk);
		apb_rd(A_OUT, rd); chk("edge hold", rd, 32'h0000_0004);
		apb_wr(A_CLR, 32'h0000_0004);
		apb_rd(A_OUT, rd); chk("edge clear", rd, 32'h0000_0000);
		// 低有效边沿：POL=0 时下降沿有效
		apb_wr(A_POL, 32'h0000_0000);
		int_in[3] = 1'b1;
		repeat (3) @(negedge clk);
		int_in[3] = 1'b0;
		repeat (3) @(negedge clk);
		apb_rd(A_OUT, rd); chk("edge falling with pol=0", rd, 32'h0000_0008);

		// ---- 6) 相或输出 ----
		int_in[3] = 1'b0;
		apb_wr(A_CLR, 32'h0000_ffff);
		apb_wr(A_EDGE, 32'h0000_0000);
		apb_wr(A_POL,  32'h0000_ffff);
		apb_wr(A_EN,   32'h0000_8000);
		apb_wr(A_SET,  32'h0000_8000);
		chk("irq from bit15 force", {31'b0, irq}, 32'h1);
		apb_wr(A_CLR,  32'h0000_8000);
		@(negedge clk);
		chk("irq released", {31'b0, irq}, 32'h0);

		// ---- 7) 强制位与使能的关系 ----
		// SET 强制位在原版 one_int_gen 里就是 (int_en & level) | int_force，
		// 即强制置位不受 EN 约束，这里按原版行为校验。
		apb_wr(A_EN,  32'h0000_0000);
		apb_wr(A_SET, 32'h0000_0010);
		apb_rd(A_OUT, rd); chk("SET bypasses EN (原版行为)", rd, 32'h0000_0010);
		apb_wr(A_CLR, 32'h0000_0010);
		apb_rd(A_OUT, rd); chk("CLR after SET", rd, 32'h0000_0000);
		// 电平模式的源在 EN=0 时必须被屏蔽（强制位已清）
		apb_wr(A_EDGE, 32'h0000_0000);
		apb_wr(A_POL,  32'h0000_ffff);
		int_in[4] = 1'b1;
		@(negedge clk);
		apb_rd(A_OUT, rd); chk("level blocked by EN=0", rd, 32'h0000_0000);
		apb_wr(A_EN, 32'h0000_0010);
		apb_rd(A_OUT, rd); chk("level visible when EN=1", rd, 32'h0000_0010);

		if (errors == 0)
			$display("\n==== TB_INT16 RESULT: PASS (0 errors) ====\n");
		else
			$display("\n==== TB_INT16 RESULT: FAIL (%0d errors) ====\n", errors);

		$finish;
	end

	initial begin
		#200000;
		$display("\n==== TB_INT16 TIMEOUT ====\n");
		$finish;
	end

endmodule
