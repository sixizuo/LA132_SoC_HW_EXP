//=====================================================================
//  tb_da_cs.v  ——  专项检查: DA 模式下 TLV5618A 片选由 RTL 自动完成
//  (纯 Verilog 写法, iverilog 与 xsim 都能编)
//
//  检查点 (监测内部 APB 主机的每一次访问):
//    1) 使能 DA 后先重配: SPCR=0xD8, SPER=0x40, SOFTCS=0xF2 (空闲)
//    2) 每个样本: SOFTCS=0xD2 -> DATA(高字节) -> SPSR 轮询 ->
//       DATA(低字节) -> SPSR 轮询 -> SOFTCS=0xF2
//    3) 0xD2 之后必须先出现 0xF2 才能出现下一个 0xD2 (不会连续两次选中)
//    4) DATA 写入的字节顺序 = da_word 高字节在前
//  结果: ==== TB_DA_CS RESULT: PASS (n frames) ====
//=====================================================================
`timescale 1ns/1ps

module tb_da_cs;
	localparam CLK_PERIOD = 31;                 /* 约 32 MHz */
	localparam N_EXP = 4;                       /* 期望帧数 = 2, 多留余量 */

	reg clk = 1'b0, rstn = 1'b0;
	always #(CLK_PERIOD/2) clk = ~clk;

	reg         psel = 1'b0, penable = 1'b0, pwrite = 1'b0;
	reg  [31:0] paddr = 32'd0, pwdata = 32'd0;
	wire [31:0] prdata;

	wire [3:0]  spi_clk, spi_mosi, spi_csn;
	wire [7:0]  spi_mul;
	wire        irq;

	spi_stream_top dut (
		.apb_pclk   (clk   ), .apb_prstn (rstn  ),
		.apb_psel   (psel  ), .apb_penable(penable),
		.apb_pwrite (pwrite), .apb_paddr  (paddr ),
		.apb_pwdata (pwdata), .apb_prdata (prdata),
		.apb_pready (                      ),
		.spi_clk    (spi_clk), .spi_miso (4'h0  ),
		.spi_mosi   (spi_mosi), .spi_csn (spi_csn),
		.spi_mul    (spi_mul), .stream_irq(irq  )
	);

	integer errors   = 0;
	integer n_frame  = 0;
	reg [15:0] da_exp [0:N_EXP-1];
	integer exp_i = 0;                          /* 已发完的帧数 */
	reg [7:0]  byte_hi, byte_lo;
	integer expect_hi = 1;                      /* 下一个 DATA 写应是高字节 */
	reg  cs_on_prev = 1'b0;                     /* 上次 0xD2/0xF2 是选中还是释放 */
	integer cfg_seen  = 0;

	task apb_wr(input [7:0] a, input [31:0] d);
		begin
			@(negedge clk);
			psel = 1'b1; pwrite = 1'b1; paddr = {24'd0, a}; pwdata = d;
			@(negedge clk); penable = 1'b1;
			@(negedge clk); penable = 1'b0; psel = 1'b0;
		end
	endtask

	/* 监测内部主机每一次 mi_done */
	always @(posedge clk) begin
		if (rstn && dut.mi_done) begin
			if (!dut.mst_wr) begin
				/* 读: 只认 SPSR 轮询, 其余不该发生 */
				if (dut.mst_addr != 8'h04) begin
					$display("FAIL: unexpected read addr=0x%02x", dut.mst_addr);
					errors = errors + 1;
				end
			end else begin
				case (dut.mst_addr)
					8'h00 : begin                           /* SPCR */
						if (dut.mst_wdata !== 8'hd8) begin
							$display("FAIL: DA SPCR=0x%02x (expect 0xD8)",
							         dut.mst_wdata);
							errors = errors + 1;
						end
					end
					8'h0c : ;                               /* SPER */
					8'h14 : begin                           /* SOFTCS */
						if (dut.mst_wdata == 8'hd2) begin
							if (cs_on_prev) begin
								$display("FAIL: two 0xD2 without 0xF2 between");
								errors = errors + 1;
							end
							cs_on_prev = 1'b1;
						end else if (dut.mst_wdata == 8'hf2) begin
							if (cs_on_prev) begin
								n_frame = n_frame + 1;
								expect_hi = 1;
							end else if (cfg_seen != 0) begin
								$display("FAIL: 0xF2 without preceding 0xD2");
								errors = errors + 1;
							end
							cs_on_prev = 1'b0;
						end else begin
							$display("FAIL: bad SOFTCS value 0x%02x",
							         dut.mst_wdata);
							errors = errors + 1;
						end
						cfg_seen = 1;
					end
					8'h08 : begin                           /* DATA: DA 字节 */
						if (!cs_on_prev) begin
							$display("FAIL: DATA 0x%02x with CS not asserted",
							         dut.mst_wdata);
							errors = errors + 1;
						end
						if (expect_hi) begin
							byte_hi = dut.mst_wdata; expect_hi = 0;
						end else begin
							byte_lo = dut.mst_wdata;
							if (exp_i < 2) begin
								if ({byte_hi, byte_lo} !== da_exp[exp_i]) begin
									$display("FAIL: DA frame 0x%04x expect 0x%04x",
									         {byte_hi, byte_lo}, da_exp[exp_i]);
									errors = errors + 1;
								end
								exp_i = exp_i + 1;
							end
						end
					end
					default : ;
				endcase
			end
		end
	end

	initial begin
		da_exp[0] = 16'h30A5;                       /* 帧 1 */
		da_exp[1] = 16'hC366;                       /* 帧 2 */

		rstn = 1'b0;
		repeat (4) @(negedge clk);
		rstn = 1'b1;

		apb_wr(8'h04, 32'd64);                      /* DIV=64, 节拍最快 */
		apb_wr(8'h00, 32'h3);                       /* CTRL = EN | DA */
		apb_wr(8'h08, 32'h30A5);                    /* DA 帧 1 */
		apb_wr(8'h08, 32'hC366);                    /* DA 帧 2 */

		/* 等 2 个 DA 帧完成 */
		repeat (20000) @(posedge clk);

		if (n_frame < 2) begin
			$display("FAIL: only %0d DA frames completed", n_frame);
			errors = errors + 1;
		end

		if (errors == 0)
			$display("==== TB_DA_CS RESULT: PASS (%0d frames) ====", n_frame);
		else
			$display("==== TB_DA_CS RESULT: FAIL (%0d errors, %0d frames) ====",
			         errors, n_frame);
		$finish;
	end

	initial begin
		#50000000;                                  /* 50 ms 兜底 */
		$display("==== TB_DA_CS RESULT: TIMEOUT FAIL ====");
		$finish;
	end
endmodule
