`include "config.vh"
`include "apb_addr.svh"

module godson_mcu_cpu (
	input         clock,
	input         resetn,
	input 		  reset_clear,	

	output [`APB_SLAVE_NUM - 1 : 0]    periph_psel   ,
	output [32*`APB_SLAVE_NUM - 1 : 0] periph_paddr  ,
	output [ 4*`APB_SLAVE_NUM - 1 : 0] periph_pstrb  ,
	output [`APB_SLAVE_NUM - 1 : 0]    periph_pwrite ,
	output [`APB_SLAVE_NUM - 1 : 0]    periph_penable,
	output [32*`APB_SLAVE_NUM - 1 : 0] periph_pwdata ,
	input  [32*`APB_SLAVE_NUM - 1 : 0] periph_prdata ,
	input  [`APB_SLAVE_NUM - 1 : 0]    periph_pack   ,

	input           dma_psel   ,
	input  [31 : 0] dma_paddr  ,
	input  [ 3 : 0] dma_pstrb  ,
	input           dma_pwrite ,
	input           dma_penable,
	input  [31 : 0] dma_pwdata ,
	output [31 : 0] dma_prdata ,
	output          dma_pack   ,

	input           ljtag_trst_i,
	input           ljtag_tms_i ,
	output          ljtag_tdo_o ,
	input           ljtag_tdi_i ,
	input           ljtag_tck_i ,

	input  [5:0]    interrupt
	,
	output			pps_led,

	// ================================================================
	//  M0 : CPU 的 AXI 主口 (接到顶层 axi_interconnect 的主设备 0)
	// ================================================================
	output [`LID      - 1:0] m_awid    ,
	output [`LAWADDR  - 1:0] m_awaddr  ,
	output [`LAWLEN   - 1:0] m_awlen   ,
	output [`LAWSIZE  - 1:0] m_awsize  ,
	output [`LAWBURST - 1:0] m_awburst ,
	output [`LAWLOCK  - 1:0] m_awlock  ,
	output [`LAWCACHE - 1:0] m_awcache ,
	output [`LAWPROT  - 1:0] m_awprot  ,
	output                   m_awvalid ,
	input                    m_awready ,

	output [`LID      - 1:0] m_wid     ,
	output [`LWDATA   - 1:0] m_wdata   ,
	output [`LWSTRB   - 1:0] m_wstrb   ,
	output                   m_wlast   ,
	output                   m_wvalid  ,
	input                    m_wready  ,

	input  [`LID      - 1:0] m_bid     ,
	input  [`LBRESP   - 1:0] m_bresp   ,
	input                    m_bvalid  ,
	output                   m_bready  ,

	output [`LID      - 1:0] m_arid    ,
	output [`LARADDR  - 1:0] m_araddr  ,
	output [`LARLEN   - 1:0] m_arlen   ,
	output [`LARSIZE  - 1:0] m_arsize  ,
	output [`LARBURST - 1:0] m_arburst ,
	output [`LARLOCK  - 1:0] m_arlock  ,
	output [`LARCACHE - 1:0] m_arcache ,
	output [`LARPROT  - 1:0] m_arprot  ,
	output                   m_arvalid ,
	input                    m_arready ,

	input  [`LID      - 1:0] m_rid     ,
	input  [`LRDATA   - 1:0] m_rdata   ,
	input  [`LRRESP   - 1:0] m_rresp   ,
	input                    m_rlast   ,
	input                    m_rvalid  ,
	output                   m_rready  ,

	// ================================================================
	//  S0 : axi_interconnect 的从口 0, 回送到内部 axi2apb_bridge -> APB 外设
	// ================================================================
	input  [`LID      - 1:0] apb_s_awid    ,
	input  [`LAWADDR  - 1:0] apb_s_awaddr  ,
	input  [`LAWLEN   - 1:0] apb_s_awlen   ,
	input  [`LAWSIZE  - 1:0] apb_s_awsize  ,
	input  [`LAWBURST - 1:0] apb_s_awburst ,
	input  [`LAWLOCK  - 1:0] apb_s_awlock  ,
	input  [`LAWCACHE - 1:0] apb_s_awcache ,
	input  [`LAWPROT  - 1:0] apb_s_awprot  ,
	input                    apb_s_awvalid ,
	output                   apb_s_awready ,

	input  [`LID      - 1:0] apb_s_wid     ,
	input  [`LWDATA   - 1:0] apb_s_wdata   ,
	input  [`LWSTRB   - 1:0] apb_s_wstrb   ,
	input                    apb_s_wlast   ,
	input                    apb_s_wvalid  ,
	output                   apb_s_wready  ,

	output [`LID      - 1:0] apb_s_bid     ,
	output [`LBRESP   - 1:0] apb_s_bresp   ,
	output                   apb_s_bvalid  ,
	input                    apb_s_bready  ,

	input  [`LID      - 1:0] apb_s_arid    ,
	input  [`LARADDR  - 1:0] apb_s_araddr  ,
	input  [`LARLEN   - 1:0] apb_s_arlen   ,
	input  [`LARSIZE  - 1:0] apb_s_arsize  ,
	input  [`LARBURST - 1:0] apb_s_arburst ,
	input  [`LARLOCK  - 1:0] apb_s_arlock  ,
	input  [`LARCACHE - 1:0] apb_s_arcache ,
	input  [`LARPROT  - 1:0] apb_s_arprot  ,
	input                    apb_s_arvalid ,
	output                   apb_s_arready ,

	output [`LID      - 1:0] apb_s_rid     ,
	output [`LRDATA   - 1:0] apb_s_rdata   ,
	output [`LRRESP   - 1:0] apb_s_rresp   ,
	output                   apb_s_rlast   ,
	output                   apb_s_rvalid  ,
	input                    apb_s_rready
);

	// internal signal
	wire [`LID         -1 :0] cpu_awid;
	wire [`LAWADDR     -1 :0] cpu_awaddr;
	wire [`LAWLEN      -1 :0] cpu_awlen;
	wire [`LAWSIZE     -1 :0] cpu_awsize;
	wire [`LAWBURST    -1 :0] cpu_awburst;
	wire [`LAWLOCK     -1 :0] cpu_awlock;
	wire [`LAWCACHE    -1 :0] cpu_awcache;
	wire [`LAWPROT     -1 :0] cpu_awprot;
	wire                      cpu_awvalid;
	wire                      cpu_awready;
	wire [`LID         -1 :0] cpu_wid;
	wire [`LWDATA      -1 :0] cpu_wdata;
	wire [`LWSTRB      -1 :0] cpu_wstrb;
	wire                      cpu_wlast;
	wire                      cpu_wvalid;
	wire                      cpu_wready;
	wire [`LID         -1 :0] cpu_bid;
	wire [`LBRESP      -1 :0] cpu_bresp;
	wire                      cpu_bvalid;
	wire                      cpu_bready;
	wire [`LID         -1 :0] cpu_arid;
	wire [`LARADDR     -1 :0] cpu_araddr;
	wire [`LARLEN      -1 :0] cpu_arlen;
	wire [`LARSIZE     -1 :0] cpu_arsize;
	wire [`LARBURST    -1 :0] cpu_arburst;
	wire [`LARLOCK     -1 :0] cpu_arlock;
	wire [`LARCACHE    -1 :0] cpu_arcache;
	wire [`LARPROT     -1 :0] cpu_arprot;
	wire                      cpu_arvalid;
	wire                      cpu_arready;
	wire [`LID         -1 :0] cpu_rid;
	wire [`LRDATA      -1 :0] cpu_rdata;
	wire [`LRRESP      -1 :0] cpu_rresp;
	wire                      cpu_rlast;
	wire                      cpu_rvalid;
	wire                      cpu_rready;

	wire [`LID         -1 :0] apb_awid;
	wire [`LAWADDR     -1 :0] apb_awaddr;
	wire [`LAWLEN      -1 :0] apb_awlen;
	wire [`LAWSIZE     -1 :0] apb_awsize;
	wire [`LAWBURST    -1 :0] apb_awburst;
	wire [`LAWLOCK     -1 :0] apb_awlock;
	wire [`LAWCACHE    -1 :0] apb_awcache;
	wire [`LAWPROT     -1 :0] apb_awprot;
	wire                      apb_awvalid;
	wire                      apb_awready;
	wire [`LID         -1 :0] apb_wid;
	wire [`LWDATA      -1 :0] apb_wdata;
	wire [`LWSTRB      -1 :0] apb_wstrb;
	wire                      apb_wlast;
	wire                      apb_wvalid;
	wire                      apb_wready;
	wire [`LID         -1 :0] apb_bid;
	wire [`LBRESP      -1 :0] apb_bresp;
	wire                      apb_bvalid;
	wire                      apb_bready;
	wire [`LID         -1 :0] apb_arid;
	wire [`LARADDR     -1 :0] apb_araddr;
	wire [`LARLEN      -1 :0] apb_arlen;
	wire [`LARSIZE     -1 :0] apb_arsize;
	wire [`LARBURST    -1 :0] apb_arburst;
	wire [`LARLOCK     -1 :0] apb_arlock;
	wire [`LARCACHE    -1 :0] apb_arcache;
	wire [`LARPROT     -1 :0] apb_arprot;
	wire                      apb_arvalid;
	wire                      apb_arready;
	wire [`LID         -1 :0] apb_rid;
	wire [`LRDATA      -1 :0] apb_rdata;
	wire [`LRRESP      -1 :0] apb_rresp;
	wire                      apb_rlast;
	wire                      apb_rvalid;
	wire                      apb_rready;
	
	// ================================================================
	// 原 axi_mux 的 s1_* (第二路 AXI 从设备) 已删除 :
	//   本工程 CPU 只保留一路 AXI 主口 (m_*), 由顶层 axi_interconnect
	//   完成 3 主 x 4 从 的译码与仲裁; 从口 0 (apb_s_*) 回送到下面的
	//   axi2apb_bridge, 其余从设备 (AXI-DMAC / AXI-LCD / DDR3) 由
	//   axi_subsys 内部直连, 不再经 CPU 模块。
	// ================================================================

	wire                      apb_ack;
	wire                      apb_rw;
	wire                      apb_psel;
	wire                      apb_enab;
	wire [`ADDR_APB-1:0]      apb_addr;
	wire [3:0]                apb_strb;
	wire [`DATA_APB-1:0]      apb_datai;
	wire [`DATA_APB-1:0]      apb_datao;

	wire                      inst_sram_en;
	wire [ 3:0]               inst_sram_strb;
	wire [31:0]               inst_sram_wdata;
	wire [31:0]               inst_sram_rdata;
	wire                      inst_sram_wr;
	wire                      inst_sram_fetch;
	wire [31:0]               inst_sram_addr;
	wire                      inst_sram_rrdy = 1'b1;
	wire                      inst_sram_ack  = 1'b1;
	wire                      inst_sram_resp = 1'b0;
	wire                      inst_ram_clk = clock;

	wire                      data_sram_en;
	wire [ 3:0]               data_sram_strb;
	wire [31:0]               data_sram_wdata;
	wire [31:0]               data_sram_rdata;
	wire                      data_sram_wr;
	wire                      data_sram_fetch;
	wire [31:0]               data_sram_addr;
	wire                      data_sram_ack = 1'b1;
	wire                      data_sram_rrdy = 1'b1;
	wire                      data_sram_resp = 1'b0;
	wire                      data_ram_clk = clock;
	
	Flash_128k A_flash (
		.CLKin            (inst_ram_clk          ),
		.DO               (inst_sram_rdata       ),
		.AD               (inst_sram_addr        ),
		.STRB             (inst_sram_strb        ),
		.DI               (inst_sram_wdata       ),
		.EN               (inst_sram_en          ),
		.R_WB             (inst_sram_wr          ),
		.rst_n            (reset_clear           )
	);
	
	Dram_8k A_dram (
		.CLKin            (data_ram_clk          ),
		.DO               (data_sram_rdata       ),
		.AD               (data_sram_addr        ),
		.STRB             (data_sram_strb        ),
		.DI               (data_sram_wdata       ),
		.EN               (data_sram_en          ),
		.R_WB             (data_sram_wr          ),
		.rst_n            (reset_clear           )
	);

	wire sleeping_o;
	wire [31:0] fetch_pc;
	wire [31:0] debug_pc;

	//pps_led
	reg [24:0] cnt;
	reg [31:0] prev_fetch_pc; 
	always @(posedge clock or negedge resetn) begin                                    
			if(!resetn) begin
				cnt <= 0;
            	prev_fetch_pc <= 0;
			end
		else begin
            if (fetch_pc != prev_fetch_pc) begin
                cnt <= cnt + 1;
			end
			prev_fetch_pc <= fetch_pc; 
		end
	end
	assign pps_led = cnt[24];

   	// la132
	//-----------------------------------------------------------------
	//  !! 2026-11-04 修复：Vivado project 流程下 boot_pc 悬空 -> PC=0 !!
	//-----------------------------------------------------------------
	//  现象: 用 Vivado project 方式建工程综合时, la132_top 是 blackbox
	//  (LA132/la132_top.v 空壳带 syn_black_box 属性)。综合器把实例上
	//  直连的常数输入 (boot_pc / mode_lisa / inst_xor / nmi) 优化掉,
	//  不生成 net; 实现阶段链接 la132_top.edf 时这些引脚全部悬空 ->
	//  CPU 复位后启动地址 = 0 -> PC=0, 程序永远跑不起来。
	//  而 np_build 流程 read_edif 在前 (同名时网表优先), 常数连接
	//  完整保留, 所以一直没暴露。
	//  修法: 常数先落到带 dont_touch 的 wire 上, 再接进实例, 并给
	//  实例本身加 dont_touch, 强制综合器保留这些连接。
	//-----------------------------------------------------------------
	(* dont_touch = "true" *) wire        mode_lisa_c = 1'b1;
	(* dont_touch = "true" *) wire [31:0] inst_xor_c  = 32'b0;
	(* dont_touch = "true" *) wire [31:0] boot_pc_c   = 32'h1c000000;
	(* dont_touch = "true" *) wire        nmi_c       = 1'b0;

	(* dont_touch = "true" *) la132_top A_la132 (
		.boot_pc          (boot_pc_c           ),
		.clk              (clock               ),
		.clk_count        (clock               ),
		.hard_resetn      (reset_clear         ),
		.soft_resetn      (resetn              ),

		.sleeping         (sleeping_o          ),
		.can_high_freq    (                    ),
		.cpu_debug_mode   (                    ),
		.cpu_fetch_pc     (fetch_pc            ),
		.wb_pc            (debug_pc            ),
		.mode_lisa        (mode_lisa_c         ),
		.inst_xor         (inst_xor_c          ),

		.nmi              (nmi_c               ),
		.ext_int          (interrupt           ),

		.arid             (cpu_arid[3:0]       ),
		.araddr           (cpu_araddr          ),
		.arlen            (cpu_arlen           ),
		.arsize           (cpu_arsize          ),
		.arburst          (cpu_arburst         ),
		.arlock           (cpu_arlock          ),
		.arcache          (cpu_arcache         ),
		.arprot           (cpu_arprot          ),
		.arvalid          (cpu_arvalid         ),
		.arready          (cpu_arready         ),

		.rid              (cpu_rid[3:0]        ),
		.rdata            (cpu_rdata           ),
		.rresp            (cpu_rresp           ),
		.rlast            (cpu_rlast           ),
		.rvalid           (cpu_rvalid          ),
		.rready           (cpu_rready          ),

		.awid             (cpu_awid[3:0]       ),
		.awaddr           (cpu_awaddr          ),
		.awlen            (cpu_awlen           ),
		.awsize           (cpu_awsize          ),
		.awburst          (cpu_awburst         ),
		.awlock           (cpu_awlock          ),
		.awcache          (cpu_awcache         ),
		.awprot           (cpu_awprot          ),
		.awvalid          (cpu_awvalid         ),
		.awready          (cpu_awready         ),

		.wid              (cpu_wid[3:0]        ),
		.wdata            (cpu_wdata           ),
		.wstrb            (cpu_wstrb           ),
		.wlast            (cpu_wlast           ),
		.wvalid           (cpu_wvalid          ),
		.wready           (cpu_wready          ),

		.bid              (cpu_bid[3:0]        ),
		.bresp            (cpu_bresp           ),
		.bvalid           (cpu_bvalid          ),
		.bready           (cpu_bready          ),

		.inst_sram_en     (inst_sram_en        ),
		.inst_sram_wr     (inst_sram_wr        ),
		.inst_sram_fetch  (inst_sram_fetch     ),
		.inst_sram_strb   (inst_sram_strb      ),
		.inst_sram_addr   (inst_sram_addr      ),
		.inst_sram_wdata  (inst_sram_wdata     ),
		.inst_sram_rdata  (inst_sram_rdata     ),
		.inst_sram_ack    (inst_sram_ack       ),
		.inst_sram_rrdy   (inst_sram_rrdy      ),
		.inst_sram_resp   (inst_sram_resp      ),

		.data_sram_en     (data_sram_en        ),
		.data_sram_wr     (data_sram_wr        ),
		.data_sram_fetch  (data_sram_fetch     ),
		.data_sram_strb   (data_sram_strb      ),
		.data_sram_addr   (data_sram_addr      ),
		.data_sram_wdata  (data_sram_wdata     ),
		.data_sram_rdata  (data_sram_rdata     ),
		.data_sram_ack    (data_sram_ack       ),
		.data_sram_rrdy   (data_sram_rrdy      ),
		.data_sram_resp   (data_sram_resp      ),

		.trstn            (ljtag_trst_i        ),
		.tck              (ljtag_tck_i         ),
		.tdi              (ljtag_tdi_i         ),
		.tms              (ljtag_tms_i         ),
		.tdo              (ljtag_tdo_o         ),
		.ljtag_prrst      (ljtag_prrst_src     ),
		.ljtag_lock       (1'b0                ),

		.prid_revision    (4'd0                ),
		.cpunum           (10'b0               ),

		.ibus0_valid      (1'b1                ),
		.ibus0_base       (32'h1c00_0000       ), // va: 1c00_0000 & bfc0_0000
		.ibus0_mask       (32'h1f00_0000       ), // flash 128K, + 4 special page
		.ibus1_valid      (1'b1                ),
		.ibus1_base       (32'h9f00_0000       ), // va: 9fR0_0000 & bf00_0000
		.ibus1_mask       (32'hdff0_0000       ),
		.ibus2_valid      (1'b0                ), // flash_en
		.ibus2_base       (32'h9fe6_0000       ), // va: 9fe6_0000 & bfe6_0000
		.ibus2_mask       (32'hdfff_ff00       ),
		.ibus3_valid      (1'b0                ), // compact_mem&flash_en),
		.ibus3_base       (32'h8000_3000       ), // for va: 8000_30xx & 0000_00xx -> pa: 0000_30xx & 4000_00xx
		.ibus3_mask       (32'h7fff_ff00       ),
		.dbus0_valid      (1'b1                ),
		.dbus0_base       (32'h8000_0000       ),
		.dbus0_mask       (32'hdfff_c000       ), // 8K byte, for va: 8000_0000 & a000_0000 -> pa: 0000_0000
		.dbus1_valid      (1'b1                ),
		.dbus1_base       (32'h0000_0000       ),
		.dbus1_mask       (32'hffff_e000       ), // 8K byte, for va: 0000_0000             -> pa: 0000_0000
		.dbus2_valid      (1'b0                ), // unused
		.dbus2_base       (32'h0000_0000       ),
		.dbus2_mask       (32'h0000_0000       ),
		.dbus3_valid      (1'b0                ), // unused
		.dbus3_base       (32'h0000_0000       ),
		.dbus3_mask       (32'h0000_0000       ),

		.test_mode        (1'b0                )
	);


	// ================================================================
	//  M0 : la132_top 的 AXI 主口 (cpu_*) -> 顶层 AXI 主口 (m_*)
	//  S0 : 顶层 AXI 从口 (apb_s_*) -> 内部 AXI 从口 (apb_*) -> axi2apb_bridge
	// ================================================================
	assign m_awid     = cpu_awid     ;   assign cpu_awready  = m_awready  ;
	assign m_awaddr   = cpu_awaddr   ;   assign cpu_wready   = m_wready   ;
	assign m_awlen    = cpu_awlen    ;   assign cpu_bid      = m_bid      ;
	assign m_awsize   = cpu_awsize   ;   assign cpu_bresp    = m_bresp    ;
	assign m_awburst  = cpu_awburst  ;   assign cpu_bvalid   = m_bvalid   ;
	assign m_awlock   = cpu_awlock   ;   assign m_bready     = cpu_bready ;
	assign m_awcache  = cpu_awcache  ;   assign cpu_arready  = m_arready  ;
	assign m_awprot   = cpu_awprot   ;   assign cpu_rid      = m_rid      ;
	assign m_awvalid  = cpu_awvalid  ;   assign cpu_rdata    = m_rdata    ;
	assign m_wid      = cpu_wid      ;   assign cpu_rresp    = m_rresp    ;
	assign m_wdata    = cpu_wdata    ;   assign cpu_rlast    = m_rlast    ;
	assign m_wstrb    = cpu_wstrb    ;   assign cpu_rvalid   = m_rvalid   ;
	assign m_wlast    = cpu_wlast    ;   assign m_rready     = cpu_rready ;
	assign m_wvalid   = cpu_wvalid   ;
	assign m_arid     = cpu_arid     ;
	assign m_araddr   = cpu_araddr   ;
	assign m_arlen    = cpu_arlen    ;
	assign m_arsize   = cpu_arsize   ;
	assign m_arburst  = cpu_arburst  ;
	assign m_arlock   = cpu_arlock   ;
	assign m_arcache  = cpu_arcache  ;
	assign m_arprot   = cpu_arprot   ;
	assign m_arvalid  = cpu_arvalid  ;

	assign apb_awid     = apb_s_awid    ;   assign apb_s_awready = apb_awready;
	assign apb_awaddr   = apb_s_awaddr  ;   assign apb_s_wready  = apb_wready ;
	assign apb_awlen    = apb_s_awlen   ;   assign apb_s_bid     = apb_bid    ;
	assign apb_awsize   = apb_s_awsize  ;   assign apb_s_bresp   = apb_bresp  ;
	assign apb_awburst  = apb_s_awburst ;   assign apb_s_bvalid  = apb_bvalid ;
	assign apb_awlock   = apb_s_awlock  ;   assign apb_bready    = apb_s_bready;
	assign apb_awcache  = apb_s_awcache ;   assign apb_s_arready = apb_arready;
	assign apb_awprot   = apb_s_awprot  ;   assign apb_s_rid     = apb_rid    ;
	assign apb_awvalid  = apb_s_awvalid ;   assign apb_s_rdata   = apb_rdata  ;
	assign apb_wid      = apb_s_wid     ;   assign apb_s_rresp   = apb_rresp  ;
	assign apb_wdata    = apb_s_wdata   ;   assign apb_s_rlast   = apb_rlast  ;
	assign apb_wstrb    = apb_s_wstrb   ;   assign apb_s_rvalid  = apb_rvalid ;
	assign apb_wlast    = apb_s_wlast   ;   assign apb_rready    = apb_s_rready;
	assign apb_wvalid   = apb_s_wvalid  ;
	assign apb_arid     = apb_s_arid    ;
	assign apb_araddr   = apb_s_araddr  ;
	assign apb_arlen    = apb_s_arlen   ;
	assign apb_arsize   = apb_s_arsize  ;
	assign apb_arburst  = apb_s_arburst ;
	assign apb_arlock   = apb_s_arlock  ;
	assign apb_arcache  = apb_s_arcache ;
	assign apb_arprot   = apb_s_arprot  ;
	assign apb_arvalid  = apb_s_arvalid ;

	// axi2apb
	axi2apb_bridge A_axi2apb (
		.clk              (clock               ),
		.rst_n            (resetn              ),

		.axi_s_awid       (apb_awid            ),
		.axi_s_awaddr     (apb_awaddr          ),
		.axi_s_awlen      (apb_awlen           ),
		.axi_s_awsize     (apb_awsize          ),
		.axi_s_awburst    (apb_awburst         ),
		.axi_s_awlock     (apb_awlock          ),
		.axi_s_awcache    (apb_awcache         ),
		.axi_s_awprot     (apb_awprot          ),
		.axi_s_awvalid    (apb_awvalid         ),
		.axi_s_awready    (apb_awready         ),
		.axi_s_wid        (apb_wid             ),
		.axi_s_wdata      (apb_wdata           ),
		.axi_s_wstrb      (apb_wstrb           ),
		.axi_s_wlast      (apb_wlast           ),
		.axi_s_wvalid     (apb_wvalid          ),
		.axi_s_wready     (apb_wready          ),
		.axi_s_bid        (apb_bid             ),
		.axi_s_bresp      (apb_bresp           ),
		.axi_s_bvalid     (apb_bvalid          ),
		.axi_s_bready     (apb_bready          ),
		.axi_s_arid       (apb_arid            ),
		.axi_s_araddr     (apb_araddr          ),
		.axi_s_arlen      (apb_arlen           ),
		.axi_s_arsize     (apb_arsize          ),
		.axi_s_arburst    (apb_arburst         ),
		.axi_s_arlock     (apb_arlock          ),
		.axi_s_arcache    (apb_arcache         ),
		.axi_s_arprot     (apb_arprot          ),
		.axi_s_arvalid    (apb_arvalid         ),
		.axi_s_arready    (apb_arready         ),
		.axi_s_rid        (apb_rid             ),
		.axi_s_rdata      (apb_rdata           ),
		.axi_s_rresp      (apb_rresp           ),
		.axi_s_rlast      (apb_rlast           ),
		.axi_s_rvalid     (apb_rvalid          ),
		.axi_s_rready     (apb_rready          ),

		.apb_valid_cpu    (apb_valid           ),
		.apb_clk          (                    ),
		.apb_reset_n      (apb_reset_n         ),
		.reg_psel         (apb_psel            ),
		.reg_enable       (apb_enab            ),
		.reg_rw           (apb_rw              ),
		.reg_addr         (apb_addr            ),
		.reg_strb         (apb_strb            ),
		.reg_datai        (apb_datai           ),
		.reg_ready_1      (apb_ack             ),
		.reg_datao        (apb_datao           )
	);

	apb_bridge #(
		.N_MASTER(2   ),
		.N_SLAVE (`APB_SLAVE_NUM),
		.W_DATA  (32  ),
		.W_ADDR  (32  )
	) A_apb_mux_cpu (
		.apb_clk   (clock    ),   // 2026-10-31: 原来悬空, 导致桥内超时计数器无时钟
		.apb_rstn  (resetn   ),
		.m_psel    ({dma_psel   , apb_psel }),
		.m_paddr   ({dma_paddr  , apb_addr }),
		.m_pstrb   ({dma_pstrb  , apb_strb }),
		.m_pwrite  ({dma_pwrite , apb_rw   }),
		.m_penable ({dma_penable, apb_enab }),
		.m_pwdata  ({dma_pwdata , apb_datai}),
		.m_prdata  ({dma_prdata , apb_datao}),
		.m_pready  ({dma_pack   , apb_ack  }),
		
		.s_psel    (periph_psel   ),
		.s_paddr   (periph_paddr  ),
		.s_pstrb   (periph_pstrb  ),
		.s_pwrite  (periph_pwrite ),
		.s_penable (periph_penable),
		.s_pwdata  (periph_pwdata ),
		.s_prdata  (periph_prdata ),
		.s_pready  (periph_pack   )
	);

