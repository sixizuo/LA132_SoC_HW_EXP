//=====================================================================
//  tb_touch_dri.v  ——  实验八 多点解析自检激励
//---------------------------------------------------------------------
//  要点 : touch_dri_multi 在真实工程里由 iic_dri_m 的 dri_clk 驱动，
//         CLK_FREQ/IIC_FREQ = 32M/250k 时 dri_clk = 1 MHz，
//         因此一个时钟 = 1 us，cnt_1us_cnt 直接就是微秒计数，
//         iic_done / once_done 都是“单周期脉冲”，iic_data 与
//         once_done 同拍有效。本 tb 严格按这一时序建模。
//  做法 : 测试平台直接扮演 iic_dri_m，按 GT911 的寄存器语义应答
//           读 0x814E → 返回 0x80|N（N 点就绪）
//           读 0x8150 → 连续吐出 N×8 字节坐标（x低/x高/y低/y高/尺寸/id/保留）
//           写 0x814E → 应答，清状态
//         把“I2C 比特时序”和“多点解析逻辑”解耦，定位问题更快。
//  覆盖 :
//    1) 3 点：3 个 pt_valid，id/x/y 与注入一致，pt_num=3
//    2) 5 点：全量解析
//    3) maxpoint=2 时 4 点被钳位到 2 点
//=====================================================================
`timescale 1ns / 1ps

module tb_touch_dri;

	localparam CLK_PERIOD = 1000;    // 1 MHz，等价于 iic_dri_m 的 dri_clk

	reg         clk, rstn;

	// 驱动 <-> 测试平台 的 iic 字节接口
	wire [6:0]  slave_addr;
	wire        iic_exec, iic_rh_wl, bit_ctrl;
	wire [15:0] iic_addr;
	wire [7:0]  iic_data_w;
	wire [7:0]  reg_num;
	reg  [7:0]  iic_data;
	reg         iic_done, once_done, iic_ack;

	// 驱动输出
	wire [3:0]  pt_id, pt_num;
	wire [13:0] pt_x, pt_y;
	wire        pt_valid, frame_valid;
	wire        touch_rst_n, touch_int_dir, touch_int_out;

	reg  [3:0]  maxpoint;
	reg  [31:0] interval;

	touch_dri_multi #(.WIDTH(8), .INIT_RST(20), .INIT_DLY(60)) dut (
		.clk           (clk          ),
		.rst_n         (rstn         ),
		.slave_addr    (slave_addr   ),
		.iic_exec      (iic_exec     ),
		.iic_rh_wl     (iic_rh_wl    ),
		.iic_addr      (iic_addr     ),
		.iic_data_w    (iic_data_w   ),
		.bit_ctrl      (bit_ctrl     ),
		.reg_num       (reg_num      ),
		.iic_data      (iic_data     ),
		.iic_ack       (iic_ack      ),
		.iic_done      (iic_done     ),
		.once_done     (once_done    ),
		.lcd_id        (16'h4384     ),
		.maxpoint      (maxpoint     ),
		.interval      (interval     ),
		.touch_rst_n   (touch_rst_n  ),
		.touch_int_in  (1'b1         ),
		.touch_int_dir (touch_int_dir),
		.touch_int_out (touch_int_out),
		.pt_id         (pt_id        ),
		.pt_x          (pt_x         ),
		.pt_y          (pt_y         ),
		.pt_valid      (pt_valid     ),
		.pt_num        (pt_num       ),
		.frame_valid   (frame_valid  )
	);

	always #(CLK_PERIOD/2) clk = ~clk;

	// ---------------- 注入用坐标表 ----------------
	reg [3:0]  inj_n;              // 本帧点数
	reg [13:0] inj_x [0:4];
	reg [13:0] inj_y [0:4];
	reg [3:0]  inj_id[0:4];

	// ---------------- 行为级 I2C 响应器 ----------------
	// 4 个相位：S_IDLE 等 iic_exec / S_DATA 给字节+once_done /
	//          S_HOLD 撤 once_done / S_DONE 给 iic_done
	localparam P_IDLE = 2'd0;
	localparam P_DATA = 2'd1;
	localparam P_HOLD = 2'd2;
	localparam P_DONE = 2'd3;

	reg [1:0]  ph;
	reg [5:0]  bidx;      // 字节序号
	reg [5:0]  bnum;      // 本次事务字节数
	reg        rh_wl_r;
	reg [15:0] addr_r;

	// 取第 k 个字节（按寄存器语义）
	function [7:0] byte_of;
		input [5:0]  k;
		input [15:0] a;
		reg   [2:0]  pos;
		reg   [2:0]  pi;
		begin
			if (a == 16'h814e) begin
				byte_of = (inj_n == 4'd0) ? 8'h00 : (8'h80 | {4'd0, inj_n});
			end else if (a == 16'h8150) begin
				pos = k[2:0];
				pi  = k[5:3];
				case (pos)
					3'd0: byte_of = inj_x[pi][7:0];
					3'd1: byte_of = {2'b00, inj_x[pi][13:8]};
					3'd2: byte_of = inj_y[pi][7:0];
					3'd3: byte_of = {2'b00, inj_y[pi][13:8]};
					3'd4: byte_of = 8'h10;                  // 尺寸低
					3'd5: byte_of = 8'h00;                  // 尺寸高
					3'd6: byte_of = {4'd0, inj_id[pi]};
					default: byte_of = 8'h00;               // 保留
				endcase
			end else begin
				byte_of = 8'h00;
			end
		end
	endfunction

	always @(posedge clk) begin
		if (!rstn) begin
			ph        <= P_IDLE;
			bidx      <= 6'd0;
			bnum      <= 6'd0;
			rh_wl_r   <= 1'b1;
			addr_r    <= 16'd0;
			iic_done  <= 1'b0;
			once_done <= 1'b0;
			iic_ack   <= 1'b1;
			iic_data  <= 8'h00;
		end else begin
			iic_done  <= 1'b0;
			once_done <= 1'b0;
			case (ph)
				P_IDLE : begin
					if (iic_exec) begin
						ph      <= P_DATA;
						bidx    <= 6'd0;
						bnum    <= (reg_num == 8'd0) ? 6'd1 : reg_num[5:0];
						rh_wl_r <= iic_rh_wl;
						addr_r  <= iic_addr;
						iic_ack <= 1'b0;             // 从设备应答
					end
				end
				P_DATA : begin
					if (!rh_wl_r) begin
						ph <= P_DONE;                // 写操作：不发数据
					end else begin
						iic_data  <= byte_of(bidx, addr_r);
						once_done <= 1'b1;
						ph        <= P_HOLD;
					end
				end
				P_HOLD : begin
					if (bidx + 6'd1 >= bnum) ph <= P_DONE;
					else begin
						bidx <= bidx + 6'd1;
						ph   <= P_DATA;
					end
				end
				P_DONE : begin
					iic_done <= 1'b1;
					ph       <= P_IDLE;
				end
				default : ph <= P_IDLE;
			endcase
		end
	end

	// ---------------- 检查 ----------------
	integer errors = 0;
	integer got_pts = 0;
	integer i;

	task chk;
		input [255:0] name;
		input [31:0]  got, exp;
		begin
			if (got !== exp) begin
				$display("FAIL %0s : got=%0d exp=%0d (t=%0t)", name, got, exp, $time);
				errors = errors + 1;
			end else begin
				$display("pass %0s : %0d (t=%0t)", name, got, $time);
			end
		end
	endtask

	// 收集 pt_valid 并按注入表比对
	integer order_idx = 0;
	always @(posedge clk) begin
		if (pt_valid) begin
			if (inj_x[order_idx] !== pt_x || inj_y[order_idx] !== pt_y
			    || inj_id[order_idx] !== pt_id) begin
				$display("FAIL point %0d : id=%0d x=%0d y=%0d exp id=%0d x=%0d y=%0d (t=%0t)",
				         got_pts, pt_id, pt_x, pt_y,
				         inj_id[order_idx], inj_x[order_idx], inj_y[order_idx], $time);
				errors = errors + 1;
			end else begin
				$display("pass point %0d : id=%0d x=%0d y=%0d (t=%0t)",
				         got_pts, pt_id, pt_x, pt_y, $time);
			end
			got_pts   = got_pts + 1;
			order_idx = order_idx + 1;
		end
		if (frame_valid) begin
			$display("---- frame end : %0d points, pt_num=%0d (t=%0t)",
			         order_idx, pt_num, $time);
			order_idx = 0;
		end
	end

	integer frame_cnt = 0;
	always @(posedge clk) if (frame_valid) frame_cnt = frame_cnt + 1;

	// 调试 : vvp +DBG 时打印状态跳转（不影响正式结果）
	reg [3:0] d_cur, d_flow;
	reg [5:0] d_bc;
	initial begin d_cur = 4'hf; d_flow = 4'hf; d_bc = 6'h3f; end
	always @(posedge clk) if ($test$plusargs("DBG")) begin
		if (dut.cur_status !== d_cur || dut.flow_cnt !== d_flow || dut.byte_cnt !== d_bc) begin
			$display("[%0t] cur=%0d flow=%0d bc=%0d | exec=%b rd=%b addr=%h rn=%0d data=%h | done=%b once=%b ack=%b pt_num=%0d",
				$time, dut.cur_status, dut.flow_cnt, dut.byte_cnt,
				iic_exec, iic_rh_wl, iic_addr, reg_num, iic_data,
				iic_done, once_done, iic_ack, pt_num);
			d_cur = dut.cur_status; d_flow = dut.flow_cnt; d_bc = dut.byte_cnt;
		end
	end

	initial begin
		clk = 0; rstn = 0;
		iic_data = 8'h00; iic_done = 0; once_done = 0; iic_ack = 1'b1;
		maxpoint = 4'd5;
		interval = 32'd320;          // 320/32 = 10 us 采样间隔
		inj_n = 0;

		inj_id[0]=0; inj_x[0]=100;  inj_y[0]=200;
		inj_id[1]=1; inj_x[1]=700;  inj_y[1]=50;
		inj_id[2]=2; inj_x[2]=400;  inj_y[2]=240;
		inj_id[3]=3; inj_x[3]=10;   inj_y[3]=470;
		inj_id[4]=4; inj_x[4]=799;  inj_y[4]=1;

		repeat (5) @(negedge clk);
		rstn = 1;

		// 等待初始化（INIT_RST + INIT_DLY = 60 us）
		repeat (120) @(negedge clk);

		// 第 1 帧：3 点
		inj_n = 4'd3;
		wait (frame_valid === 1'b1);
		repeat (5) @(negedge clk);
		chk("frame1 points", got_pts, 3);
		chk("frame1 pt_num", {28'd0, pt_num}, 3);

		// 第 2 帧：5 点
		inj_n = 4'd5;
		wait (frame_valid === 1'b1);
		repeat (5) @(negedge clk);
		chk("frame2 points total", got_pts, 8);
		chk("frame2 pt_num", {28'd0, pt_num}, 5);

		// 第 3 帧：maxpoint=2，4 点被钳位
		maxpoint = 4'd2;
		inj_n = 4'd4;
		wait (frame_valid === 1'b1);
		repeat (5) @(negedge clk);
		chk("frame3 points total", got_pts, 10);
		chk("frame3 pt_num clamped", {28'd0, pt_num}, 2);

		if (errors == 0)
			$display("\n==== TB_TOUCH_DRI RESULT: PASS (0 errors, %0d frames) ====\n", frame_cnt);
		else
			$display("\n==== TB_TOUCH_DRI RESULT: FAIL (%0d errors) ====\n", errors);
		$finish;
	end

	initial begin
		#20000000;                    // 20 ms 仿真上限（足够 3 帧）
		$display("\n==== TB_TOUCH_DRI TIMEOUT (got_pts=%0d, frames=%0d) ====", got_pts, frame_cnt);
		$finish;
	end

endmodule
