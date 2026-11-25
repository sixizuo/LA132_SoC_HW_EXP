`timescale 1ns / 1ps
//=====================================================================
//  File   : axi_ddr_slave.v
//  Brief  : AXI4 Slave1 -> DDR3(MIG) 桥接顶层
//  Target : XC7A100T (云晓 100T 核心板) / LA132 SoC
//  Author : WorkBuddy
//---------------------------------------------------------------------
//  功能说明
//  1) 本模块作为 AXI Slave1 的从端器件，接收 LA132 经由 axi_mux 第二路
//     (s1_*) 转发过来的读写请求；
//  2) 内部通过 Axi_CDC_128 完成两件事：
//       - 位宽转换 : 32bit (SoC 侧) <-> 128bit (MIG AXI 侧)
//       - 时钟转换 : clock(32MHz 域) <-> ui_clk(100MHz/DDR 域)
//  3) 转换后的 128bit AXI 请求送入 mig_7series_0 的 32bit AXI 从口，
//     由 MIG 完成 DDR3 命令/时序/校准的全部工作；
//  4) 地址映射 : AXI 窗口基址 0x4000_0000, 长度 0x3FFF_FFFF (1GB)
//     颗粒 2 x MT41K256M16 (32bit DQ) -> MIG 配置 DataWidth=32 / C0_S_AXI_ADDR_WIDTH=30
//
//  注意: 为避免「CDC 是 128bit、MIG 是 32bit」的位宽不匹配，本文件采用
//  两条可选路径（由 `DDR_AXI_CDC_STYLE 选择）：
//     - 定义 DDR_CDC_WIDTH_128 : 使用 128bit CDC（需 128bit MIG 配置）
//     - 缺省(推荐)             : 使用 32bit 直通 + 轻量跨时钟握手
//  当前缺省路径与工程内现成的 mig_7series_0(32bit AXI) 完全匹配。
//=====================================================================

