`include "config_sel.vh"
`include "apb_addr.svh"
`include "config.vh"
module godson_mcu_top (
    input           clk50m ,
    input           rstn   ,
	input 			reset_clear,
    output          pps_led,
//    input[3:0]      sw_int,
    input[1:0]      btn_int,

`ifdef DDR_PERIPHERALS
    // ============== DDR3 物理接口 (axi_subsys -> MIG -> DDR3 颗粒) ==============
    output          ddr3_reset_n,      // DDR3 复位
    output [0:0]    ddr3_ck_p   ,      // DDR3 差分时钟 正
    output [0:0]    ddr3_ck_n   ,      // DDR3 差分时钟 负
    output [0:0]    ddr3_cke    ,      // DDR3 时钟使能
    output [0:0]    ddr3_cs_n   ,      // DDR3 片选
    output [2:0]    ddr3_ba     ,      // DDR3 Bank 选择
    output [14:0]   ddr3_addr   ,      // DDR3 地址
    output          ddr3_ras_n  ,      // DDR3 行选
    output          ddr3_cas_n  ,      // DDR3 列选
    output          ddr3_we_n   ,      // DDR3 读写选择
    output [3:0]    ddr3_dm     ,      // DDR3 数据掩码
    output [0:0]    ddr3_odt    ,      // DDR3 片内端接
    inout  [31:0]   ddr3_dq     ,      // DDR3 数据
    inout  [3:0]    ddr3_dqs_n  ,      // DDR3 数据选通 负
    inout  [3:0]    ddr3_dqs_p  ,      // DDR3 数据选通 正
`endif

`ifdef GPIO_PERIPHERALS
//    inout [51:0] gpio,
	inout           gpio0,//sw0~7
	inout           gpio1,//sw1
	inout           gpio2,//sw2
	inout           gpio3,//sw3
	inout           gpio4,//sw4
	inout           gpio5,//sw5
	inout           gpio6,//sw6
	inout           gpio7,//sw7
	
	inout           gpio24,//LED_0
	inout           gpio25,//LED_1
	inout           gpio26,//LED_2
	inout           gpio27,//LED_3
	inout           gpio28,//LED_4
	inout           gpio29,//LED_5
	inout           gpio30,//LED_6
	inout           gpio31,//LED_7
	
	inout           gpio48,//an_0
	inout           gpio49,//an_1
	inout           gpio50,//an_2
	
	inout           gpio56,//seg_0
	inout           gpio57,//seg_1
	inout           gpio58,//seg_2
	inout           gpio59,//seg_3
	inout           gpio60,//seg_4
	inout           gpio61,//seg_5
	inout           gpio62,//seg_6
	inout           gpio63,//seg_7
`endif
`ifdef ARRAY_PERIPHERALS	
	inout           gpio8,//matrix_col0
	inout           gpio9,//matrix_col1
	inout           gpio10,//matrix_col2
	inout           gpio11,//matrix_col3
	
	inout           gpio16,//matrix_row0
	inout           gpio17,//matrix_row1
	inout           gpio18,//matrix_row2
	inout           gpio19,//matrix_row3
	
	inout           gpio32,//led_col0
    inout           gpio33,//led_col1
    inout           gpio34,//led_col2
    inout           gpio35,//led_col3
    inout           gpio36,//led_col4
    inout           gpio37,//led_col5
    inout           gpio38,//led_col6
    inout           gpio39,//led_col7
 
 	inout           gpio40,//led_row0
	inout           gpio41,//led_row1
	inout           gpio42,//led_row2
	inout           gpio43,//led_row3
	inout           gpio44,//led_row4
	inout           gpio45,//led_row5
	inout           gpio46,//led_row6
	inout           gpio47,//led_row7
`endif

`ifdef Step_motor_PERIPHERALS
//	 J8-step_motor
	inout           gpio12,
	inout           gpio13,
	inout           gpio14,
	inout           gpio15,
`endif

`ifdef UART_PERIPHERALS
	input           uart0_rx,
	output          uart0_tx,
`endif

`ifdef IIC_PERIPHERALS
	inout           iic0_scl,
	inout           iic0_sda,
	inout           iic1_scl,
	inout           iic1_sda,
//	inout           iic2_scl,
//	inout           iic2_sda,
`endif

`ifdef USB_PERIPHERALS
	inout           usb_clk_60m,
	input           usb_rxf_n  ,
	inout           usb_txf_n  ,
	inout           usb_oe_n   ,
	inout          	usb_rd_n   ,
	inout           usb_wr_n   ,
	inout           usb_siwu_n ,
	inout  [7:0]    usb_data   ,
`endif

`ifdef LCD_PERIPHERALS
	output          lcd_hs      ,
	output          lcd_vs      ,
	output          lcd_de      ,
	output          lcd_bl      ,
	output          lcd_clk     ,
	output          lcd_rst_n   ,
	inout  [23:0]   lcd_rgb     ,
`endif

`ifdef TOUCH_PERIPHERALS
	output          touch_scl  ,
	inout           touch_sda  ,
	inout           touch_int  ,
	output          touch_rst_n,
`endif

`ifdef PWM_PERIPHERALS
	output          pwm1,
	output          pwm2,
`endif

`ifdef SPI_PERIPHERALS
	inout  [1:0]    spi_clk ,
	inout  [0:0]    spi_miso,
	inout  [1:0]    spi_mosi,
	inout  [1:0]    spi_csn ,
`endif

`ifdef ADC_9280_PERIPHERALS
    output       adc_clk,    // ADC_CLK
    input [7:0]  adc_data,    // ADC_DATA
    input adc_otr,
`endif
`ifdef DAC_9708_PERIPHERALS
    output       dac_clk,    // dac_CLK
    output [7:0]  dac_data,    // dac_DATA