endmodule // godson_mcu_cpu



module Dram_8k (DO, AD, STRB, CLKin, DI, EN, R_WB, rst_n);

    parameter NB = 32;  // Number of Data Bits
    parameter NA = 32;  // Number of Address Bits
    parameter NW = 512; // Number of WORDS 4*2048=8KB

    output [(NB - 1):0] DO;
    input [(NB - 1):0] DI;
    input [      3 :0] STRB;
    input [(NA - 1):0] AD;
    input EN;
    input R_WB;
    input CLKin;
	input rst_n;

	reg [14:0] reset_addr; 
	reg reset_done;
	reg reset_en;

    wire [3:0] wea = reset_en ? 4'b1111 : ({4{R_WB}} & STRB);
	wire [14:0] mem_addr = reset_en ? reset_addr : (AD[(NA - 1):2]);
	wire [31:0] mem_data = reset_en ? 32'h00000000 : DI;

    always @(posedge CLKin or negedge rst_n) begin
        if (!rst_n) begin
            reset_addr <= 30'h20000000;
            reset_done <= 0;
            reset_en <= 1;
        end else if (reset_en) begin
            if (reset_addr < NW) begin
                reset_addr <= reset_addr + 1;
            end else begin
                reset_done <= 1;
                reset_en <= 0; // 夝佝完戝，杢夝�?�常读写
            end
        end
    end
    blk_mem_gen_1 ram_8k_inst ( 
		.clka  (CLKin         ),
		.ena   (EN            ),
		.wea   (wea           ),
		// .addra (AD[(NA - 1):2]),
		.addra (mem_addr	  ),
		.dina  (mem_data      ),
		.douta (DO            )
    );