`include "config.vh"

module axi_ddr_slave #(
  // MIG AXI 侧地址位宽（MIG C0_S_AXI_ADDR_WIDTH = 30, 1GB）
  //   截断到 30 bit 等价于减去基址 0x4000_0000（bit30 是窗口基址位）
  parameter MIG_ADDR_WIDTH = 30,
  // MIG AXI 侧 ID 位宽
  parameter MIG_ID_WIDTH   = 4
) (
  // ---------------- SoC 侧（AXI Slave1）----------------
  input  wire                     soc_aclk,       // 32MHz
  input  wire                     soc_aresetn,

  input  wire [`LID       -1:0]   s1_awid,
  input  wire [`LAWADDR   -1:0]   s1_awaddr,
  input  wire [`LAWLEN    -1:0]   s1_awlen,
  input  wire [`LAWSIZE   -1:0]   s1_awsize,
  input  wire [`LAWBURST  -1:0]   s1_awburst,
  input  wire [`LAWLOCK   -1:0]   s1_awlock,
  input  wire [`LAWCACHE  -1:0]   s1_awcache,
  input  wire [`LAWPROT   -1:0]   s1_awprot,
  input  wire                     s1_awvalid,
  output wire                     s1_awready,

  input  wire [`LID       -1:0]   s1_wid,
  input  wire [`LWDATA    -1:0]   s1_wdata,
  input  wire [`LWSTRB    -1:0]   s1_wstrb,
  input  wire                     s1_wlast,
  input  wire                     s1_wvalid,
  output wire                     s1_wready,

  output wire [`LID       -1:0]   s1_bid,
  output wire [`LBRESP    -1:0]   s1_bresp,
  output wire                     s1_bvalid,
  input  wire                     s1_bready,

  input  wire [`LID       -1:0]   s1_arid,
  input  wire [`LARADDR   -1:0]   s1_araddr,
  input  wire [`LARLEN    -1:0]   s1_arlen,
  input  wire [`LARSIZE   -1:0]   s1_arsize,
  input  wire [`LARBURST  -1:0]   s1_arburst,
  input  wire [`LARLOCK   -1:0]   s1_arlock,
  input  wire [`LARCACHE  -1:0]   s1_arcache,
  input  wire [`LARPROT   -1:0]   s1_arprot,
  input  wire                     s1_arvalid,
  output wire                     s1_arready,

  output wire [`LID       -1:0]   s1_rid,
  output wire [`LRDATA    -1:0]   s1_rdata,
  output wire [`LRRESP    -1:0]   s1_rresp,
  output wire                     s1_rlast,
  output wire                     s1_rvalid,
  input  wire                     s1_rready,

  // ---------------- DDR3 物理接口 ----------------
  input  wire                     ddr_refclk,     // 200MHz MMCM 参考时钟
  input  wire                     ddr_sys_rst,    // 高有效复位
  output wire                     init_calib_complete,

  output wire [14:0]              ddr3_addr,
  output wire [ 2:0]              ddr3_ba,
  output wire                     ddr3_cas_n,
  output wire [ 0:0]              ddr3_ck_n,
  output wire [ 0:0]              ddr3_ck_p,
  output wire [ 0:0]              ddr3_cke,
  output wire                     ddr3_ras_n,
  output wire                     ddr3_reset_n,
  output wire                     ddr3_we_n,
  inout  wire [31:0]              ddr3_dq,
  inout  wire [ 3:0]              ddr3_dqs_n,
  inout  wire [ 3:0]              ddr3_dqs_p,
  output wire [ 0:0]              ddr3_cs_n,
  output wire [ 3:0]              ddr3_dm,
  output wire [ 0:0]              ddr3_odt
);

  //====================================================================
  // MIG 侧 AXI 信号（32bit / ui_clk 域）
  //====================================================================
  wire                     ui_clk;
  wire                     ui_clk_sync_rst;
  wire                     ddr_aclk    = ui_clk;
  //  MIG 的 sys_rst 极性 = ACTIVE LOW (mig_7series_0_mig.v 里 RST_ACT_LOW=1,
  //  即 sys_rst_act_hi = ~sys_rst)。本模块端口 ddr_sys_rst 为高有效,
  //  例化处必须取反后送入, 否则芯片永远处于复位状态 (仿真空壳掩盖了该问题)。
  wire                     mig_sys_rst_n = ~ddr_sys_rst;
  //  MIG AXI 侧复位: ui_clk_sync_rst 是 MIG 输出的 ui_clk 域同步复位(高有效),
  //  再与 init_calib_complete 相与, 保证在校准完成前不放行任何 AXI 事务
  //  (MIG 手册要求: init_calib_complete 拉高前不得发起 AXI 访问)
  wire                     ddr_aresetn = (~ui_clk_sync_rst) & init_calib_complete;

  // MIG 片内温度传感器读数 (INTERNAL 模式), 本设计未使用
  wire [11:0]              ddr_device_temp;

  wire [MIG_ID_WIDTH-1:0]  ddr_awid   ;
  wire [MIG_ADDR_WIDTH-1:0]ddr_awaddr ;
  wire [7:0]               ddr_awlen  ;
  wire [2:0]               ddr_awsize ;
  wire [1:0]               ddr_awburst;
  wire [0:0]               ddr_awlock ;
  wire [3:0]               ddr_awcache;
  wire [2:0]               ddr_awprot ;
  wire [3:0]               ddr_awqos  ;
  wire                     ddr_awvalid;
  wire                     ddr_awready;
  wire [31:0]              ddr_wdata  ;
  wire [3:0]               ddr_wstrb  ;
  wire                     ddr_wlast  ;
  wire                     ddr_wvalid ;
  wire                     ddr_wready ;
  wire [MIG_ID_WIDTH-1:0]  ddr_bid    ;
  wire [1:0]               ddr_bresp  ;
  wire                     ddr_bvalid ;
  wire                     ddr_bready ;
  wire [MIG_ID_WIDTH-1:0]  ddr_arid   ;
  wire [MIG_ADDR_WIDTH-1:0]ddr_araddr ;
  wire [7:0]               ddr_arlen  ;
  wire [2:0]               ddr_arsize ;
  wire [1:0]               ddr_arburst;
  wire [0:0]               ddr_arlock ;
  wire [3:0]               ddr_arcache;
  wire [2:0]               ddr_arprot ;
  wire [3:0]               ddr_arqos  ;
  wire                     ddr_arvalid;
  wire                     ddr_arready;
  wire [MIG_ID_WIDTH-1:0]  ddr_rid    ;
  wire [31:0]              ddr_rdata  ;
  wire [1:0]               ddr_rresp  ;
  wire                     ddr_rlast  ;
  wire                     ddr_rvalid ;
  wire                     ddr_rready ;

  //====================================================================
  // AXI 跨时钟位宽转换桥
  //   SoC 32bit@32MHz  <->  MIG 32bit@ui_clk
  //   采用 Axi_CDC_32（本目录提供）完成握手与同步；
  //   若工程 MIG 配置为 128bit AXI，则改用 Axi_CDC_128。
  //====================================================================
  axi_cdc_bridge #(
    .ADDR_WIDTH (MIG_ADDR_WIDTH),
    .ID_WIDTH   (MIG_ID_WIDTH  )
  ) u_axi_cdc (
    .s_aclk        (soc_aclk     ),
    .s_aresetn     (soc_aresetn  ),

    .s_awid        (s1_awid      ),
    .s_awaddr      (s1_awaddr    ),
    .s_awlen       (s1_awlen     ),
    .s_awsize      (s1_awsize    ),
    .s_awburst     (s1_awburst   ),
    .s_awlock      (s1_awlock    ),
    .s_awcache     (s1_awcache   ),
    .s_awprot      (s1_awprot    ),
    .s_awvalid     (s1_awvalid   ),
    .s_awready     (s1_awready   ),

    .s_wid         (s1_wid       ),
    .s_wdata       (s1_wdata     ),
    .s_wstrb       (s1_wstrb     ),
    .s_wlast       (s1_wlast     ),
    .s_wvalid      (s1_wvalid    ),
    .s_wready      (s1_wready    ),

    .s_bid         (s1_bid       ),
    .s_bresp       (s1_bresp     ),
    .s_bvalid      (s1_bvalid    ),
    .s_bready      (s1_bready    ),

    .s_arid        (s1_arid      ),
    .s_araddr      (s1_araddr    ),
    .s_arlen       (s1_arlen     ),
    .s_arsize      (s1_arsize    ),
    .s_arburst     (s1_arburst   ),
    .s_arlock      (s1_arlock    ),
    .s_arcache     (s1_arcache   ),
    .s_arprot      (s1_arprot    ),
    .s_arvalid     (s1_arvalid   ),
    .s_arready     (s1_arready   ),

    .s_rid         (s1_rid       ),
    .s_rdata       (s1_rdata     ),
    .s_rresp       (s1_rresp     ),
    .s_rlast       (s1_rlast     ),
    .s_rvalid      (s1_rvalid    ),
    .s_rready      (s1_rready    ),

    .m_aclk        (ddr_aclk     ),
    .m_aresetn     (ddr_aresetn  ),

    .m_awid        (ddr_awid     ),
    .m_awaddr      (ddr_awaddr   ),
    .m_awlen       (ddr_awlen    ),
    .m_awsize      (ddr_awsize   ),
    .m_awburst     (ddr_awburst  ),
    .m_awlock      (ddr_awlock   ),
    .m_awcache     (ddr_awcache  ),
    .m_awprot      (ddr_awprot   ),
    .m_awvalid     (ddr_awvalid  ),
    .m_awready     (ddr_awready  ),

    .m_wid         (             ),
    .m_wdata       (ddr_wdata    ),
    .m_wstrb       (ddr_wstrb    ),
    .m_wlast       (ddr_wlast    ),
    .m_wvalid      (ddr_wvalid   ),
    .m_wready      (ddr_wready   ),

    .m_bid         (ddr_bid      ),
    .m_bresp       (ddr_bresp    ),
    .m_bvalid      (ddr_bvalid   ),
    .m_bready      (ddr_bready   ),

    .m_arid        (ddr_arid     ),
    .m_araddr      (ddr_araddr   ),
    .m_arlen       (ddr_arlen    ),
    .m_arsize      (ddr_arsize   ),
    .m_arburst     (ddr_arburst  ),
    .m_arlock      (ddr_arlock   ),
    .m_arcache     (ddr_arcache  ),
    .m_arprot      (ddr_arprot   ),
    .m_arvalid     (ddr_arvalid  ),
    .m_arready     (ddr_arready  ),

    .m_rid         (ddr_rid      ),
    .m_rdata       (ddr_rdata    ),
    .m_rresp       (ddr_rresp    ),
    .m_rlast       (ddr_rlast    ),
    .m_rvalid      (ddr_rvalid   ),
    .m_rready      (ddr_rready   )
  );

  //====================================================================
  // MIG DDR3 控制器实例
  //====================================================================
  mig_7series_0 u_mig_7series_0 (
    // -------- DDR3 物理接口 --------
    .ddr3_addr           (ddr3_addr          ),
    .ddr3_ba             (ddr3_ba            ),
    .ddr3_cas_n          (ddr3_cas_n         ),
    .ddr3_ck_n           (ddr3_ck_n          ),
    .ddr3_ck_p           (ddr3_ck_p          ),
    .ddr3_cke            (ddr3_cke           ),
    .ddr3_ras_n          (ddr3_ras_n         ),
    .ddr3_reset_n        (ddr3_reset_n       ),
    .ddr3_we_n           (ddr3_we_n          ),
    .ddr3_dq             (ddr3_dq            ),
    .ddr3_dqs_n          (ddr3_dqs_n         ),
    .ddr3_dqs_p          (ddr3_dqs_p         ),
    .ddr3_cs_n           (ddr3_cs_n          ),
    .ddr3_dm             (ddr3_dm            ),
    .ddr3_odt            (ddr3_odt           ),
    .init_calib_complete (init_calib_complete),

    // -------- AXI 应用接口 --------
    .ui_clk              (ui_clk             ),
    .ui_clk_sync_rst     (ui_clk_sync_rst    ),
    .mmcm_locked         (                    ),
    .aresetn             (ddr_aresetn        ),   // 必须是 ui_clk 域同步复位
    .device_temp         (ddr_device_temp    ),
    .app_sr_req          (1'b0                ),
    .app_ref_req         (1'b0                ),
    .app_zq_req          (1'b0                ),
    .app_sr_active       (                    ),
    .app_ref_ack         (                    ),
    .app_zq_ack          (                    ),

    // -------- AXI 写地址 --------
    .s_axi_awid          (ddr_awid            ),
    .s_axi_awaddr        (ddr_awaddr          ),
    .s_axi_awlen         (ddr_awlen           ),
    .s_axi_awsize        (ddr_awsize          ),
    .s_axi_awburst       (ddr_awburst         ),
    .s_axi_awlock        (ddr_awlock          ),
    .s_axi_awcache       (ddr_awcache         ),
    .s_axi_awprot        (ddr_awprot          ),
    .s_axi_awqos         (ddr_awqos           ),
    .s_axi_awvalid       (ddr_awvalid         ),
    .s_axi_awready       (ddr_awready         ),

    // -------- AXI 写数据 --------
    .s_axi_wdata         (ddr_wdata           ),
    .s_axi_wstrb         (ddr_wstrb           ),
    .s_axi_wlast         (ddr_wlast           ),
    .s_axi_wvalid        (ddr_wvalid          ),
    .s_axi_wready        (ddr_wready          ),

    // -------- AXI 写响应 --------
    .s_axi_bid           (ddr_bid             ),
    .s_axi_bresp         (ddr_bresp           ),
    .s_axi_bvalid        (ddr_bvalid          ),
    .s_axi_bready        (ddr_bready          ),

    // -------- AXI 读地址 --------
    .s_axi_arid          (ddr_arid            ),
    .s_axi_araddr        (ddr_araddr          ),
    .s_axi_arlen         (ddr_arlen           ),
    .s_axi_arsize        (ddr_arsize          ),
    .s_axi_arburst       (ddr_arburst         ),
    .s_axi_arlock        (ddr_arlock          ),
    .s_axi_arcache       (ddr_arcache         ),
    .s_axi_arprot        (ddr_arprot          ),
    .s_axi_arqos         (ddr_arqos           ),
    .s_axi_arvalid       (ddr_arvalid         ),
    .s_axi_arready       (ddr_arready         ),

    // -------- AXI 读数据 --------
    .s_axi_rid           (ddr_rid             ),
    .s_axi_rdata         (ddr_rdata           ),
    .s_axi_rresp         (ddr_rresp           ),
    .s_axi_rlast         (ddr_rlast           ),
    .s_axi_rvalid        (ddr_rvalid          ),
    .s_axi_rready        (ddr_rready          ),

    // -------- 参考时钟 / 复位 --------
    .sys_clk_i           (ddr_refclk          ),
    .sys_rst             (mig_sys_rst_n       )    // 取反: MIG sys_rst 低有效
  );

  // QoS 未使用
  assign ddr_awqos = 4'h0;
  assign ddr_arqos = 4'h0;

endmodule