`endif

    input           ljtag_trst, ljtag_tms , ljtag_tdi, ljtag_tck,
    output          ljtag_tdo
	
);

	parameter   ADDR_APB = 32,
				DATA_APB = 32;

	wire clk_ext32m;
	wire lcd_sys_clk; // 50 MHz
	wire ddr_refclk ; // 200 MHz, 供 MIG 作 sys_clk_i / 参考时钟
//	wire audio_sys_clk; // 12 MHz
//	wire eth_sys_clk; // 200 MHz
//	wire pixel_clk; //65MHZ
//	wire pixel_clk_5x; //325MHZ
	wire locked;
	
	wire rst_n;

	clk_wiz_0 clk_wiz_0_inst (.clk_in1(clk50m), .resetn(rstn), .locked(locked), .clk_out1(clk_ext32m)
	,.clk_out2(lcd_sys_clk)
//	, .clk_out3(audio_sys_clk)
	, .clk_out4(ddr_refclk)
		// .clk_out5(pixel_clk)
//		, .clk_out6(pixel_clk_5x)
		);
	assign rst_n = rstn & locked;

//	assign audio_mclk = audio_sys_clk;

	// ================================================================
	// ================================================================
	// ================================================================
	
	// ================================================================ interrupt below
	wire [4:0] pmu_int = 5'b0;
	wire gpio_irq;
	wire uart0_irq;
	wire intc_irq;
	wire timer_irq;
	wire iic0_irq;
	wire usb_irq;
	wire touch_irq;
	wire spi_irq;
	wire array_key_irq;
	wire dma_irq;

	// ---- 新 AXI 子系统中断 ----
	wire axi_dma_irq;   // AXI DMAC (0x4001_0000)
	wire axi_lcd_irq;   // AXI LCD  (0x4000_0000)
	
	wire [5:0] interrupt = {gpio_irq, intc_irq, 4'h0};
	// ================================================================	interrupt above

	wire [`APB_SLAVE_NUM - 1 : 0]          periph_psel   ;
	wire [`APB_SLAVE_NUM * ADDR_APB - 1:0] periph_paddr  ;
	wire [`APB_SLAVE_NUM - 1 : 0]          periph_pwrite ;
	wire [ 4*`APB_SLAVE_NUM - 1 : 0]       periph_pstrb;
	wire [`APB_SLAVE_NUM - 1 : 0]          periph_penable;
	wire [`APB_SLAVE_NUM * DATA_APB - 1:0] periph_pwdata ;
	wire [`APB_SLAVE_NUM * DATA_APB - 1:0] periph_prdata ;
	wire [`APB_SLAVE_NUM - 1 : 0]          periph_pack   ;

	`APB_PERIPH_DECLARATION(gpio,  ADDR_APB, DATA_APB, 0);  // 32'h30000000
	`APB_PERIPH_DECLARATION(uart,  ADDR_APB, DATA_APB, 1);  // 32'h30010000
	`APB_PERIPH_DECLARATION(intc,  ADDR_APB, DATA_APB, 2);  // 32'h30020000
	`APB_PERIPH_DECLARATION(timer, ADDR_APB, DATA_APB, 3);  // 32'h30030000
	`APB_PERIPH_DECLARATION(iic,   ADDR_APB, DATA_APB, 4);  // 32'h30040000
`ifdef EXP_KBD
	`APB_PERIPH_DECLARATION(kbd,   ADDR_APB, DATA_APB, 5);  // 32'h30050000 矩阵键盘（实验二/六）
`endif
	`APB_PERIPH_DECLARATION(touch, ADDR_APB, DATA_APB, 6);  // 32'h30060000
`ifdef EXP_DOT
	`APB_PERIPH_DECLARATION(dot,   ADDR_APB, DATA_APB, 7);  // 32'h30070000 LED 点阵（实验七）
`endif
//	`APB_PERIPH_DECLARATION(eth,   ADDR_APB, DATA_APB, 8);  // 32'h30080000
	`APB_PERIPH_DECLARATION(pwm,   ADDR_APB, DATA_APB, 9); // 32'h30090000
	`APB_PERIPH_DECLARATION(spi,   ADDR_APB, DATA_APB, 10); // 32'h300a0000
	`APB_PERIPH_DECLARATION(adc9280, ADDR_APB, DATA_APB, 11); // 32'h300b0000
	`APB_PERIPH_DECLARATION(dac9708, ADDR_APB, DATA_APB, 12); // 32'h300c0000
//	`APB_PERIPH_DECLARATION(fir,   ADDR_APB, DATA_APB, 13); // 32'h300d0000
	`APB_PERIPH_DECLARATION(dma,   ADDR_APB, DATA_APB, 14); // 32'h300e0000
	`APB_PERIPH_DECLARATION(ram,   ADDR_APB, DATA_APB, 15); // 32'h300f0000
	// 2026-11-02: usb 原来完全没有 APB 端口声明 (usb_psel 等是隐式悬空线,
	// CPU 永远选不中它)。挂到 id 16 = 0x3010_0000, 寄存器 USB_DATA=+0x0,
	// USB_CTRL=+0x4 (读回 {5'b0, tx_full, !rx_empty})。
	`APB_PERIPH_DECLARATION(usb,   ADDR_APB, DATA_APB, 16); // 32'h30100000
	`APB_PERIPH_DECLARATION(lcd,   ADDR_APB, DATA_APB, 17);  // 32'h32000000
//	`APB_PERIPH_DECLARATION(hdmi,  ADDR_APB, DATA_APB, 18); // 32'h33000000

	wire                   dma_m_psel   ;
	wire [ ADDR_APB - 1:0] dma_m_paddr  ;
	wire [ 0 : 0]          dma_m_pwrite ;
	wire [ 3 : 0]          dma_m_pstrb;
	wire [ 0 : 0]          dma_m_penable;
	wire [ DATA_APB - 1:0] dma_m_pwdata ;
	wire [ DATA_APB - 1:0] dma_m_prdata ;
	wire [ 0 : 0]          dma_m_pack   ;

	// ==================================================================
	//  M0 / S0 AXI 互联线 (必须声明在 A_cpu 例化之前, 否则会被隐式
	//  声明成 1bit)
	// ==================================================================
	wire [`LID      - 1 : 0] cpu_m_awid   ;
	wire [`LAWADDR  - 1 : 0] cpu_m_awaddr ;
	wire [`LAWLEN   - 1 : 0] cpu_m_awlen  ;
	wire [`LAWSIZE  - 1 : 0] cpu_m_awsize ;
	wire [`LAWBURST - 1 : 0] cpu_m_awburst;
	wire [`LAWLOCK  - 1 : 0] cpu_m_awlock ;
	wire [`LAWCACHE - 1 : 0] cpu_m_awcache;
	wire [`LAWPROT  - 1 : 0] cpu_m_awprot ;
	wire                     cpu_m_awvalid;
	wire                     cpu_m_awready;
	wire [`LID      - 1 : 0] cpu_m_wid    ;
	wire [`LWDATA   - 1 : 0] cpu_m_wdata  ;
	wire [`LWSTRB   - 1 : 0] cpu_m_wstrb  ;
	wire                     cpu_m_wlast  ;
	wire                     cpu_m_wvalid ;
	wire                     cpu_m_wready ;
	wire [`LID      - 1 : 0] cpu_m_bid    ;
	wire [`LBRESP   - 1 : 0] cpu_m_bresp  ;
	wire                     cpu_m_bvalid ;
	wire                     cpu_m_bready ;
	wire [`LID      - 1 : 0] cpu_m_arid   ;
	wire [`LARADDR  - 1 : 0] cpu_m_araddr ;
	wire [`LARLEN   - 1 : 0] cpu_m_arlen  ;
	wire [`LARSIZE  - 1 : 0] cpu_m_arsize ;
	wire [`LARBURST - 1 : 0] cpu_m_arburst;
	wire [`LARLOCK  - 1 : 0] cpu_m_arlock ;
	wire [`LARCACHE - 1 : 0] cpu_m_arcache;
	wire [`LARPROT  - 1 : 0] cpu_m_arprot ;
	wire                     cpu_m_arvalid;
	wire                     cpu_m_arready;
	wire [`LID      - 1 : 0] cpu_m_rid    ;
	wire [`LRDATA   - 1 : 0] cpu_m_rdata  ;
	wire [`LRRESP   - 1 : 0] cpu_m_rresp  ;
	wire                     cpu_m_rlast  ;
	wire                     cpu_m_rvalid ;
	wire                     cpu_m_rready ;

	wire [`LID      - 1 : 0] apb_s_awid   ;
	wire [`LAWADDR  - 1 : 0] apb_s_awaddr ;
	wire [`LAWLEN   - 1 : 0] apb_s_awlen  ;
	wire [`LAWSIZE  - 1 : 0] apb_s_awsize ;
	wire [`LAWBURST - 1 : 0] apb_s_awburst;
	wire [`LAWLOCK  - 1 : 0] apb_s_awlock ;
	wire [`LAWCACHE - 1 : 0] apb_s_awcache;
	wire [`LAWPROT  - 1 : 0] apb_s_awprot ;
	wire                     apb_s_awvalid;
	wire                     apb_s_awready;
	wire [`LID      - 1 : 0] apb_s_wid    ;
	wire [`LWDATA   - 1 : 0] apb_s_wdata  ;
	wire [`LWSTRB   - 1 : 0] apb_s_wstrb  ;
	wire                     apb_s_wlast  ;
	wire                     apb_s_wvalid ;
	wire                     apb_s_wready ;
	wire [`LID      - 1 : 0] apb_s_bid    ;
	wire [`LBRESP   - 1 : 0] apb_s_bresp  ;
	wire                     apb_s_bvalid ;
	wire                     apb_s_bready ;
	wire [`LID      - 1 : 0] apb_s_arid   ;
	wire [`LARADDR  - 1 : 0] apb_s_araddr ;
	wire [`LARLEN   - 1 : 0] apb_s_arlen  ;
	wire [`LARSIZE  - 1 : 0] apb_s_arsize ;
	wire [`LARBURST - 1 : 0] apb_s_arburst;
	wire [`LARLOCK  - 1 : 0] apb_s_arlock ;
	wire [`LARCACHE - 1 : 0] apb_s_arcache;
	wire [`LARPROT  - 1 : 0] apb_s_arprot ;
	wire                     apb_s_arvalid;
	wire                     apb_s_arready;
	wire [`LID      - 1 : 0] apb_s_rid    ;
	wire [`LRDATA   - 1 : 0] apb_s_rdata  ;
	wire [`LRRESP   - 1 : 0] apb_s_rresp  ;
	wire                     apb_s_rlast  ;
	wire                     apb_s_rvalid ;
	wire                     apb_s_rready ;

	wire init_calib_complete;

	// LCD ID (由 axi_lcd 输出, 16'h4384) 与 INTC 的 mul_sel :
	// 这两个 net 在 touch_top / intc_top 里被引用, 必须在使用前显式声明,
	// 否则会被隐式声明成 1bit (Vivado 能推断, 但 iverilog 会告警)。
	wire [15:0] lcd_id;
	wire [31:0] mul_sel;

	// ------------------------------------------------------------------
	// 11.5 节实验模块的公共连线
	//   这些 net 由 EXP_* 宏控制的模块驱动, 在这里统一声明, 避免使用处
	//   被隐式声明成 1 bit。
	// ------------------------------------------------------------------
	wire        kbd_irq;          // 矩阵键盘有新键（单拍脉冲）
	wire [3:0]  kbd_row;          // 行驱动, 接 gpio16~19
	wire [3:0]  kbd_col;          // 列采样, 接 gpio8~11
	wire        dot_frame_irq;    // 点阵帧同步（单拍脉冲）
	wire [7:0]  dot_row;          // 行选, 接 gpio40~47
	wire [7:0]  dot_col;          // 列数据, 接 gpio32~39
	wire        spi_stream_irq;   // 流式 SPI 的 RX 半满中断
	wire        spi_irq_exp;      // 送 INTC int_2 的 SPI 中断（两种实现二选一）
	wire [7:0]  spi_mul_s;        // 两版 SPI 控制器都有 spi_mul 输出

	// ------------------------------------------------------------------
	// ljtag TCK 时钟网络 (2026-11-05)
	//-------------------------------------------------------------------
	// 现象: 工程模式新出的 bit 下载后, LALINK/openocd 读回的 IDCODE 是
	//       0x2D2D2D2D / 0xB4B4B4B4, 正确值是 0x5A5A5A5A。
	//       前者 = 0x5A5A5A5A >> 1, 后者 = 0x5A5A5A5A << 1 —— 整体错一位,
	//       只是方向相反。TAP 的 DR/IR 全部错位, halt / load_image 一律
	//       失败, 只能报 "Failed to enter Debug Mode", make flash 无法执行。
	// 实测对照 (同一块板, 同一根 LALINK):
	//       11-04 projfix bit  : TCK 经门控, TDO 组合 -> 读 0x5A5A5A5A OK
	//       11-05 工程 bit     : TCK 经门控, TDO 组合 -> 0x2D2D2D2D (偏早)
	//       11-05 + negedge 打拍: TCK 走 BUFG, TDO 打拍 -> 0xB4B4B4B4 (偏晚)
	//       即 TDO 的变化点相对 LALINK 的采样沿只差几 ns, 处在临界窗口里,
	//       place 结果一变(本次新增 ADC/DAC 逻辑)就翻面。降 adapter speed
	//       从 2 MHz 到 100 kHz 无效 —— 采样点相对 TCK 边沿固定, 与周期无关。
	// 处理: 把 TCK 显式走 BUFG (比 IBUF 直连多约 3~5 ns), 让 TDO 的变化点
	//       整体后移, 落在 0x2D2D2D2D(偏早) 与 0xB4B4B4B4(偏晚) 之间;
	//       TDO 恢复组合直连, 不再打拍(打拍会整整晚半个周期, 已实测过头)。
	//       la132.xdc 里已有 CLOCK_DEDICATED_ROUTE FALSE [get_nets
	//       ljtag_tck_IBUF], BUFG 可以走普通布线, 不会报 DRC。
	//-------------------------------------------------------------------
	wire ljtag_tck_g;
	BUFG u_ljtag_tck_bufg (.I(ljtag_tck), .O(ljtag_tck_g));

	godson_mcu_cpu A_cpu (
		.clock          (clk_ext32m     ),
		.resetn         (rst_n          ),
		.reset_clear	(reset_clear	),
		.periph_psel    (periph_psel    ),
		.periph_paddr   (periph_paddr   ),
		.periph_pstrb   (periph_pstrb),
		.periph_pwrite  (periph_pwrite  ),
		
		.periph_penable (periph_penable ),
		.periph_pwdata  (periph_pwdata  ),
		.periph_prdata  (periph_prdata  ),
		.periph_pack    (periph_pack    ),

		.dma_psel       (dma_m_psel     ),
		.dma_paddr      (dma_m_paddr    ),
		.dma_pwrite     (dma_m_pwrite   ),
		.dma_pstrb      (dma_m_pstrb    ),
		.dma_penable    (dma_m_penable  ),
		.dma_pwdata     (dma_m_pwdata   ),
		.dma_prdata     (dma_m_prdata   ),
		.dma_pack       (dma_m_pack     ),

		.ljtag_trst_i   (ljtag_trst     ),
		.ljtag_tms_i    (ljtag_tms      ),
		.ljtag_tdo_o    (ljtag_tdo      ),
		.ljtag_tdi_i    (ljtag_tdi      ),
		.ljtag_tck_i    (ljtag_tck_g    ),

		.interrupt      (interrupt      ),
		.pps_led        (pps_led        ),

		// ---- M0 : CPU AXI 主口 -> axi_subsys.u_axi_subsys ----
		.m_awid         (cpu_m_awid     ),
		.m_awaddr       (cpu_m_awaddr   ),
		.m_awlen        (cpu_m_awlen    ),
		.m_awsize       (cpu_m_awsize   ),
		.m_awburst      (cpu_m_awburst  ),
		.m_awlock       (cpu_m_awlock   ),
		.m_awcache      (cpu_m_awcache  ),
		.m_awprot       (cpu_m_awprot   ),
		.m_awvalid      (cpu_m_awvalid  ),
		.m_awready      (cpu_m_awready  ),
		.m_wid          (cpu_m_wid      ),
		.m_wdata        (cpu_m_wdata    ),
		.m_wstrb        (cpu_m_wstrb    ),
		.m_wlast        (cpu_m_wlast    ),
		.m_wvalid       (cpu_m_wvalid   ),
		.m_wready       (cpu_m_wready   ),
		.m_bid          (cpu_m_bid      ),
		.m_bresp        (cpu_m_bresp    ),
		.m_bvalid       (cpu_m_bvalid   ),
		.m_bready       (cpu_m_bready   ),
		.m_arid         (cpu_m_arid     ),
		.m_araddr       (cpu_m_araddr   ),
		.m_arlen        (cpu_m_arlen    ),
		.m_arsize       (cpu_m_arsize   ),
		.m_arburst      (cpu_m_arburst  ),
		.m_arlock       (cpu_m_arlock   ),
		.m_arcache      (cpu_m_arcache  ),
		.m_arprot       (cpu_m_arprot   ),
		.m_arvalid      (cpu_m_arvalid  ),
		.m_arready      (cpu_m_arready  ),
		.m_rid          (cpu_m_rid      ),
		.m_rdata        (cpu_m_rdata    ),
		.m_rresp        (cpu_m_rresp    ),
		.m_rlast        (cpu_m_rlast    ),
		.m_rvalid       (cpu_m_rvalid   ),
		.m_rready       (cpu_m_rready   ),

		// ---- S0 : axi_subsys 从口 -> 内部 axi2apb_bridge ----
		.apb_s_awid     (apb_s_awid     ),
		.apb_s_awaddr   (apb_s_awaddr   ),
		.apb_s_awlen    (apb_s_awlen    ),
		.apb_s_awsize   (apb_s_awsize   ),
		.apb_s_awburst  (apb_s_awburst  ),
		.apb_s_awlock   (apb_s_awlock   ),
		.apb_s_awcache  (apb_s_awcache  ),
		.apb_s_awprot   (apb_s_awprot   ),
		.apb_s_awvalid  (apb_s_awvalid  ),
		.apb_s_awready  (apb_s_awready  ),
		.apb_s_wid      (apb_s_wid      ),
		.apb_s_wdata    (apb_s_wdata    ),
		.apb_s_wstrb    (apb_s_wstrb    ),
		.apb_s_wlast    (apb_s_wlast    ),
		.apb_s_wvalid   (apb_s_wvalid   ),
		.apb_s_wready   (apb_s_wready   ),
		.apb_s_bid      (apb_s_bid      ),
		.apb_s_bresp    (apb_s_bresp    ),
		.apb_s_bvalid   (apb_s_bvalid   ),
		.apb_s_bready   (apb_s_bready   ),
		.apb_s_arid     (apb_s_arid     ),
		.apb_s_araddr   (apb_s_araddr   ),
		.apb_s_arlen    (apb_s_arlen    ),
		.apb_s_arsize   (apb_s_arsize   ),
		.apb_s_arburst  (apb_s_arburst  ),
		.apb_s_arlock   (apb_s_arlock   ),
		.apb_s_arcache  (apb_s_arcache  ),
		.apb_s_arprot   (apb_s_arprot   ),
		.apb_s_arvalid  (apb_s_arvalid  ),
		.apb_s_arready  (apb_s_arready  ),
		.apb_s_rid      (apb_s_rid      ),
		.apb_s_rdata    (apb_s_rdata    ),
		.apb_s_rresp    (apb_s_rresp    ),
		.apb_s_rlast    (apb_s_rlast    ),
		.apb_s_rvalid   (apb_s_rvalid   ),
		.apb_s_rready   (apb_s_rready   )
);

	// ==================================================================
	//  CPU <-> AXI 子系统 互联线
	//    M0 : CPU 的 AXI 主口         -> axi_interconnect 主设备 0
	//    S0 : axi_interconnect 从口 0 -> CPU 内 axi2apb_bridge -> APB 外设
	//  说明: CPU 只保留一路 AXI 主口, 原来的 axi_mux(AXI0/AXI1 二选一)
	//        已删除, 由 axi_interconnect 统一做 3主 x 4从 译码与仲裁
	// ==================================================================

	// ==================================================================
	//  AXI 子系统 : 3 主设备 (CPU / AXI-DMAC / AXI-LCD) x 4 从设备
	//    S0 APB-BRIDGE : 其余地址           (回 A_cpu 内 axi2apb_bridge)
	//    S1 AXI-DMAC   : 0x4001_0000 / 64KB (axi_dma  配置寄存器)
	//    S2 AXI-LCD    : 0x4000_0000 / 64KB (axi_lcd  配置寄存器)
	//    S3 DDR3       : 0x2000_0000 / 512MB(axi_ddr_slave -> MIG -> DDR3)
	//  CPU 与 AXI-DMAC 都能访问全部 4 个从设备。
	// ==================================================================
	axi_subsys u_axi_subsys (
		.aclk                 (clk_ext32m     ),
		.aresetn              (rst_n          ),
		.lcd_sys_clk          (lcd_sys_clk    ),
		.lcd_sys_rstn         (rst_n          ),
		.ddr_refclk           (ddr_refclk     ),
		.ddr_sys_rst          (~rst_n         ),

		// ---- M0 : CPU 主口 ----
		.cpu_m_awid           (cpu_m_awid     ),
		.cpu_m_awaddr         (cpu_m_awaddr   ),
		.cpu_m_awlen          (cpu_m_awlen    ),
		.cpu_m_awsize         (cpu_m_awsize   ),
		.cpu_m_awburst        (cpu_m_awburst  ),
		.cpu_m_awlock         (cpu_m_awlock   ),
		.cpu_m_awcache        (cpu_m_awcache  ),
		.cpu_m_awprot         (cpu_m_awprot   ),
		.cpu_m_awvalid        (cpu_m_awvalid  ),
		.cpu_m_awready        (cpu_m_awready  ),
		.cpu_m_wid            (cpu_m_wid      ),
		.cpu_m_wdata          (cpu_m_wdata    ),
		.cpu_m_wstrb          (cpu_m_wstrb    ),
		.cpu_m_wlast          (cpu_m_wlast    ),
		.cpu_m_wvalid         (cpu_m_wvalid   ),
		.cpu_m_wready         (cpu_m_wready   ),
		.cpu_m_bid            (cpu_m_bid      ),
		.cpu_m_bresp          (cpu_m_bresp    ),
		.cpu_m_bvalid         (cpu_m_bvalid   ),
		.cpu_m_bready         (cpu_m_bready   ),
		.cpu_m_arid           (cpu_m_arid     ),
		.cpu_m_araddr         (cpu_m_araddr   ),
		.cpu_m_arlen          (cpu_m_arlen    ),
		.cpu_m_arsize         (cpu_m_arsize   ),
		.cpu_m_arburst        (cpu_m_arburst  ),
		.cpu_m_arlock         (cpu_m_arlock   ),
		.cpu_m_arcache        (cpu_m_arcache  ),
		.cpu_m_arprot         (cpu_m_arprot   ),
		.cpu_m_arvalid        (cpu_m_arvalid  ),
		.cpu_m_arready        (cpu_m_arready  ),
		.cpu_m_rid            (cpu_m_rid      ),
		.cpu_m_rdata          (cpu_m_rdata    ),
		.cpu_m_rresp          (cpu_m_rresp    ),
		.cpu_m_rlast          (cpu_m_rlast    ),
		.cpu_m_rvalid         (cpu_m_rvalid   ),
		.cpu_m_rready         (cpu_m_rready   ),

		// ---- S0 : APB 桥从口 ----
		.apb_s_awid           (apb_s_awid     ),
		.apb_s_awaddr         (apb_s_awaddr   ),
		.apb_s_awlen          (apb_s_awlen    ),
		.apb_s_awsize         (apb_s_awsize   ),
		.apb_s_awburst        (apb_s_awburst  ),
		.apb_s_awlock         (apb_s_awlock   ),
		.apb_s_awcache        (apb_s_awcache  ),
		.apb_s_awprot         (apb_s_awprot   ),
		.apb_s_awvalid        (apb_s_awvalid  ),
		.apb_s_awready        (apb_s_awready  ),
		.apb_s_wid            (apb_s_wid      ),
		.apb_s_wdata          (apb_s_wdata    ),
		.apb_s_wstrb          (apb_s_wstrb    ),
		.apb_s_wlast          (apb_s_wlast    ),
		.apb_s_wvalid         (apb_s_wvalid   ),
		.apb_s_wready         (apb_s_wready   ),
		.apb_s_bid            (apb_s_bid      ),
		.apb_s_bresp          (apb_s_bresp    ),
		.apb_s_bvalid         (apb_s_bvalid   ),
		.apb_s_bready         (apb_s_bready   ),
		.apb_s_arid           (apb_s_arid     ),
		.apb_s_araddr         (apb_s_araddr   ),
		.apb_s_arlen          (apb_s_arlen    ),
		.apb_s_arsize         (apb_s_arsize   ),
		.apb_s_arburst        (apb_s_arburst  ),
		.apb_s_arlock         (apb_s_arlock   ),
		.apb_s_arcache        (apb_s_arcache  ),
		.apb_s_arprot         (apb_s_arprot   ),
		.apb_s_arvalid        (apb_s_arvalid  ),
		.apb_s_arready        (apb_s_arready  ),
		.apb_s_rid            (apb_s_rid      ),
		.apb_s_rdata          (apb_s_rdata    ),
		.apb_s_rresp          (apb_s_rresp    ),
		.apb_s_rlast          (apb_s_rlast    ),
		.apb_s_rvalid         (apb_s_rvalid   ),
		.apb_s_rready         (apb_s_rready   ),

		// ---- LCD 物理接口 (由 axi_lcd 驱动) ----
		.lcd_id               (lcd_id         ),
		.lcd_clk              (lcd_clk        ),
		.lcd_rstn             (lcd_rst_n      ),
		.lcd_de               (lcd_de         ),
		.lcd_bl               (lcd_bl         ),
		.lcd_hs               (lcd_hs         ),
		.lcd_vs               (lcd_vs         ),
		.lcd_rgb              (lcd_rgb        ),

		// ---- DDR3 物理接口 ----
		.init_calib_complete  (init_calib_complete),
		.ddr3_addr            (ddr3_addr      ),
		.ddr3_ba              (ddr3_ba        ),
		.ddr3_cas_n           (ddr3_cas_n     ),
		.ddr3_ck_n            (ddr3_ck_n      ),
		.ddr3_ck_p            (ddr3_ck_p      ),
		.ddr3_cke             (ddr3_cke       ),
		.ddr3_ras_n           (ddr3_ras_n     ),
		.ddr3_reset_n         (ddr3_reset_n   ),
		.ddr3_we_n            (ddr3_we_n      ),
		.ddr3_dq              (ddr3_dq        ),
		.ddr3_dqs_n           (ddr3_dqs_n     ),
		.ddr3_dqs_p           (ddr3_dqs_p     ),
		.ddr3_cs_n            (ddr3_cs_n      ),
		.ddr3_dm              (ddr3_dm        ),
		.ddr3_odt             (ddr3_odt       ),

		// ---- 中断 ----
		.dma_irq              (axi_dma_irq    ),
		.lcd_irq              (axi_lcd_irq    )
	);

	// AXI LCD 的帧结束/欠载中断是"粘滞位", 需要软件写 LCD REG_STATUS(0x3001_0008)
	// 的 bit3/bit2 做 W1C 清除; 为避免一直拉高打扰原触摸中断, 这里不并入 INTC。
	// 如确需接入, 把 intc_inst 的 .int_7 改成 (touch_irq | axi_lcd_irq) 即可。


`ifdef GPIO_PERIPHERALS
	//gpio_mul
	wire [63:0] gpio_oe;      // 送 IOBUF 的最终输出使能
	wire [63:0] gpio_o;       // 送 IOBUF 的最终输出数据
	wire [63:0] gpio_i;
	wire [63:0] gpio_oe_cpu;  // GPIO 模块给出的（可被实验控制器旁路）
	wire [63:0] gpio_o_cpu;

	gpio_top gpio_inst (
		.apb_pclk       (clk_ext32m     ),
		.apb_prstn      (rst_n          ),
		.apb_psel       (gpio_psel      ),
		.apb_paddr      (gpio_paddr     ),
		.apb_pstrb      (gpio_pstrb     ),
		.apb_pwrite     (gpio_pwrite    ),
		.apb_penable    (gpio_penable   ),
		.apb_pwdata     (gpio_pwdata    ),
		.apb_prdata     (gpio_prdata    ),
		.apb_pready     (gpio_pack      ),

		.gpio_oe        (gpio_oe_cpu    ),
		.gpio_o         (gpio_o_cpu     ),
		.gpio_i         (gpio_i         ),

		.gpio_irq       (gpio_irq       )
);
	// ------------------------------------------------------------------
	// GPIO 输出分配：默认整条总线直通；矩阵键盘 / LED 点阵这两个实验控制器
	// 要独占 J8 上的引脚，由 EXP_KBD / EXP_DOT 把对应位从 CPU 手里接过来。
	// 这样物理引脚仍然只在本文件的 IOBUF 里出现一次，约束不用改。
	// ------------------------------------------------------------------
	assign gpio_oe[7:0]   = gpio_oe_cpu[7:0];
	assign gpio_o [7:0]   = gpio_o_cpu [7:0];
	assign gpio_oe[15:12] = gpio_oe_cpu[15:12];
	assign gpio_o [15:12] = gpio_o_cpu [15:12];
	assign gpio_oe[31:20] = gpio_oe_cpu[31:20];
	assign gpio_o [31:20] = gpio_o_cpu [31:20];
	assign gpio_oe[63:48] = gpio_oe_cpu[63:48];
	assign gpio_o [63:48] = gpio_o_cpu [63:48];

`ifdef EXP_KBD
	// 矩阵键盘：gpio19~16 行驱动（输出，低有效），gpio11~8 列采样（输入，板上上拉）
	// 注意 IOBUF 的 T 是"高有效关断"：T=0 才驱动输出，T=1 是高阻输入。
	assign gpio_oe[19:16] = 4'h0;            // 行线：T=0 -> 输出
	assign gpio_o [19:16] = kbd_row;
	assign gpio_oe[11:8]  = 4'hf;            // 列线：T=1 -> 高阻输入
	assign gpio_o [11:8]  = 4'h0;
`else
	assign gpio_oe[11:8]  = gpio_oe_cpu[11:8];
	assign gpio_o [11:8]  = gpio_o_cpu [11:8];
	assign gpio_oe[19:16] = gpio_oe_cpu[19:16];
	assign gpio_o [19:16] = gpio_o_cpu [19:16];
`endif

`ifdef EXP_DOT
	// LED 点阵：gpio39~32 列数据（输出，高有效），gpio47~40 行选（输出，低有效）
	// T=0 输出（高有效关断，见上）
	assign gpio_oe[39:32] = 8'h00;
	// 2026-11-25 上板实测: 物理最左列是 gpio39, 直接接线会左右镜像。
	// 这里把 dot_col 位序反转, 保证 apb_dot 约定的 "bit0 = 最左列" 生效。
	assign gpio_o [39:32] = {dot_col[0], dot_col[1], dot_col[2], dot_col[3],
	                         dot_col[4], dot_col[5], dot_col[6], dot_col[7]};
	assign gpio_oe[47:40] = 8'h00;
	assign gpio_o [47:40] = dot_row;
`else
	assign gpio_oe[39:32] = gpio_oe_cpu[39:32];
	assign gpio_o [39:32] = gpio_o_cpu [39:32];
	assign gpio_oe[47:40] = gpio_oe_cpu[47:40];
	assign gpio_o [47:40] = gpio_o_cpu [47:40];
`endif
//   genvar gpio_num;
//   generate
//      for (gpio_num=0; gpio_num < 52; gpio_num=gpio_num+1)
//      begin: GPIO_IOBUG
//         IOBUF gpio_iobuf[gpio_num] (.IO(gpio[gpio_num]), .O(gpio_i[gpio_num]), .I(gpio_o[gpio_num]), .T(gpio_oe[gpio_num]));
//      end
//   endgenerate
	IOBUF gpio0_iobuf (.IO(gpio0), .O(gpio_i[0]), .I(gpio_o[0]), .T(gpio_oe[0]));//SW
	IOBUF gpio1_iobuf (.IO(gpio1), .O(gpio_i[1]), .I(gpio_o[1]), .T(gpio_oe[1]));
	IOBUF gpio2_iobuf (.IO(gpio2), .O(gpio_i[2]), .I(gpio_o[2]), .T(gpio_oe[2]));
	IOBUF gpio3_iobuf (.IO(gpio3), .O(gpio_i[3]), .I(gpio_o[3]), .T(gpio_oe[3]));
	IOBUF gpio4_iobuf (.IO(gpio4), .O(gpio_i[4]), .I(gpio_o[4]), .T(gpio_oe[4]));
	IOBUF gpio5_iobuf (.IO(gpio5), .O(gpio_i[5]), .I(gpio_o[5]), .T(gpio_oe[5]));
	IOBUF gpio6_iobuf (.IO(gpio6), .O(gpio_i[6]), .I(gpio_o[6]), .T(gpio_oe[6]));
	IOBUF gpio7_iobuf (.IO(gpio7), .O(gpio_i[7]), .I(gpio_o[7]), .T(gpio_oe[7]));
	
	IOBUF gpio24_iobuf (.IO(gpio24), .O(gpio_i[24]), .I(gpio_o[24]), .T(gpio_oe[24]));//led
	IOBUF gpio25_iobuf (.IO(gpio25), .O(gpio_i[25]), .I(gpio_o[25]), .T(gpio_oe[25]));
	IOBUF gpio26_iobuf (.IO(gpio26), .O(gpio_i[26]), .I(gpio_o[26]), .T(gpio_oe[26]));
	IOBUF gpio27_iobuf (.IO(gpio27), .O(gpio_i[27]), .I(gpio_o[27]), .T(gpio_oe[27]));
	IOBUF gpio28_iobuf (.IO(gpio28), .O(gpio_i[28]), .I(gpio_o[28]), .T(gpio_oe[28]));
	IOBUF gpio29_iobuf (.IO(gpio29), .O(gpio_i[29]), .I(gpio_o[29]), .T(gpio_oe[29]));
	IOBUF gpio30_iobuf (.IO(gpio30), .O(gpio_i[30]), .I(gpio_o[30]), .T(gpio_oe[30]));
	IOBUF gpio31_iobuf (.IO(gpio31), .O(gpio_i[31]), .I(gpio_o[31]), .T(gpio_oe[31]));
	
	IOBUF gpio48_iobuf (.IO(gpio48), .O(gpio_i[48]), .I(gpio_o[48]), .T(gpio_oe[48]));//AN
	IOBUF gpio49_iobuf (.IO(gpio49), .O(gpio_i[49]), .I(gpio_o[49]), .T(gpio_oe[49]));
	IOBUF gpio50_iobuf (.IO(gpio50), .O(gpio_i[50]), .I(gpio_o[50]), .T(gpio_oe[50]));
	
	IOBUF gpio56_iobuf (.IO(gpio56), .O(gpio_i[56]), .I(gpio_o[56]), .T(gpio_oe[56]));//SEG
	IOBUF gpio57_iobuf (.IO(gpio57), .O(gpio_i[57]), .I(gpio_o[57]), .T(gpio_oe[57]));
	IOBUF gpio58_iobuf (.IO(gpio58), .O(gpio_i[58]), .I(gpio_o[58]), .T(gpio_oe[58]));
	IOBUF gpio59_iobuf (.IO(gpio59), .O(gpio_i[59]), .I(gpio_o[59]), .T(gpio_oe[59]));
	IOBUF gpio60_iobuf (.IO(gpio60), .O(gpio_i[60]), .I(gpio_o[60]), .T(gpio_oe[60]));
	IOBUF gpio61_iobuf (.IO(gpio61), .O(gpio_i[61]), .I(gpio_o[61]), .T(gpio_oe[61]));
	IOBUF gpio62_iobuf (.IO(gpio62), .O(gpio_i[62]), .I(gpio_o[62]), .T(gpio_oe[62]));
	IOBUF gpio63_iobuf (.IO(gpio63), .O(gpio_i[63]), .I(gpio_o[63]), .T(gpio_oe[63]));
`endif
`ifdef ARRAY_PERIPHERALS
	IOBUF gpio8_iobuf (.IO(gpio8), .O(gpio_i[8]), .I(gpio_o[8]), .T(gpio_oe[8]));//MATRIX COL
	IOBUF gpio9_iobuf (.IO(gpio9), .O(gpio_i[9]), .I(gpio_o[9]), .T(gpio_oe[9]));
	IOBUF gpio10_iobuf (.IO(gpio10), .O(gpio_i[10]), .I(gpio_o[10]), .T(gpio_oe[10]));
	IOBUF gpio11_iobuf (.IO(gpio11), .O(gpio_i[11]), .I(gpio_o[11]), .T(gpio_oe[11]));
	
	IOBUF gpio16_iobuf (.IO(gpio16), .O(gpio_i[16]), .I(gpio_o[16]), .T(gpio_oe[16]));//MATRIX ROW
	IOBUF gpio17_iobuf (.IO(gpio17), .O(gpio_i[17]), .I(gpio_o[17]), .T(gpio_oe[17]));
	IOBUF gpio18_iobuf (.IO(gpio18), .O(gpio_i[18]), .I(gpio_o[18]), .T(gpio_oe[18]));
	IOBUF gpio19_iobuf (.IO(gpio19), .O(gpio_i[19]), .I(gpio_o[19]), .T(gpio_oe[19]));
	
	IOBUF gpio32_iobuf (.IO(gpio32), .O(gpio_i[32]), .I(gpio_o[32]), .T(gpio_oe[32]));//LED_COL
	IOBUF gpio33_iobuf (.IO(gpio33), .O(gpio_i[33]), .I(gpio_o[33]), .T(gpio_oe[33]));
	IOBUF gpio34_iobuf (.IO(gpio34), .O(gpio_i[34]), .I(gpio_o[34]), .T(gpio_oe[34]));
	IOBUF gpio35_iobuf (.IO(gpio35), .O(gpio_i[35]), .I(gpio_o[35]), .T(gpio_oe[35]));
	IOBUF gpio36_iobuf (.IO(gpio36), .O(gpio_i[36]), .I(gpio_o[36]), .T(gpio_oe[36]));
	IOBUF gpio37_iobuf (.IO(gpio37), .O(gpio_i[37]), .I(gpio_o[37]), .T(gpio_oe[37]));
	IOBUF gpio38_iobuf (.IO(gpio38), .O(gpio_i[38]), .I(gpio_o[38]), .T(gpio_oe[38]));
	IOBUF gpio39_iobuf (.IO(gpio39), .O(gpio_i[39]), .I(gpio_o[39]), .T(gpio_oe[39]));
	
	IOBUF gpio41_iobuf (.IO(gpio41), .O(gpio_i[41]), .I(gpio_o[41]), .T(gpio_oe[41]));//LED_ROW
	IOBUF gpio40_iobuf (.IO(gpio40), .O(gpio_i[40]), .I(gpio_o[40]), .T(gpio_oe[40]));
	IOBUF gpio42_iobuf (.IO(gpio42), .O(gpio_i[42]), .I(gpio_o[42]), .T(gpio_oe[42]));
	IOBUF gpio43_iobuf (.IO(gpio43), .O(gpio_i[43]), .I(gpio_o[43]), .T(gpio_oe[43]));
	IOBUF gpio44_iobuf (.IO(gpio44), .O(gpio_i[44]), .I(gpio_o[44]), .T(gpio_oe[44]));
	IOBUF gpio45_iobuf (.IO(gpio45), .O(gpio_i[45]), .I(gpio_o[45]), .T(gpio_oe[45]));
	IOBUF gpio46_iobuf (.IO(gpio46), .O(gpio_i[46]), .I(gpio_o[46]), .T(gpio_oe[46]));
	IOBUF gpio47_iobuf (.IO(gpio47), .O(gpio_i[47]), .I(gpio_o[47]), .T(gpio_oe[47]));
`endif	

`ifdef Step_motor_PERIPHERALS
	IOBUF gpio12_iobuf (.IO(gpio12), .O(gpio_i[12]), .I(gpio_o[12]), .T(gpio_oe[12]));
	IOBUF gpio13_iobuf (.IO(gpio13), .O(gpio_i[13]), .I(gpio_o[13]), .T(gpio_oe[13]));
	IOBUF gpio14_iobuf (.IO(gpio14), .O(gpio_i[14]), .I(gpio_o[14]), .T(gpio_oe[14]));
	IOBUF gpio15_iobuf (.IO(gpio15), .O(gpio_i[15]), .I(gpio_o[15]), .T(gpio_oe[15]));
`endif


`ifdef UART_PERIPHERALS
	uart_top uart0_inst (
		.apb_pclk       (clk_ext32m     ),
		.apb_prstn      (rst_n          ),
		.apb_psel       (uart_psel      ),
		.apb_paddr      (uart_paddr     ),
		.apb_pwrite     (uart_pwrite    ),
		.apb_penable    (uart_penable   ),
		.apb_pwdata     (uart_pwdata    ),
		.apb_prdata     (uart_prdata    ),
		.apb_pready     (uart_pack      ),

		.uart_rx       (uart0_rx       ),
		.uart_tx       (uart0_tx       ),

		.uart_irq       (uart0_irq      )
	);
`endif

`ifdef INTC_PERIPHERALS
	// ------------------------------------------------------------------
	// 16 路 INTC 的扩展中断源（表 11-7）。没有对应实验模块时接 1'b0，
	// 由软件用 SET 寄存器强制置位来验证通路。
	// ------------------------------------------------------------------
	`ifdef EXP_SPI_STREAM
	assign spi_irq_exp = spi_stream_irq;     // 流式 SPI 走 int_2
	`else
	assign spi_irq_exp = spi_irq;
	`endif
	`ifdef EXP_KBD
	wire int_src_11 = kbd_irq;
	`else
	wire int_src_11 = 1'b0;
	`endif
	`ifdef EXP_DOT
	wire int_src_12 = dot_frame_irq;
	`else
	wire int_src_12 = 1'b0;
	`endif
	`ifdef EXP_SPI_STREAM
	wire int_src_13 = spi_stream_irq;
	`else
	wire int_src_13 = 1'b0;
	`endif
	wire int_src_8  = axi_dma_irq;
	wire int_src_9  = usb_irq;
	wire int_src_10 = axi_lcd_irq;
	wire int_src_14 = 1'b0;                  // 软件强制
	wire int_src_15 = 1'b0;                  // 软件强制

`ifdef EXP_INTC16
	// 实验一：16 路参数化中断控制器（替代 8 路 intc_top）
	intc_top16 intc_inst (
		.apb_pclk       (clk_ext32m     ),
		.apb_prstn      (rst_n          ),
		.apb_psel       (intc_psel      ),
		.apb_paddr      (intc_paddr     ),
		.apb_pwrite     (intc_pwrite    ),
		.apb_penable    (intc_penable   ),
		.apb_pwdata     (intc_pwdata    ),
		.apb_prdata     (intc_prdata    ),
		.apb_pready     (intc_pack      ),

		.int_in         ({int_src_15, int_src_14, int_src_13, int_src_12,
		                  int_src_11, int_src_10, int_src_9,  int_src_8,
		                  touch_irq,  btn_int[1],  btn_int[0], dma_irq,
		                  iic_irq,    spi_irq_exp, timer_irq, uart0_irq}),

		.intc_irq       (intc_irq       )
	);
`else
		intc_top intc_inst (
		.apb_pclk       (clk_ext32m     ),
		.apb_prstn      (rst_n          ),
		.apb_psel       (intc_psel      ),
		.apb_paddr      (intc_paddr     ),
		.apb_pwrite     (intc_pwrite    ),
		.apb_penable    (intc_penable   ),
		.apb_pwdata     (intc_pwdata    ),
		.apb_prdata     (intc_prdata    ),
		.apb_pready     (intc_pack      ),

//		.mul_sel		(mul_sel		),

		.int_0          (uart0_irq      ),
		.int_1          (timer_irq      ),
		.int_2          (spi_irq        ),
		.int_3          (iic_irq        ),
		.int_4          (dma_irq | axi_dma_irq),  // 原 APB DMA | 新 AXI DMAC
		.int_5          (btn_int[0]     ),
		.int_6          (btn_int[1]     ),
		.int_7          (touch_irq      ),

		.intc_irq       (intc_irq       )
	);
`endif
`endif

`ifdef TIMER_PERIPHERALS
	timer_top timer_inst (
		.apb_pclk       (clk_ext32m     ),
		.apb_prstn      (rst_n          ),
		.apb_psel       (timer_psel     ),
		.apb_paddr      (timer_paddr    ),
		.apb_pwrite     (timer_pwrite   ),
		.apb_penable    (timer_penable  ),
		.apb_pwdata     (timer_pwdata   ),
		.apb_prdata     (timer_prdata   ),
		.apb_pready     (timer_pack     ),

		.timer_irq      (timer_irq      )
	);
`endif


`ifdef IIC_PERIPHERALS

	wire [1:0] scl_i_u;
	wire [1:0] scl_o_u;
	wire [1:0] sda_i_u;
	wire [1:0] sda_o_u;
	wire scl_oen;
	wire sda_oen;
	IOBUF IIC_SCL_inst0(.IO(iic0_scl), .O(scl_i_u[0]), .I(scl_o_u[0]), .T(scl_oen));
	IOBUF IIC_SDA_inst0(.IO(iic0_sda), .O(sda_i_u[0]), .I(sda_o_u[0]), .T(sda_oen));
	IOBUF IIC_SCL_inst1(.IO(iic1_scl), .O(scl_i_u[1]), .I(scl_o_u[1]), .T(scl_oen));
	IOBUF IIC_SDA_inst1(.IO(iic1_sda), .O(sda_i_u[1]), .I(sda_o_u[1]), .T(sda_oen));

//	IOBUF IIC_SCL_inst2(.IO(iic2_scl), .O(scl_i_u[2]), .I(scl_o_u[2]), .T(scl_oen));
//	IOBUF IIC_SDA_inst2(.IO(iic2_sda), .O(sda_i_u[2]), .I(sda_o_u[2]), .T(sda_oen));


	iic_top iic_inst(
		.apb_pclk    (clk_ext32m    ),
		.apb_prstn   (rst_n   ),
		.apb_psel    (iic_psel    ),
		.apb_paddr   (iic_paddr   ),
		.apb_pwrite  (iic_pwrite  ),
		.apb_penable (iic_penable ),
		.apb_pwdata  (iic_pwdata  ),
		.apb_prdata  (iic_prdata  ),
		.apb_pready  (iic_pack  ),

		.scl_i_u     (scl_i_u     ),
		.scl_o_u     (scl_o_u     ),
		.sda_i_u     (sda_i_u     ),
		.sda_o_u     (sda_o_u     ),
		.scl_oen     (scl_oen     ),
		.sda_oen	 (sda_oen	  ),
		.iic_irq     (iic_irq     )
	);
`endif

`ifdef USB_PERIPHERALS
	usb_top usb_inst (
		.apb_pclk       (clk_ext32m     ),
		.apb_prstn      (rst_n          ),
		.apb_psel       (usb_psel       ),
		.apb_paddr      (usb_paddr      ),
		.apb_pwrite     (usb_pwrite     ),
		.apb_penable    (usb_penable    ),
		.apb_pwdata     (usb_pwdata     ),
		.apb_prdata     (usb_prdata     ),
		.apb_pready     (usb_pack       ),

		.usb_clk_60m    (usb_clk_60m	),
		.usb_rxf_n      (usb_rxf_n      ),
		.usb_txf_n      (usb_txf_n      ),
		.usb_oe_n       (usb_oe_n		),
		.usb_rd_n       (usb_rd_n       ),
		.usb_wr_n       (usb_wr_n       ),
		.usb_siwu_n     (usb_siwu_n     ),
		.usb_data       (usb_data       ),

		.usb_irq        (usb_irq        )
	);
`endif

wire [2:0] rgb_r;
wire [1:0] rgb_g;
wire [2:0] rgb_b;
wire lcd_rst_n;
`ifdef LCD_PERIPHERALS
	// ------------------------------------------------------------------
	// 原 APB 版 lcd_top 已移除 : LCD 时序发生与显存读取全部由
	// axi_subsys 里的 axi_lcd 完成 (见上面的 u_axi_subsys)。
	// 这里把 APB 槽位(0x5200_0000)做成"空设备":
	//   prdata = 0, pack = 1 (永远 ready)
	// 这样万一有旧软件(APB 版 lcd.c)误访问 0x5200_0000, 传输会立即
	// 完成并读到 0, 而不会因为 pready 恒 0 把 CPU 挂死。
	// lcd_id (16'h4384, 4.3" 800x480) 已在上方声明, 由 axi_subsys 驱动,
	// 供 touch_top 读取。
	// ------------------------------------------------------------------
	assign lcd_prdata = 32'h0;
	assign lcd_pack   = 1'b1;
`endif


`ifdef TOUCH_PERIPHERALS
	// 实验八用 touch_top_multi（GT911 多点 + 16×32 记录 FIFO）替代单点版本，
	// 两者端口完全一致，地址同为 0x3006_0000。
`ifdef EXP_TOUCH_MULTI
	touch_top_multi touch_inst (
`else
	touch_top touch_inst (
`endif
		.apb_pclk       (clk_ext32m      ),
		.apb_prstn      (rst_n           ),
		.apb_psel       (touch_psel      ),
		.apb_paddr      (touch_paddr     ),
		.apb_pwrite     (touch_pwrite    ),
		.apb_penable    (touch_penable   ),
		.apb_pwdata     (touch_pwdata    ),
		.apb_prdata     (touch_prdata    ),
		.apb_pready     (touch_pack      ),

		.lcd_id         (lcd_id          ),

		.touch_scl      (touch_scl       ),
		.touch_sda      (touch_sda       ),
		.touch_int      (touch_int       ),
		.touch_rst_n    (touch_rst_n     ),

		.touch_irq      (touch_irq       )
	);
`endif

`ifdef EXP_KBD
	// ------------------------------------------------------------------
	// 实验二/六：APB 矩阵键盘控制器 (0x3005_0000)
	//   行 gpio19~16 由本控制器驱动（低有效扫描）
	//   列 gpio11~8  由本控制器采样（板上上拉，按下为低）
	//   kbd_irq 接 INTC int_11（新键确认时出一个单拍脉冲）
	// ------------------------------------------------------------------
	apb_kbd kbd_inst (
		.apb_pclk       (clk_ext32m      ),
		.apb_prstn      (rst_n           ),
		.apb_psel       (kbd_psel        ),
		.apb_paddr      (kbd_paddr       ),
		.apb_pwrite     (kbd_pwrite      ),
		.apb_penable    (kbd_penable     ),
		.apb_pwdata     (kbd_pwdata      ),
		.apb_prdata     (kbd_prdata      ),
		.apb_pready     (kbd_pack        ),

		.kbd_row        (kbd_row         ),
		.kbd_col        (gpio_i[11:8]    ),
		.kbd_irq        (kbd_irq         )
	);
`endif

`ifdef EXP_DOT
	// ------------------------------------------------------------------
	// 实验七：LED 点阵显示控制器 (0x3007_0000)
	//   列数据 gpio39~32（高有效），行选 gpio47~40（低有效）
	//   dot_frame_irq 接 INTC int_12（每帧一个脉冲，约 1 kHz）
	// ------------------------------------------------------------------
	apb_dot dot_inst (
		.apb_pclk       (clk_ext32m      ),
		.apb_prstn      (rst_n           ),
		.apb_psel       (dot_psel        ),
		.apb_paddr      (dot_paddr       ),
		.apb_pwrite     (dot_pwrite      ),
		.apb_penable    (dot_penable     ),
		.apb_pwdata     (dot_pwdata      ),
		.apb_prdata     (dot_prdata      ),
		.apb_pready     (dot_pack        ),

		.dot_row        (dot_row         ),
		.dot_col        (dot_col         ),
		.dot_frame_irq  (dot_frame_irq   )
	);
`endif

`ifdef AUDIO_PERIPHERALS
	audio_top audio_inst (
		.apb_pclk       (clk_ext32m      ),
		.apb_prstn      (rst_n           ),
		.apb_psel       (audio_psel      ),
		.apb_paddr      (audio_paddr     ),
		.apb_pwrite     (audio_pwrite    ),                         
		.apb_penable    (audio_penable   ),
		.apb_pwdata     (audio_pwdata    ),
		.apb_prdata     (audio_prdata    ),
		.apb_pready     (audio_pack      ),

		.audio_bclk     (audio_bclk      ),
		.audio_adclrc   (audio_adclrc    ),
		.audio_adcdat   (audio_adcdat    ),
		.audio_daclrc   (audio_daclrc    ),
		.audio_dacdat   (audio_dacdat    )
	);
`endif

`ifdef PWM_PERIPHERALS
//	assign pwm2 = 1'b0;
	pwm_top pwm_inst (
		.apb_pclk       (clk_ext32m      ),
		.apb_prstn      (rst_n           ),
		.apb_psel       (pwm_psel        ),
		.apb_paddr      (pwm_paddr       ),
		.apb_pwrite     (pwm_pwrite      ),
		.apb_penable    (pwm_penable     ),
		.apb_pwdata     (pwm_pwdata      ),
		.apb_prdata     (pwm_prdata      ),
		.apb_pready     (pwm_pack        ),

		.pwm           ({pwm2,pwm1}      )
	);
`endif

`ifdef SPI_PERIPHERALS
    wire [1:0] spi_clk_in;
    wire [1:0] spi_mosi_in;
    wire [2:0] spi_miso_in;
    assign spi_miso_in = 3'b111;
    wire [1:0] spi_csn_in;
	// 实验五/九：流式 SPI 控制器（内部仍例化原 spi_top，只在其外层加
	// 采样定时器 + FIFO + DMA 搬运接口），地址同为 0x300A_0000。
`ifdef EXP_SPI_STREAM
	spi_stream_top spi_inst (
		.apb_pclk       (clk_ext32m      ),
		.apb_prstn      (rst_n           ),
		.apb_psel       (spi_psel        ),
		.apb_paddr      (spi_paddr       ),
		.apb_pwrite     (spi_pwrite      ),
		.apb_penable    (spi_penable     ),
		.apb_pwdata     (spi_pwdata      ),
		.apb_prdata     (spi_prdata      ),
		.apb_pready     (spi_pack        ),

		.spi_clk        ({spi_clk_in,spi_clk}),
		.spi_miso       ({spi_miso_in,spi_miso}),
		.spi_mosi       ({spi_mosi_in,spi_mosi}),
		.spi_csn        ({spi_csn_in,spi_csn}),
		.spi_mul        (spi_mul_s       ),

		.stream_irq     (spi_stream_irq  )
	);
`else
	spi_top spi_inst (
		.apb_pclk       (clk_ext32m      ),
		.apb_prstn      (rst_n           ),
		.apb_psel       (spi_psel        ),
		.apb_paddr      (spi_paddr       ),
		.apb_pwrite     (spi_pwrite      ),
		.apb_penable    (spi_penable     ),
		.apb_pwdata     (spi_pwdata      ),
		.apb_prdata     (spi_prdata      ),
		.apb_pready     (spi_pack        ),

		.spi_clk        ({spi_clk_in,spi_clk}),
		.spi_miso       ({spi_miso_in,spi_miso}),
		.spi_mosi       ({spi_mosi_in,spi_mosi}),
		.spi_csn        ({spi_csn_in,spi_csn}),

		.spi_irq		(spi_irq         )
	);
`endif
`endif

`ifdef ADC_9280_PERIPHERALS
	ADC_9280_apb ADC_9280_inst (
		.apb_pclk       (clk_ext32m      ),
		.apb_prstn      (rst_n           ),
		.apb_psel       (adc9280_psel      ),
		.apb_paddr      (adc9280_paddr     ),
		.apb_pwrite     (adc9280_pwrite    ),
		.apb_penable    (adc9280_penable   ),
		.apb_pwdata     (adc9280_pwdata    ),
		.apb_prdata     (adc9280_prdata    ),
		.apb_pready     (adc9280_pack      ),

		.adc_clk            (adc_clk       ),
		.adc_otr            (adc_otr      ),
		.adc_data           (adc_data      )
	);
`endif
`ifdef DAC_9708_PERIPHERALS
	dac_9708_top DAC_9708_inst (
		.apb_pclk       (clk_ext32m      ),
		.apb_prstn      (rst_n           ),
		.apb_psel       (dac9708_psel      ),
		.apb_paddr      (dac9708_paddr     ),
		.apb_pwrite     (dac9708_pwrite    ),
		.apb_penable    (dac9708_penable   ),
		.apb_pstrb      (dac9708_pstrb     ),
		.apb_pwdata     (dac9708_pwdata    ),
		.apb_prdata     (dac9708_prdata    ),
		.apb_pready     (dac9708_pack      ),

		.dac_clk            (dac_clk       ),
		.dac_data           (dac_data      )
	);
`endif


`ifdef FFT_PERIPHERALS
	apb_fft fft_inst (
		.apb_pclk   	(clk_ext32m      ),
		.apb_prstn  	(rst_n           ),
		.apb_psel   	(fft_psel        ),
		.apb_paddr  	(fft_paddr       ),
		.apb_pwrite 	(fft_pwrite      ),
		.apb_penable	(fft_penable     ),
		.apb_pwdata 	(fft_pwdata      ),
		.apb_prdata 	(fft_prdata      ),
		.apb_pready     (fft_pack        )
	);
`endif

`ifdef FIR_PERIPHERALS
	apb_fir fir_inst (
		.apb_pclk       (clk_ext32m      ),
		.apb_prstn      (rst_n           ),
		.apb_psel       (fir_psel        ),
		.apb_paddr      (fir_paddr       ),
		.apb_pwrite     (fir_pwrite      ),                         
		.apb_penable    (fir_penable     ),
		.apb_pwdata     (fir_pwdata      ),
		.apb_prdata     (fir_prdata      ),
		.apb_pready     (fir_pack        )
	);
`endif

`ifdef DMA_PERIPHERALS
	dma_top dma_inst (
		.pclk           (clk_ext32m      ),
		.prstn          (rst_n           ),

		.cfg_psel       (dma_psel        ),
		.cfg_paddr      (dma_paddr       ),
		.cfg_pwrite     (dma_pwrite      ),
		.cfg_penable    (dma_penable     ),
		.cfg_pwdata     (dma_pwdata      ),
		.cfg_prdata     (dma_prdata      ),
		.cfg_pready     (dma_pack        ),

		.dat_psel       (dma_m_psel      ),
		.dat_paddr      (dma_m_paddr     ),
		.dat_pstrb      (dma_m_pstrb     ),
		.dat_pwrite     (dma_m_pwrite    ),
		.dat_penable    (dma_m_penable   ),
		.dat_pwdata     (dma_m_pwdata    ),
		.dat_prdata     (dma_m_prdata    ),
		.dat_pready     (dma_m_pack      ),

		.dma_int        (dma_irq         )
	);
`endif
`ifdef RAM_PERIPHERALS
	apb_ram ram_inst (
		.apb_pclk       (clk_ext32m      ),
		.apb_prstn      (rst_n           ),
		.apb_psel       (ram_psel        ),
		.apb_paddr      (ram_paddr       ),
		.apb_pstrb      (ram_pstrb       ),
		.apb_pwrite     (ram_pwrite      ),                         
		.apb_penable    (ram_penable     ),
		.apb_pwdata     (ram_pwdata      ),
		.apb_prdata     (ram_prdata      ),
		.apb_pready     (ram_pack        )
	);
`endif
`ifdef RAM_64_32_PERIPHERALS
	APB_SRAM_64_32b ram_64_32_inst (
		.apb_pclk       (clk_ext32m      ),
		.apb_prstn      (rst_n           ),
		.apb_psel       (ram_64_32_psel        ),
		.apb_paddr      (ram_64_32_paddr       ),
		.apb_pwrite     (ram_64_32_pwrite      ),                         
		.apb_penable    (ram_64_32_penable     ),
		.apb_pwdata     (ram_64_32_pwdata      ),
		.apb_prdata     (ram_64_32_prdata      ),
		.apb_pready     (ram_64_32_pack        )
	);
`endif

`ifdef NOR_PERIPHERALS
  nor_top nor_inst(
    .apb_pclk    (clk_ext32m    ),
    .apb_prstn   (rst_n   ),

    .apb_psel    (nor_psel    ),
    .apb_paddr   (nor_paddr   ),
    .apb_pwrite  (nor_pwrite  ),
    .apb_penable (nor_penable ),
    .apb_pwdata  (nor_pwdata  ),
    .apb_prdata  (nor_prdata  ),
	.apb_pready  (nor_pack  ),

	.nor_addr    (nor_addr),
	.nor_data_in (nor_data_in),
	.nor_data_out(nor_data_out),

    .nor_cen     (nor_cen     ),
    .nor_oen     (nor_oen     ),
    .nor_wen     (nor_wen     ),
    .nor_wpn     (nor_wpn     ),
    .nor_rstn    (nor_rstn    ),
    .nor_byten   (nor_byten   ),
    .nor_rybyn   (nor_rybyn   )
);
`endif

`ifdef HDMI_PERIPHERALS
  HDMI_TOP hdmi_inst (
        .apb_pclk       (clk_ext32m      ),
        .apb_prstn      (rst_n           ),
        .apb_psel       (hdmi_psel       ),
        .apb_paddr      (hdmi_paddr      ),
        .apb_pwrite     (hdmi_pwrite     ),
        .apb_penable    (hdmi_penable    ),
        .apb_pwdata     (hdmi_pwdata     ),
        .apb_prdata     (hdmi_prdata     ),
		.apb_pready     (hdmi_pack       ),

        .pixel_data_sel      (pixel_data_sel        ),  // ��������APB���õ�ָʾ��

        .pixel_clk      (pixel_clk        ),
        .pixel_clk_5x   (pixel_clk_5x     ),
        .sys_rst_n      (rst_n            ),
        .tmds_clk_p     (tmds_clk_p       ),
        .tmds_clk_n     (tmds_clk_n       ),
        .tmds_data_p    (tmds_data_p      ),
        .tmds_data_n    (tmds_data_n      )
  );
`endif




endmodule
