//=====================================================================
//  tb_spi_stream.v  ——  实验九 流式 SPI 控制器自检激励
//---------------------------------------------------------------------
//  验证对象 : spi_stream_top（内部含原 spi_top）
//  做法 :
//    · APB 侧按寄存器语义读写
//    · SPI 侧挂一个 ADC128S102 行为模型：CPOL=1/CPHA=1，主机在 sck
//      上升沿采样 MISO，模型在 sck 下降沿更新 MISO 并采集 MOSI，
//      每 16 bit 一帧，先回高字节再回低字节，内容为递增的采样序号
//  覆盖 :
//    1) 版本号、DIV 钳位到 64、CH 读写
//    2) AD 连续采样：DATA 依次读出 0,1,2,…，CNT 与实际条数一致
//    3) RX 半满中断（32 条）与 FIFO_LVL
//    4) 回环模式：写 DATA 直接出现在 RX FIFO
//    5) 清空 CNT
//=====================================================================
`timescale 1ns / 1ps

module tb_spi_stream;

	localparam CLK_PERIOD = 31.25;    // 32 MHz

	reg         pclk, prstn;
	reg         psel, pwrite, penable;
	reg  [31:0] paddr, pwdata;
	wire [31:0] prdata;
	wire        pready;

	wire [3:0]  spi_clk;
	wire [3:0]  spi_mosi;
	wire [3:0]  spi_csn;
	wire [7:0]  spi_mul;
	reg  [3:0]  spi_miso;
	wire        stream_irq;

	spi_stream_top dut (
		.apb_pclk    (pclk       ),
		.apb_prstn   (prstn      ),
		.apb_psel    (psel       ),
		.apb_paddr   (paddr      ),
		.apb_pwrite  (pwrite     ),
		.apb_penable (penable    ),
		.apb_pwdata  (pwdata     ),
		.apb_prdata  (prdata     ),
		.apb_pready  (pready     ),
		.spi_clk     (spi_clk    ),
		.spi_miso    (spi_miso   ),
		.spi_mosi    (spi_mosi   ),
		.spi_csn     (spi_csn    ),
		.spi_mul     (spi_mul    ),
		.stream_irq  (stream_irq )
	);

	always #(CLK_PERIOD/2) pclk = ~pclk;

	// ---------------- ADC128S102 行为模型 ----------------
	// 每个 16 bit 帧返回 {4'h0, gen}，gen 每帧加 1
	reg  [11:0] gen;
	reg  [15:0] adc_word;
	reg  [7:0]  sh;
	reg  [2:0]  bitn;
	reg         ph;            // 0=高字节 1=低字节
	reg         miso_r;

	initial begin
		gen = 12'd0;
		adc_word = 16'd0;
		sh = 8'h00;
		bitn = 3'd0;
		ph = 1'b0;
		miso_r = 1'b0;
		spi_miso = 4'hf;        // 空闲高
	end

	// 芯片选择有效（spi_csn[0]==0）才开始工作
	wire cs_act = (spi_csn[0] === 1'b0);

	always @(negedge spi_clk[0]) if (cs_act) begin
		miso_r   <= sh[7];
		spi_miso <= {4{sh[7]}};   // miso_i = &spi_miso，4 位必须同值
		sh       <= {sh[6:0], 1'b0};
		bitn     <= bitn + 3'd1;
		if (bitn == 3'd7) begin
			bitn <= 3'd0;
			if (!ph) begin
				ph <= 1'b1;
				sh <= adc_word[7:0];        // 装载低字节
			end else begin
				ph <= 1'b0;
				gen      <= gen + 12'd1;
				adc_word <= {4'h0, gen + 12'd1};
				sh       <= {4'h0, gen + 12'd1} >> 8;   // 下一帧高字节
			end
		end
	end

	// ---------------- APB 任务 ----------------
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
			#1 d = prdata;
			@(negedge pclk);
			psel = 0; penable = 0;
		end
	endtask

	// ---------------- 检查 ----------------
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

	reg [31:0] d;
	integer i;
	reg [31:0] v;

	initial begin
		pclk = 0; prstn = 0;
		psel = 0; pwrite = 0; penable = 0; paddr = 0; pwdata = 0;

		repeat (5) @(negedge pclk);
		prstn = 1;
		repeat (3) @(negedge pclk);

		// ---- 1. 版本与钳位 ----
		apb_rd(32'h1c, d); chk("VERSION", d, 32'h5350_0003);
		apb_wr(32'h04, 32'd8);  apb_rd(32'h04, d); chk("DIV 8->64", d, 32'd64);
		apb_wr(32'h14, 32'd5);  apb_rd(32'h14, d); chk("CH=5",      d, 32'd5);
		apb_rd(32'h00, d); chk("CTRL dflt", d, 32'd0);

		// ---- 2. 使能 AD 采样 ----
		apb_wr(32'h04, 32'd64);            // fs = 32M/64 = 500 kHz（仿真加速）
		apb_wr(32'h00, 32'h0000_0001);     // en=1, AD 模式
		// 等够 40 个样本
		wait (dut.rx_cnt >= 7'd40);
		$display("---- rx_cnt reached %0d (t=%0t)", dut.rx_cnt, $time);

		apb_rd(32'h18, d); chk("FIFO_LVL RX=40", d & 32'h0000_00ff, 32'd40);
		apb_rd(32'h10, d); chk("CNT>=40", (d >= 32'd40) ? 32'd1 : 32'd0, 32'd1);
		apb_rd(32'h0c, d); chk("STATUS rx_half", d & 32'h0000_0003, 32'h0000_0003);

		// 关采样，避免继续进 FIFO 干扰比对
		apb_wr(32'h00, 32'h0000_0000);
		repeat (20) @(negedge pclk);

		// ---- 3. 依次弹出并校验递增序列 ----
		apb_rd(32'h08, d); chk("sample 0", d, 32'd0);
		apb_rd(32'h08, d); chk("sample 1", d, 32'd1);
		apb_rd(32'h08, d); chk("sample 2", d, 32'd2);
		for (i = 3; i < 40; i = i + 1) begin
			apb_rd(32'h08, d);
			if (d !== i[31:0]) begin
				$display("FAIL sample %0d : got=%0d (t=%0t)", i, d, $time);
				errors = errors + 1;
			end
		end
		apb_rd(32'h08, d); chk("read empty FIFO", d, 32'hffff_ffff);
		apb_rd(32'h0c, d); chk("STATUS empty", d & 32'h0000_0001, 32'd0);

		// ---- 4. 清 CNT ----
		apb_wr(32'h10, 32'd1);
		apb_rd(32'h10, d); chk("CNT clear", d, 32'd0);

		// ---- 5. 回环：写 DATA 直接进 RX FIFO ----
		apb_wr(32'h00, 32'h0000_0009);     // en=1 + loop=1
		apb_wr(32'h08, 32'h0000_0123);
		apb_wr(32'h08, 32'h0000_0456);
		repeat (5) @(negedge pclk);
		apb_rd(32'h18, d); chk("loopback RX=2", d & 32'h0000_00ff, 32'd2);
		apb_rd(32'h08, d); chk("loopback data 0", d, 32'h0000_0123);
		apb_rd(32'h08, d); chk("loopback data 1", d, 32'h0000_0456);

		if (errors == 0)
			$display("\n==== TB_SPI_STREAM RESULT: PASS (0 errors) ====\n");
		else
			$display("\n==== TB_SPI_STREAM RESULT: FAIL (%0d errors) ====\n", errors);
		$finish;
	end

	initial begin
		#20000000;
		$display("\n==== TB_SPI_STREAM TIMEOUT (rx_cnt=%0d st=%0d) ====\n", dut.rx_cnt, dut.st);
		$finish;
	end

endmodule