endmodule

module Flash_128k (DO, AD, STRB, CLKin, DI, EN, R_WB, rst_n);    

    parameter NB = 32;   // Number of Data Bits
    parameter NA = 32;   // Number of Address Bits
    parameter NW = 512;

    output [(NB - 1):0] DO;
    input [(NB - 1):0] DI;
    input [      3 :0] STRB;
    input [(NA - 1):0] AD;
    input EN;
    input R_WB;
    input CLKin;
	input rst_n;

	//=================================================================
	//  !! 2026-10-30 修复：删掉"复位后清零前 2KB flash"的状态机 !!
	//-----------------------------------------------------------------
	//  原代码在 rst_n(=reset_clear) 有效后，会让 reset_en=1 并把
	//  mem_addr 强制切到 reset_addr(0,1,2,...511)，wea 强制 4'b1111，
	//  也就是把 0x1C000000 起 512 个字(2KB)清成 0 —— 而这段正是
	//  异常向量表 + _start，是 CPU 复位后要取的第一段代码。
	//  更致命的是它和取指抢同一个 BRAM 端口：reset_clear 一释放，
	//  CPU 开始取指的同时清零机也在写同一批地址 → 取到 0x00000000
	//  → 非法指令 → 异常循环(IE 被硬件清零) → LALINK 再也 halt 不
	//  住内核 → 之后每次烧写都报 "Failed to enter Debug Mode"。
	//  另外 reset_addr 只有 15 位，`30'h7000000` 会被截断成 0，
	//  说明这行本来就被改写坏了。
	//  flash 在本工程是 blk_mem_gen_0(BRAM)，掉电/重下 bit 流本来
	//  就会由 coe/apb_write.coe 重新装载，完全不需要在复位时清空。
	//  如需恢复旧行为，把下面 wire 改回带 reset_en 的写法并把
	//  always 块取消注释即可。
	//=================================================================
	reg [14:0] reset_addr; 
	reg reset_done;
	reg reset_en;

    wire [3:0] wea = ({4{R_WB}} & STRB);
	wire [14:0] mem_addr = (AD[(NA - 1):2]);
	wire [31:0] mem_data = DI;

    // always @(posedge CLKin or negedge rst_n) begin
    //     if (!rst_n) begin
    //         reset_addr <= 15'b0;
    //         reset_done <= 0;
    //         reset_en <= 1;
    //     end else if (reset_en) begin
    //         if (reset_addr < NW) begin
    //             reset_addr <= reset_addr + 1;
    //         end else begin
    //             reset_done <= 1;
    //             reset_en <= 0;
    //         end
    //     end
    // end

    blk_mem_gen_0 flash_128k_inst ( 
		.clka  (CLKin         ),
		.ena   (EN            ),
		.wea   (wea           ),
		// .addra (AD[(NA - 1):2]),
		// .addra ({0, 0, AD[(NA - 1):2]}), // for simulation
		.addra (mem_addr	  ),
		.dina  (mem_data      ),
		.douta (DO            )
    );

endmodule