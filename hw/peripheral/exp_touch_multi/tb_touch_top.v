//=====================================================================
//  tb_touch_top.v  ——  实验八 APB 包装层自检激励
//---------------------------------------------------------------------
//  验证对象 : touch_top_multi
//    - APB 寄存器读写与越界钳位（MAXPOINT / INTERVAL / CTRL）
//    - 点记录入 FIFO（跨时钟两相握手）与出栈顺序
//    - 空 FIFO 读回 0xFFFF_FFFF、满/空状态位
//    - 清 FIFO 命令
//    - 中断输出 = irq_en & !empty
//  说明 :
//    I2C 字节级解析已由 tb_touch_dri.v 验证；本 tb 用 force 从 dri 域
//    直接注入 pt_valid / frame_valid，把“解析结果 -> APB 侧”这一段单独
//    隔出来测，避免与 SCL/SDA 时序耦合。
//=====================================================================
`timescale 1ns / 1ps

module tb_touch_top;

	localparam CLK_PERIOD = 31.25;   // 32 MHz APB clock

	reg         pclk, prstn;
	reg         psel, pwrite, penable;
	reg  [31:0] paddr, pwdata;
	wire [31:0] prdata;
	wire        pready;

	wire        touch_scl;
	wire        touch_sda;
	wire        touch_int;
	wire        touch_rst_n;
	wire        touch_irq;

	reg  [15:0] lcd_id = 16'h4384;

	pullup (touch_sda);
	pullup (touch_int);

	touch_top_multi dut (
		.apb_pclk    (pclk      ),
		.apb_prstn   (prstn     ),
		.apb_psel    (psel      ),
		.apb_paddr   (paddr     ),
		.apb_pwrite  (pwrite    ),
		.apb_penable (penable   ),
		.apb_pwdata  (pwdata    ),
		.apb_prdata  (prdata    ),
		.apb_pready  (pready    ),
		.lcd_id      (lcd_id    ),
		.touch_scl   (touch_scl ),
		.touch_sda   (touch_sda ),
		.touch_int   (touch_int ),
		.touch_rst_n (touch_rst_n),
		.touch_irq   (touch_irq )
	);

	always #(CLK_PERIOD/2) pclk = ~pclk;

	// ---------------- APB read/write tasks ----------------
	task apb_wr;
		input [31:0] a, d;
		begin
			@(negedge pclk);
			psel = 1; pwrite = 1; paddr = a; pwdata = d; penable = 0;
			@(negedge pclk);
			penable = 1;
			@(negedge pclk);
			psel = 0; penable = 0; pwrite = 0;
		end
	endtask

	task apb_rd;
		input  [31:0] a;
		output [31:0] d;
		begin
			@(negedge pclk);
			psel = 1; pwrite = 0; paddr = a; penable = 0;
			@(negedge pclk);
			penable = 1;
			#1 d = prdata;               // sample before the completing edge
			@(negedge pclk);
			psel = 0; penable = 0;
		end
	endtask

	// ---------------- checkers ----------------
	integer errors = 0;

	task chk;
		input [255:0] name;
		input [31:0]  got, exp;
		begin
			if (got !== exp) begin
				$display("FAIL %0s : got=0x%08h exp=0x%08h (t=%0t)", name, got, exp, $time);
				errors = errors + 1;
			end else begin
				$display("pass %0s : 0x%08h", name, got);
			end
		end
	endtask

	task chk_irq;
		input [255:0] name;
		input         got, exp;
		begin
			if (got !== exp) begin
				$display("FAIL %0s : got=%b exp=%b (t=%0t)", name, got, exp, $time);
				errors = errors + 1;
			end else begin
				$display("pass %0s : %b", name, got);
			end
		end
	endtask

	// ---------------- injectors (dri domain) ----------------
	reg [4:0] fcnt0;

	task inject_point;
		input [3:0]  id;
		input [13:0] x, y;
		begin
			fcnt0 = dut.fcnt;
			force dut.pt_id    = id;
			force dut.pt_x     = x;
			force dut.pt_y     = y;
			// 在 negedge 施加，跨一个 posedge 后在下一个 negedge 撤销，
			// 保证被测模块恰好采样一次（避免与 posedge 采样竞争）
			@(negedge dut.dri_clk);
			force dut.pt_valid = 1'b1;
			@(negedge dut.dri_clk);
			force dut.pt_valid = 1'b0;
			wait (dut.fcnt === fcnt0 + 5'd1);     // 已跨到 pclk 域入队
			repeat (2) @(negedge pclk);
		end
	endtask

	task inject_frame;
		input [3:0] n;
		begin
			force dut.pt_num      = n;
			@(negedge dut.dri_clk);
			force dut.frame_valid = 1'b1;
			@(negedge dut.dri_clk);
			force dut.frame_valid = 1'b0;
			wait (dut.num_reg === n);
			repeat (2) @(negedge pclk);
		end
	endtask

	reg [31:0] d;

	initial begin
		pclk = 0; prstn = 0;
		psel = 0; pwrite = 0; penable = 0; paddr = 0; pwdata = 0;

		repeat (5) @(negedge pclk);
		prstn = 1;
		repeat (3) @(negedge pclk);

		// ---- 1. version and default values ----
		apb_rd(32'h18, d); chk("VERSION",        d, 32'h5450_0002);
		apb_rd(32'h14, d); chk("MAXPOINT dflt",  d, 32'd5);
		apb_rd(32'h04, d); chk("INTERVAL dflt",  d, 32'd95000);
		apb_rd(32'h00, d); chk("CTRL dflt",      d, 32'd0);

		// ---- 2. clamping ----
		apb_wr(32'h14, 32'd3);  apb_rd(32'h14, d); chk("MAXPOINT=3",     d, 32'd3);
		apb_wr(32'h14, 32'd0);  apb_rd(32'h14, d); chk("MAXPOINT 0->1",  d, 32'd1);
		apb_wr(32'h14, 32'd9);  apb_rd(32'h14, d); chk("MAXPOINT 9->5",  d, 32'd5);
		apb_wr(32'h04, 32'd10); apb_rd(32'h04, d); chk("INTERVAL 10->32",d, 32'd32);

		// ---- 3. enable: multi-point + irq ----
		apb_wr(32'h00, 32'h0000_0007);
		apb_rd(32'h00, d); chk("CTRL=0x7", d, 32'h0000_0007);

		// empty FIFO
		apb_rd(32'h10, d); chk("STATUS empty", d, 32'h0000_0001);
		chk_irq("IRQ low when empty", touch_irq, 1'b0);
		apb_rd(32'h08, d); chk("DATA read when empty", d, 32'hffff_ffff);

		// ---- 4. inject 3 points + frame end ----
		inject_point(4'd0, 14'd100, 14'd200);
		inject_point(4'd1, 14'd700, 14'd50);
		inject_point(4'd2, 14'd400, 14'd240);
		inject_frame(4'd3);

		apb_rd(32'h10, d); chk("STATUS not empty", d, 32'h0000_0100);
		apb_rd(32'h0c, d); chk("NUM=3",            d, 32'd3);
		chk_irq("IRQ high when not empty", touch_irq, 1'b1);

		// ---- 5. pop order and record format {id,x,y} ----
		apb_rd(32'h08, d); chk("record 0", d, {4'd0, 14'd100, 14'd200});
		apb_rd(32'h08, d); chk("record 1", d, {4'd1, 14'd700, 14'd50});
		apb_rd(32'h08, d); chk("record 2", d, {4'd2, 14'd400, 14'd240});

		apb_rd(32'h10, d); chk("STATUS empty again", d, 32'h0000_0101);
		apb_rd(32'h08, d); chk("DATA read after drain", d, 32'hffff_ffff);

		// ---- 6. clear FIFO ----
		inject_point(4'd3, 14'd10, 14'd470);
		inject_point(4'd4, 14'd799, 14'd1);
		apb_rd(32'h10, d); chk("STATUS after 2 points", d, 32'h0000_0100);

		apb_wr(32'h00, 32'h0000_000f);      // bit3 clear FIFO
		apb_wr(32'h00, 32'h0000_0007);
		repeat (5) @(negedge pclk);
		apb_rd(32'h10, d); chk("STATUS after clear", d, 32'h0000_0001);

		// ---- 7. irq disable ----
		apb_wr(32'h00, 32'h0000_0005);      // clear irq_en
		inject_point(4'd0, 14'd1, 14'd2);
		chk_irq("IRQ low after disable", touch_irq, 1'b0);

		release dut.pt_id;
		release dut.pt_x;
		release dut.pt_y;
		release dut.pt_valid;
		release dut.pt_num;
		release dut.frame_valid;

		if (errors == 0)
			$display("\n==== TB_TOUCH_TOP RESULT: PASS (0 errors) ====\n");
		else
			$display("\n==== TB_TOUCH_TOP RESULT: FAIL (%0d errors) ====\n", errors);
		$finish;
	end

	initial begin
		#5000000;
		$display("\n==== TB_TOUCH_TOP TIMEOUT ====\n");
		$finish;
	end

endmodule
