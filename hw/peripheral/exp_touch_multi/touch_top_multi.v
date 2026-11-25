//=====================================================================
//  touch_top_multi.v  ——  实验八：多点触摸坐标采集（APB 从设备）
//---------------------------------------------------------------------
//  结构 :
//    iic_dri_m（I2C 主机）+ touch_dri_multi（GT911 多点解析）
//    + 16×32 本地环形 FIFO（分布式 RAM）+ req/ack 跨时钟握手
//  地址 : APB 编号 6，基址 0x3006_0000
//  寄存器 :
//    0x00 CTRL     RW bit0 使能 / bit1 中断使能 / bit2 多点模式 / bit3 清 FIFO
//    0x04 INTERVAL RW 采样间隔，单位 32 MHz 周期，默认 95000（约 3 ms）
//    0x08 DATA     R  读一条记录并弹出；空时返回 0xFFFF_FFFF
//    0x0C NUM      R  当前帧点数 0~5
//    0x10 STATUS   R  bit0 空 / bit1 满 / bit8 帧有效
//    0x14 MAXPOINT RW 最大上报点数，默认 5，可写 1~5
//    0x18 VERSION  R  固定 0x5450_0002 ("TP")
//  记录格式 :
//    多点模式 CTRL[2]=1 : {id[3:0], x[13:0], y[13:0]}
//    单点模式 CTRL[2]=0 : {x[15:0], y[15:0]}（与原单点控制器兼容，id 丢弃）
//  跨时钟 :
//    dri_clk 与 apb_pclk 同源但频率不同，点数据用“请求/应答”电平握手搬移，
//    数据在请求有效期间保持不变，避免直接采样异步总线。
//=====================================================================
module touch_top_multi (
	input  wire        apb_pclk   ,
	input  wire        apb_prstn  ,
	input  wire        apb_psel   ,
	input  wire [31:0] apb_paddr  ,
	input  wire        apb_pwrite ,
	input  wire        apb_penable,
	input  wire [31:0] apb_pwdata ,
	output wire [31:0] apb_prdata ,
	output wire        apb_pready ,

	input  wire [15:0] lcd_id     ,

	output wire        touch_scl  ,
	inout  wire        touch_sda  ,
	inout  wire        touch_int  ,
	output wire        touch_rst_n,

	output wire        touch_irq
);

	localparam [7:0] R_CTRL     = 8'h00;
	localparam [7:0] R_INTERVAL = 8'h04;
	localparam [7:0] R_DATA     = 8'h08;
	localparam [7:0] R_NUM      = 8'h0c;
	localparam [7:0] R_STATUS   = 8'h10;
	localparam [7:0] R_MAXPOINT = 8'h14;
	localparam [7:0] R_VERSION  = 8'h18;

	// ---------------- APB 寄存器 ----------------
	reg  [31:0] ctrl;
	reg  [31:0] interval;
	reg  [31:0] maxpoint;
	reg  [31:0] prdata;

	wire wr, rd;
	wire work_en;
	wire irq_en;
	wire multi_en;
	wire clr_fifo;

	assign wr = apb_psel &  apb_pwrite & apb_penable;
	assign rd = apb_psel & !apb_pwrite & apb_penable;
	assign apb_pready = apb_penable;

	assign work_en  = ctrl[0];
	assign irq_en   = ctrl[1];
	assign multi_en = ctrl[2];
	assign clr_fifo = ctrl[3];

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			ctrl     <= 32'h0;
			interval <= 32'd95000;
			maxpoint <= 32'd5;
		end else if (wr) begin
			case (apb_paddr[7:0])
				R_CTRL     : ctrl     <= {28'd0, apb_pwdata[3:0]};
				R_INTERVAL : interval <= (apb_pwdata < 32'd32) ? 32'd32 : apb_pwdata;
				R_MAXPOINT : maxpoint <= (apb_pwdata == 32'd0) ? 32'd1 :
				                         (apb_pwdata > 32'd5) ? 32'd5 : apb_pwdata;
				default : ;
			endcase
		end
	end

	// ---------------- 触摸驱动 ----------------
	wire        touch_int_dir, touch_int_in, touch_int_out;
	wire        touch_sda_dir, touch_sda_in, touch_sda_out;

	wire [6:0]  slave_addr;
	wire        iic_exec, iic_rh_wl, bit_ctrl;
	wire [15:0] iic_addr;
	wire [7:0]  iic_data_w;
	wire [7:0]  reg_num;
	wire [7:0]  iic_data;
	wire        iic_done, once_done, iic_ack;
	wire        dri_clk;

	wire [3:0]  pt_id, pt_num;
	wire [13:0] pt_x, pt_y;
	wire        pt_valid, frame_valid;

	assign touch_sda = touch_sda_dir ? touch_sda_out : 1'bz;
	assign touch_sda_in = touch_sda;
	assign touch_int = touch_int_dir ? touch_int_out : 1'bz;
	assign touch_int_in = touch_int;

	iic_dri_m #(
		.CLK_FREQ (32_000_000),
		.IIC_FREQ (250_000   ),
		.WIDTH    (8         )
	) u_iic (
		.clk        (apb_pclk    ),
		.rst_n      (apb_prstn & work_en),
		.slave_addr (slave_addr  ),
		.iic_exec   (iic_exec    ),
		.iic_rh_wl  (iic_rh_wl   ),
		.iic_addr   (iic_addr    ),
		.iic_data_w (iic_data_w  ),
		.bit_ctrl   (bit_ctrl    ),
		.reg_num    (reg_num     ),
		.iic_data   (iic_data    ),
		.iic_done   (iic_done    ),
		.once_done  (once_done   ),
		.scl        (touch_scl   ),
		.sda_in     (touch_sda_in),
		.sda_out    (touch_sda_out),
		.sda_dir    (touch_sda_dir),
		.ack        (iic_ack     ),
		.dri_clk    (dri_clk     )
	);

	touch_dri_multi #(
		.WIDTH (8)
	) u_dri (
		.clk           (dri_clk      ),
		.rst_n         (apb_prstn & work_en),
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
		.lcd_id        (lcd_id       ),
		.maxpoint      (multi_en ? maxpoint[3:0] : 4'd1),
		.interval      (interval     ),
		.touch_rst_n   (touch_rst_n  ),
		.touch_int_in  (touch_int_in ),
		.touch_int_dir (touch_int_dir),
		.touch_int_out (touch_int_out),
		.pt_id         (pt_id        ),
		.pt_x          (pt_x         ),
		.pt_y          (pt_y         ),
		.pt_valid      (pt_valid     ),
		.pt_num        (pt_num       ),
		.frame_valid   (frame_valid  )
	);

	// ---------------- 跨时钟：两相（toggle）握手 ----------------
	// 每产生一条记录，dri 域把 hs_tog 翻转一次；pclk 域用两级同步器
	// 跟随，检测到相位不同即取数并更新 ack_r；dri 域再同步回 ack_r，
	// 相位一致后允许下一条。比“电平置 1 再归 0”的做法可靠：后者在
	// hs_req 回落时会被 pclk 侧误判成一次新的传输。
	// dri 域
	reg        hs_tog;       // 记录相位，每发一条翻转
	reg        hs_kind;      // 0 = 点记录，1 = 帧结束（点数）
	reg [31:0] hs_data;
	reg [3:0]  hs_num;
	reg        ack_sync_dri; // pclk 侧已消费到的相位
	wire       hs_idle = (ack_sync_dri == hs_tog);

	// pclk 域
	reg        req_meta, req_sync, ack_r;
	wire       req_pclk = req_sync;

	// 两级同步器：hs_tog 进 pclk，ack_r 回 dri
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			req_meta <= 1'b0;
			req_sync <= 1'b0;
		end else begin
			req_meta <= hs_tog;
			req_sync <= req_meta;
		end
	end
	always @(posedge dri_clk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			ack_sync_dri <= 1'b0;
		end else begin
			ack_sync_dri <= ack_r;
		end
	end

	// -------- FIFO（pclk 域写，pclk 域读） --------
	reg  [31:0] fifo_mem [0:15];
	reg  [3:0]  wptr, rptr;
	reg  [4:0]  fcnt;
	reg  [3:0]  num_reg;
	reg         frame_ok;
	reg  [31:0] rec_pack;

	wire        fifo_empty = (fcnt == 5'd0);
	wire        fifo_full  = (fcnt == 5'd16);
	// 收到一条记录（相位不同）：帧结束只更新 num_reg，点记录才入队
	wire        acc_item   = (req_pclk != ack_r);
	wire        fifo_we    = acc_item && !hs_kind && !fifo_full;
	wire        fifo_re    = rd && (apb_paddr[7:0] == R_DATA) && !fifo_empty;

	// 记录打包：多点 {id,x,y}；单点 {x[15:0],y[15:0]}
	always @(*) begin
		if (multi_en)
			rec_pack = {hs_data[31:28], hs_data[27:14], hs_data[13:0]};
		else
			rec_pack = {2'b00, hs_data[27:14], 2'b00, hs_data[13:0]};
	end

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			wptr     <= 4'd0;
			rptr     <= 4'd0;
			fcnt     <= 5'd0;
			ack_r    <= 1'b0;
			num_reg  <= 4'd0;
			frame_ok <= 1'b0;
		end else begin
			// 握手接收：无论点还是帧，都推进 ack 相位
			if (acc_item) begin
				ack_r <= req_pclk;
				if (hs_kind) begin
					num_reg  <= hs_num;
					frame_ok <= 1'b1;
				end
			end

			// 清 FIFO 优先；否则写/读各驱动自己的指针，fcnt 单点更新
			if (clr_fifo) begin
				rptr     <= 4'd0;
				wptr     <= 4'd0;
				fcnt     <= 5'd0;
				num_reg  <= 4'd0;
				frame_ok <= 1'b0;
			end else begin
				if (fifo_we) begin
					fifo_mem[wptr] <= rec_pack;
					wptr <= wptr + 4'd1;
				end
				if (fifo_re) begin
					rptr <= rptr + 4'd1;
				end
				case ({fifo_we, fifo_re})
					2'b10  : fcnt <= fcnt + 5'd1;
					2'b01  : fcnt <= fcnt - 5'd1;
					default: ;
				endcase
			end
		end
	end

	// -------- dri 域：相位翻转，接收方跟上后才允许下一条 --------
	always @(posedge dri_clk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			hs_tog  <= 1'b0;
			hs_kind <= 1'b0;
			hs_data <= 32'd0;
			hs_num  <= 4'd0;
		end else if (hs_idle) begin
			if (pt_valid) begin
				hs_data <= {pt_id, pt_x, pt_y};
				hs_kind <= 1'b0;
				hs_tog  <= ~hs_tog;
			end else if (frame_valid) begin
				hs_num  <= pt_num;
				hs_kind <= 1'b1;
				hs_tog  <= ~hs_tog;
			end
		end
	end

	// ---------------- 读数据选择 ----------------
	assign touch_irq = irq_en & !fifo_empty;

	always @(*) begin
		if (rd) begin
			case (apb_paddr[7:0])
				R_CTRL     : prdata = ctrl;
				R_INTERVAL : prdata = interval;
				R_DATA     : prdata = fifo_empty ? 32'hffff_ffff : fifo_mem[rptr];
				R_NUM      : prdata = {28'd0, num_reg};
				R_STATUS   : prdata = {23'd0, frame_ok, 6'd0, fifo_full, fifo_empty};
				R_MAXPOINT : prdata = maxpoint;
				R_VERSION  : prdata = 32'h5450_0002;
				default    : prdata = 32'b0;
			endcase
		end else begin
			prdata = 32'b0;
		end
	end
	assign apb_prdata = prdata;

endmodule
