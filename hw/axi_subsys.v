`timescale 1ns / 1ps
//=====================================================================
//  File   : axi_subsys.v
//  Brief  : AXI 总线子系统顶层 (3 主 x 4 从) —— LA132 SoC / 云晓 100T
//  Author : WorkBuddy
//---------------------------------------------------------------------
//  本模块把「3 个 AXI 主设备 x 4 个 AXI 从设备」的完整互联连同
//  LCD / DMAC / DDR 三个外设节点封装在一起, 只对外开放:
//    - M0 (CPU)      : 来自 godson_mcu_cpu 内的 LA132 数据总线
//    - S0 (APB-BRIDGE): 回送 godson_mcu_cpu 内的 axi2apb_bridge
//    - LCD 物理接口 / DDR3 物理接口 / 中断
//
//  ┌───────────────────────── axi_subsys ─────────────────────────┐
//  │                                                              │
//  │   M0  ┌──────────────────────────────────────────┐           │
//  │ CPU ─▶│                                          │           │
//  │   M1  │           axi_interconnect               │           │
//  │ DMAC─▶│      3 Master   x   4 Slave              │           │
//  │   M2  │                                          │           │
//  │ LCD ─▶│                                          │           │
//  │       └───┬──────────┬──────────┬────────────┬───┘           │
//  │           │ S0       │ S1       │ S2         │ S3            │
//  │           ▼          ▼          ▼            ▼               │
//  │      APB-BRIDGE    DMAC       LCD          DDR3              │
//  │      (出去)     寄存器组    寄存器组    axi_ddr_slave         │
//  │                 (axi_dma)  (axi_lcd)   -> MIG -> DDR3 颗粒    │
//  └──────────────────────────────────────────────────────────────┘
//
//  地址窗口 (见 config.vh) —— 全部使用新的 AXI 总线地址,
//  不再复用原 APB 从设备地址 (APB-DMA 0x510E_0000 / APB-LCD 0x5200_0000)
//    S0 APB-BRIDGE : 其余所有地址 (默认窗口)
//    S1 DMAC       : 0x2001_0000  (64KB, 紧跟 LCD 配置窗口)
//    S2 LCD        : 0x2000_0000  (64KB 配置窗口)
//    S3 DDR3       : 0x4000_0000  (1GB, 兼作 LCD 显存, 止于 0x7FFF_FFFF)
//
//  地址关系 : 三个窗口互不重叠, 译码顺序不影响功能
//    DDR 窗口是 0x4000_0000 ~ 0x7FFF_FFFF (mask 0xC000_0000, 共 1GB),
//    LCD / DMAC 的 64KB 配置窗口在它之前的 0x2000 段, APB 段在 0x3000 段。
//    早期版本把两者放在 DDR 窗口内部 (0x3000 段), 只能靠译码优先级绕开,
//    现已彻底分开 —— 详见 config.vh 与 amba/axi_interconnect.v 的注释。
//
//  访问权限
//    CPU  : S0 / S1 / S2 / S3     (全部)
//    DMAC : S0 / S1 / S2 / S3     (全部)
//    LCD  : 只读, 实际只用 S3 (显存)
//
//  时钟
//    aclk          : SoC AXI 时钟 32MHz  (clk_wiz_0 clk_out1)
//    lcd_sys_clk   : 50MHz               (clk_wiz_0 clk_out2)
//    ddr_refclk    : 200MHz              (clk_wiz_0 clk_out4, MIG 参考时钟)
//=====================================================================

`include "config.vh"

module axi_subsys (
  // ================= 时钟 / 复位 =================
  input  wire                        aclk           ,   // SoC AXI 32MHz
  input  wire                        aresetn        ,   // 低有效
  input  wire                        lcd_sys_clk    ,   // 50MHz
  input  wire                        lcd_sys_rstn   ,   // 低有效
  input  wire                        ddr_refclk     ,   // 200MHz
  input  wire                        ddr_sys_rst    ,   // 高有效

  // ================= M0 : CPU 主口 (来自 godson_mcu_cpu) =================
  input  wire [`LID      -1:0]       cpu_m_awid     ,
  input  wire [`LAWADDR  -1:0]       cpu_m_awaddr   ,
  input  wire [`LAWLEN   -1:0]       cpu_m_awlen    ,
  input  wire [`LAWSIZE  -1:0]       cpu_m_awsize   ,
  input  wire [`LAWBURST -1:0]       cpu_m_awburst  ,
  input  wire [`LAWLOCK  -1:0]       cpu_m_awlock   ,
  input  wire [`LAWCACHE -1:0]       cpu_m_awcache  ,
  input  wire [`LAWPROT  -1:0]       cpu_m_awprot   ,
  input  wire                        cpu_m_awvalid  ,
  output wire                        cpu_m_awready  ,

  input  wire [`LID      -1:0]       cpu_m_wid      ,
  input  wire [`LWDATA   -1:0]       cpu_m_wdata    ,
  input  wire [`LWSTRB   -1:0]       cpu_m_wstrb    ,
  input  wire                        cpu_m_wlast    ,
  input  wire                        cpu_m_wvalid   ,
  output wire                        cpu_m_wready   ,

  output wire [`LID      -1:0]       cpu_m_bid      ,
  output wire [`LBRESP   -1:0]       cpu_m_bresp    ,
  output wire                        cpu_m_bvalid   ,
  input  wire                        cpu_m_bready   ,

  input  wire [`LID      -1:0]       cpu_m_arid     ,
  input  wire [`LARADDR  -1:0]       cpu_m_araddr   ,
  input  wire [`LARLEN   -1:0]       cpu_m_arlen    ,
  input  wire [`LARSIZE  -1:0]       cpu_m_arsize   ,
  input  wire [`LARBURST -1:0]       cpu_m_arburst  ,
  input  wire [`LARLOCK  -1:0]       cpu_m_arlock   ,
  input  wire [`LARCACHE -1:0]       cpu_m_arcache  ,
  input  wire [`LARPROT  -1:0]       cpu_m_arprot   ,
  input  wire                        cpu_m_arvalid  ,
  output wire                        cpu_m_arready  ,

  output wire [`LID      -1:0]       cpu_m_rid      ,
  output wire [`LRDATA   -1:0]       cpu_m_rdata    ,
  output wire [`LRRESP   -1:0]       cpu_m_rresp    ,
  output wire                        cpu_m_rlast    ,
  output wire                        cpu_m_rvalid   ,
  input  wire                        cpu_m_rready   ,

  // ================= S0 : APB 桥从口 (回送 godson_mcu_cpu) =================
  output wire [`LID      -1:0]       apb_s_awid     ,
  output wire [`LAWADDR  -1:0]       apb_s_awaddr   ,
  output wire [`LAWLEN   -1:0]       apb_s_awlen    ,
  output wire [`LAWSIZE  -1:0]       apb_s_awsize   ,
  output wire [`LAWBURST -1:0]       apb_s_awburst  ,
  output wire [`LAWLOCK  -1:0]       apb_s_awlock   ,
  output wire [`LAWCACHE -1:0]       apb_s_awcache  ,
  output wire [`LAWPROT  -1:0]       apb_s_awprot   ,
  output wire                        apb_s_awvalid  ,
  input  wire                        apb_s_awready  ,

  output wire [`LID      -1:0]       apb_s_wid      ,
  output wire [`LWDATA   -1:0]       apb_s_wdata    ,
  output wire [`LWSTRB   -1:0]       apb_s_wstrb    ,
  output wire                        apb_s_wlast    ,
  output wire                        apb_s_wvalid   ,
  input  wire                        apb_s_wready   ,

  input  wire [`LID      -1:0]       apb_s_bid      ,
  input  wire [`LBRESP   -1:0]       apb_s_bresp    ,
  input  wire                        apb_s_bvalid   ,
  output wire                        apb_s_bready   ,

  output wire [`LID      -1:0]       apb_s_arid     ,
  output wire [`LARADDR  -1:0]       apb_s_araddr   ,
  output wire [`LARLEN   -1:0]       apb_s_arlen    ,
  output wire [`LARSIZE  -1:0]       apb_s_arsize   ,
  output wire [`LARBURST -1:0]       apb_s_arburst  ,
  output wire [`LARLOCK  -1:0]       apb_s_arlock   ,
  output wire [`LARCACHE -1:0]       apb_s_arcache  ,
  output wire [`LARPROT  -1:0]       apb_s_arprot   ,
  output wire                        apb_s_arvalid  ,
  input  wire                        apb_s_arready  ,

  input  wire [`LID      -1:0]       apb_s_rid      ,
  input  wire [`LRDATA   -1:0]       apb_s_rdata    ,
  input  wire [`LRRESP   -1:0]       apb_s_rresp    ,
  input  wire                        apb_s_rlast    ,
  input  wire                        apb_s_rvalid   ,
  output wire                        apb_s_rready   ,

  // ================= LCD 物理接口 =================
  output wire [15:0]                 lcd_id         ,
  output wire                        lcd_clk        ,
  output wire                        lcd_rstn       ,
  output wire                        lcd_de         ,
  output wire                        lcd_bl         ,
  output wire                        lcd_hs         ,
  output wire                        lcd_vs         ,
  output wire [23:0]                 lcd_rgb        ,

  // ================= DDR3 物理接口 =================
  output wire                        init_calib_complete,
  output wire [14:0]                 ddr3_addr      ,
  output wire [ 2:0]                 ddr3_ba        ,
  output wire                        ddr3_cas_n     ,
  output wire [ 0:0]                 ddr3_ck_n      ,
  output wire [ 0:0]                 ddr3_ck_p      ,
  output wire [ 0:0]                 ddr3_cke       ,
  output wire                        ddr3_ras_n     ,
  output wire                        ddr3_reset_n   ,
  output wire                        ddr3_we_n      ,
  inout  wire [31:0]                 ddr3_dq        ,
  inout  wire [ 3:0]                 ddr3_dqs_n     ,
  inout  wire [ 3:0]                 ddr3_dqs_p     ,
  output wire [ 0:0]                 ddr3_cs_n      ,
  output wire [ 3:0]                 ddr3_dm        ,
  output wire [ 0:0]                 ddr3_odt       ,

  // ================= 中断 =================
  output wire                        dma_irq        ,
  output wire                        lcd_irq
);

  localparam N_MASTER = 3;
  localparam N_SLAVE  = 4;

  //=====================================================================
  // 打包总线: 主设备侧
  //=====================================================================
  wire [N_MASTER*`LID      -1:0] ic_m_awid   ;
  wire [N_MASTER*`LAWADDR  -1:0] ic_m_awaddr ;
  wire [N_MASTER*`LAWLEN   -1:0] ic_m_awlen  ;
  wire [N_MASTER*`LAWSIZE  -1:0] ic_m_awsize ;
  wire [N_MASTER*`LAWBURST -1:0] ic_m_awburst;
  wire [N_MASTER*`LAWLOCK  -1:0] ic_m_awlock ;
  wire [N_MASTER*`LAWCACHE -1:0] ic_m_awcache;
  wire [N_MASTER*`LAWPROT  -1:0] ic_m_awprot ;
  wire [N_MASTER           -1:0] ic_m_awvalid;
  wire [N_MASTER           -1:0] ic_m_awready;

  wire [N_MASTER*`LID      -1:0] ic_m_wid    ;
  wire [N_MASTER*`LWDATA   -1:0] ic_m_wdata  ;
  wire [N_MASTER*`LWSTRB   -1:0] ic_m_wstrb  ;
  wire [N_MASTER           -1:0] ic_m_wlast  ;
  wire [N_MASTER           -1:0] ic_m_wvalid ;
  wire [N_MASTER           -1:0] ic_m_wready ;

  wire [N_MASTER*`LID      -1:0] ic_m_bid    ;
  wire [N_MASTER*`LBRESP   -1:0] ic_m_bresp  ;
  wire [N_MASTER           -1:0] ic_m_bvalid ;
  wire [N_MASTER           -1:0] ic_m_bready ;

  wire [N_MASTER*`LID      -1:0] ic_m_arid   ;
  wire [N_MASTER*`LARADDR  -1:0] ic_m_araddr ;
  wire [N_MASTER*`LARLEN   -1:0] ic_m_arlen  ;
  wire [N_MASTER*`LARSIZE  -1:0] ic_m_arsize ;
  wire [N_MASTER*`LARBURST -1:0] ic_m_arburst;
  wire [N_MASTER*`LARLOCK  -1:0] ic_m_arlock ;
  wire [N_MASTER*`LARCACHE -1:0] ic_m_arcache;
  wire [N_MASTER*`LARPROT  -1:0] ic_m_arprot ;
  wire [N_MASTER           -1:0] ic_m_arvalid;
  wire [N_MASTER           -1:0] ic_m_arready;

  wire [N_MASTER*`LID      -1:0] ic_m_rid    ;
  wire [N_MASTER*`LRDATA   -1:0] ic_m_rdata  ;
  wire [N_MASTER*`LRRESP   -1:0] ic_m_rresp  ;
  wire [N_MASTER           -1:0] ic_m_rlast  ;
  wire [N_MASTER           -1:0] ic_m_rvalid ;
  wire [N_MASTER           -1:0] ic_m_rready ;

  //=====================================================================
  // 打包总线: 从设备侧
  //=====================================================================
  wire [N_SLAVE *`LID      -1:0] ic_s_awid   ;
  wire [N_SLAVE *`LAWADDR  -1:0] ic_s_awaddr ;
  wire [N_SLAVE *`LAWLEN   -1:0] ic_s_awlen  ;
  wire [N_SLAVE *`LAWSIZE  -1:0] ic_s_awsize ;
  wire [N_SLAVE *`LAWBURST -1:0] ic_s_awburst;
  wire [N_SLAVE *`LAWLOCK  -1:0] ic_s_awlock ;
  wire [N_SLAVE *`LAWCACHE -1:0] ic_s_awcache;
  wire [N_SLAVE *`LAWPROT  -1:0] ic_s_awprot ;
  wire [N_SLAVE            -1:0] ic_s_awvalid;
  wire [N_SLAVE            -1:0] ic_s_awready;

  wire [N_SLAVE *`LID      -1:0] ic_s_wid    ;
  wire [N_SLAVE *`LWDATA   -1:0] ic_s_wdata  ;
  wire [N_SLAVE *`LWSTRB   -1:0] ic_s_wstrb  ;
  wire [N_SLAVE            -1:0] ic_s_wlast  ;
  wire [N_SLAVE            -1:0] ic_s_wvalid ;
  wire [N_SLAVE            -1:0] ic_s_wready ;

  wire [N_SLAVE *`LID      -1:0] ic_s_bid    ;
  wire [N_SLAVE *`LBRESP   -1:0] ic_s_bresp  ;
  wire [N_SLAVE            -1:0] ic_s_bvalid ;
  wire [N_SLAVE            -1:0] ic_s_bready ;

  wire [N_SLAVE *`LID      -1:0] ic_s_arid   ;
  wire [N_SLAVE *`LARADDR  -1:0] ic_s_araddr ;
  wire [N_SLAVE *`LARLEN   -1:0] ic_s_arlen  ;
  wire [N_SLAVE *`LARSIZE  -1:0] ic_s_arsize ;
  wire [N_SLAVE *`LARBURST -1:0] ic_s_arburst;
  wire [N_SLAVE *`LARLOCK  -1:0] ic_s_arlock ;
  wire [N_SLAVE *`LARCACHE -1:0] ic_s_arcache;
  wire [N_SLAVE *`LARPROT  -1:0] ic_s_arprot ;
  wire [N_SLAVE            -1:0] ic_s_arvalid;
  wire [N_SLAVE            -1:0] ic_s_arready;

  wire [N_SLAVE *`LID      -1:0] ic_s_rid    ;
  wire [N_SLAVE *`LRDATA   -1:0] ic_s_rdata  ;
  wire [N_SLAVE *`LRRESP   -1:0] ic_s_rresp  ;
  wire [N_SLAVE            -1:0] ic_s_rlast  ;
  wire [N_SLAVE            -1:0] ic_s_rvalid ;
  wire [N_SLAVE            -1:0] ic_s_rready ;

  //=====================================================================
  // DMAC 主口 (M1)
  //=====================================================================
  wire [`LID      -1:0] dma_m_arid   ;
  wire [`LARADDR  -1:0] dma_m_araddr ;
  wire [`LARLEN   -1:0] dma_m_arlen  ;
  wire [`LARSIZE  -1:0] dma_m_arsize ;
  wire [`LARBURST -1:0] dma_m_arburst;
  wire [`LARLOCK  -1:0] dma_m_arlock ;
  wire [`LARCACHE -1:0] dma_m_arcache;
  wire [`LARPROT  -1:0] dma_m_arprot ;
  wire                  dma_m_arvalid;
  wire                  dma_m_arready;
  wire [`LID      -1:0] dma_m_rid    ;
  wire [`LRDATA   -1:0] dma_m_rdata  ;
  wire [`LRRESP   -1:0] dma_m_rresp  ;
  wire                  dma_m_rlast  ;
  wire                  dma_m_rvalid ;
  wire                  dma_m_rready ;

  wire [`LID      -1:0] dma_m_awid   ;
  wire [`LAWADDR  -1:0] dma_m_awaddr ;
  wire [`LAWLEN   -1:0] dma_m_awlen  ;
  wire [`LAWSIZE  -1:0] dma_m_awsize ;
  wire [`LAWBURST -1:0] dma_m_awburst;
  wire [`LAWLOCK  -1:0] dma_m_awlock ;
  wire [`LAWCACHE -1:0] dma_m_awcache;
  wire [`LAWPROT  -1:0] dma_m_awprot ;
  wire                  dma_m_awvalid;
  wire                  dma_m_awready;
  wire [`LID      -1:0] dma_m_wid    ;
  wire [`LWDATA   -1:0] dma_m_wdata  ;
  wire [`LWSTRB   -1:0] dma_m_wstrb  ;
  wire                  dma_m_wlast  ;
  wire                  dma_m_wvalid ;
  wire                  dma_m_wready ;
  wire [`LID      -1:0] dma_m_bid    ;
  wire [`LBRESP   -1:0] dma_m_bresp  ;
  wire                  dma_m_bvalid ;
  wire                  dma_m_bready ;

  //=====================================================================
  // LCD 主口 (M2) —— 只读显存, 写通道恒无效
  //=====================================================================
  wire [`LID      -1:0] lcd_m_arid   ;
  wire [`LARADDR  -1:0] lcd_m_araddr ;
  wire [`LARLEN   -1:0] lcd_m_arlen  ;
  wire [`LARSIZE  -1:0] lcd_m_arsize ;
  wire [`LARBURST -1:0] lcd_m_arburst;
  wire [`LARLOCK  -1:0] lcd_m_arlock ;
  wire [`LARCACHE -1:0] lcd_m_arcache;
  wire [`LARPROT  -1:0] lcd_m_arprot ;
  wire                  lcd_m_arvalid;
  wire                  lcd_m_arready;
  wire [`LID      -1:0] lcd_m_rid    ;
  wire [`LRDATA   -1:0] lcd_m_rdata  ;
  wire [`LRRESP   -1:0] lcd_m_rresp  ;
  wire                  lcd_m_rlast  ;
  wire                  lcd_m_rvalid ;
  wire                  lcd_m_rready ;

  wire [`LID      -1:0] lcd_m_awid   ;
  wire [`LAWADDR  -1:0] lcd_m_awaddr ;
  wire [`LAWLEN   -1:0] lcd_m_awlen  ;
  wire [`LAWSIZE  -1:0] lcd_m_awsize ;
  wire [`LAWBURST -1:0] lcd_m_awburst;
  wire [`LAWLOCK  -1:0] lcd_m_awlock ;
  wire [`LAWCACHE -1:0] lcd_m_awcache;
  wire [`LAWPROT  -1:0] lcd_m_awprot ;
  wire                  lcd_m_awvalid;
  wire                  lcd_m_awready;
  wire [`LID      -1:0] lcd_m_wid    ;
  wire [`LWDATA   -1:0] lcd_m_wdata  ;
  wire [`LWSTRB   -1:0] lcd_m_wstrb  ;
  wire                  lcd_m_wlast  ;
  wire                  lcd_m_wvalid ;
  wire                  lcd_m_wready ;
  wire [`LID      -1:0] lcd_m_bid    ;
  wire [`LBRESP   -1:0] lcd_m_bresp  ;
  wire                  lcd_m_bvalid ;
  wire                  lcd_m_bready ;

  //=====================================================================
  // M0 : CPU
  //=====================================================================
  assign ic_m_awid   [0*`LID      +: `LID      ] = cpu_m_awid   ;
  assign ic_m_awaddr [0*`LAWADDR  +: `LAWADDR  ] = cpu_m_awaddr ;
  assign ic_m_awlen  [0*`LAWLEN   +: `LAWLEN   ] = cpu_m_awlen  ;
  assign ic_m_awsize [0*`LAWSIZE  +: `LAWSIZE  ] = cpu_m_awsize ;
  assign ic_m_awburst[0*`LAWBURST +: `LAWBURST ] = cpu_m_awburst;
  assign ic_m_awlock [0*`LAWLOCK  +: `LAWLOCK  ] = cpu_m_awlock ;
  assign ic_m_awcache[0*`LAWCACHE +: `LAWCACHE ] = cpu_m_awcache;
  assign ic_m_awprot [0*`LAWPROT  +: `LAWPROT  ] = cpu_m_awprot ;
  assign ic_m_awvalid[0]                          = cpu_m_awvalid;
  assign cpu_m_awready                            = ic_m_awready[0];

  assign ic_m_wid    [0*`LID      +: `LID      ] = cpu_m_wid    ;
  assign ic_m_wdata  [0*`LWDATA   +: `LWDATA   ] = cpu_m_wdata  ;
  assign ic_m_wstrb  [0*`LWSTRB   +: `LWSTRB   ] = cpu_m_wstrb  ;
  assign ic_m_wlast  [0]                          = cpu_m_wlast  ;
  assign ic_m_wvalid [0]                          = cpu_m_wvalid ;
  assign cpu_m_wready                             = ic_m_wready [0];

  assign cpu_m_bid                                = ic_m_bid   [0*`LID    +: `LID   ];
  assign cpu_m_bresp                              = ic_m_bresp [0*`LBRESP +: `LBRESP];
  assign cpu_m_bvalid                             = ic_m_bvalid[0];
  assign ic_m_bready [0]                          = cpu_m_bready;

  assign ic_m_arid   [0*`LID      +: `LID      ] = cpu_m_arid   ;
  assign ic_m_araddr [0*`LARADDR  +: `LARADDR  ] = cpu_m_araddr ;
  assign ic_m_arlen  [0*`LARLEN   +: `LARLEN   ] = cpu_m_arlen  ;
  assign ic_m_arsize [0*`LARSIZE  +: `LARSIZE  ] = cpu_m_arsize ;
  assign ic_m_arburst[0*`LARBURST +: `LARBURST ] = cpu_m_arburst;
  assign ic_m_arlock [0*`LARLOCK  +: `LARLOCK  ] = cpu_m_arlock ;
  assign ic_m_arcache[0*`LARCACHE +: `LARCACHE ] = cpu_m_arcache;
  assign ic_m_arprot [0*`LARPROT  +: `LARPROT  ] = cpu_m_arprot ;
  assign ic_m_arvalid[0]                          = cpu_m_arvalid;
  assign cpu_m_arready                            = ic_m_arready[0];

  assign cpu_m_rid                                = ic_m_rid   [0*`LID    +: `LID   ];
  assign cpu_m_rdata                              = ic_m_rdata [0*`LRDATA +: `LRDATA];
  assign cpu_m_rresp                              = ic_m_rresp [0*`LRRESP +: `LRRESP];
  assign cpu_m_rlast                              = ic_m_rlast [0];
  assign cpu_m_rvalid                             = ic_m_rvalid[0];
  assign ic_m_rready [0]                          = cpu_m_rready;

  //=====================================================================
  // M1 : DMAC
  //=====================================================================
  assign ic_m_arid   [1*`LID      +: `LID      ] = dma_m_arid   ;
  assign ic_m_araddr [1*`LARADDR  +: `LARADDR  ] = dma_m_araddr ;
  assign ic_m_arlen  [1*`LARLEN   +: `LARLEN   ] = dma_m_arlen  ;
  assign ic_m_arsize [1*`LARSIZE  +: `LARSIZE  ] = dma_m_arsize ;
  assign ic_m_arburst[1*`LARBURST +: `LARBURST ] = dma_m_arburst;
  assign ic_m_arlock [1*`LARLOCK  +: `LARLOCK  ] = dma_m_arlock ;
  assign ic_m_arcache[1*`LARCACHE +: `LARCACHE ] = dma_m_arcache;
  assign ic_m_arprot [1*`LARPROT  +: `LARPROT  ] = dma_m_arprot ;
  assign ic_m_arvalid[1]                          = dma_m_arvalid;
  assign dma_m_arready                            = ic_m_arready[1];

  assign dma_m_rid                                = ic_m_rid  [1*`LID    +: `LID   ];
  assign dma_m_rdata                              = ic_m_rdata[1*`LRDATA +: `LRDATA];
  assign dma_m_rresp                              = ic_m_rresp[1*`LRRESP +: `LRRESP];
  assign dma_m_rlast                              = ic_m_rlast[1];
  assign dma_m_rvalid                             = ic_m_rvalid[1];
  assign ic_m_rready [1]                          = dma_m_rready;

  assign ic_m_awid   [1*`LID      +: `LID      ] = dma_m_awid   ;
  assign ic_m_awaddr [1*`LAWADDR  +: `LAWADDR  ] = dma_m_awaddr ;
  assign ic_m_awlen  [1*`LAWLEN   +: `LAWLEN   ] = dma_m_awlen  ;
  assign ic_m_awsize [1*`LAWSIZE  +: `LAWSIZE  ] = dma_m_awsize ;
  assign ic_m_awburst[1*`LAWBURST +: `LAWBURST ] = dma_m_awburst;
  assign ic_m_awlock [1*`LAWLOCK  +: `LAWLOCK  ] = dma_m_awlock ;
  assign ic_m_awcache[1*`LAWCACHE +: `LAWCACHE ] = dma_m_awcache;
  assign ic_m_awprot [1*`LAWPROT  +: `LAWPROT  ] = dma_m_awprot ;
  assign ic_m_awvalid[1]                          = dma_m_awvalid;
  assign dma_m_awready                            = ic_m_awready[1];

  assign ic_m_wid    [1*`LID      +: `LID      ] = dma_m_wid    ;
  assign ic_m_wdata  [1*`LWDATA   +: `LWDATA   ] = dma_m_wdata  ;
  assign ic_m_wstrb  [1*`LWSTRB   +: `LWSTRB   ] = dma_m_wstrb  ;
  assign ic_m_wlast  [1]                          = dma_m_wlast  ;
  assign ic_m_wvalid [1]                          = dma_m_wvalid ;
  assign dma_m_wready                             = ic_m_wready [1];

  assign dma_m_bid                                = ic_m_bid   [1*`LID    +: `LID   ];
  assign dma_m_bresp                              = ic_m_bresp [1*`LBRESP +: `LBRESP];
  assign dma_m_bvalid                             = ic_m_bvalid[1];
  assign ic_m_bready [1]                          = dma_m_bready;

  //=====================================================================
  // M2 : LCD (只读主口; 写通道由 axi_lcd 内部恒无效)
  //=====================================================================
  assign ic_m_arid   [2*`LID      +: `LID      ] = lcd_m_arid   ;
  assign ic_m_araddr [2*`LARADDR  +: `LARADDR  ] = lcd_m_araddr ;
  assign ic_m_arlen  [2*`LARLEN   +: `LARLEN   ] = lcd_m_arlen  ;
  assign ic_m_arsize [2*`LARSIZE  +: `LARSIZE  ] = lcd_m_arsize ;
  assign ic_m_arburst[2*`LARBURST +: `LARBURST ] = lcd_m_arburst;
  assign ic_m_arlock [2*`LARLOCK  +: `LARLOCK  ] = lcd_m_arlock ;
  assign ic_m_arcache[2*`LARCACHE +: `LARCACHE ] = lcd_m_arcache;
  assign ic_m_arprot [2*`LARPROT  +: `LARPROT  ] = lcd_m_arprot ;
  assign ic_m_arvalid[2]                          = lcd_m_arvalid;
  assign lcd_m_arready                            = ic_m_arready[2];

  assign lcd_m_rid                                = ic_m_rid  [2*`LID    +: `LID   ];
  assign lcd_m_rdata                              = ic_m_rdata[2*`LRDATA +: `LRDATA];
  assign lcd_m_rresp                              = ic_m_rresp[2*`LRRESP +: `LRRESP];
  assign lcd_m_rlast                              = ic_m_rlast[2];
  assign lcd_m_rvalid                             = ic_m_rvalid[2];
  assign ic_m_rready [2]                          = lcd_m_rready;

  assign ic_m_awid   [2*`LID      +: `LID      ] = lcd_m_awid   ;
  assign ic_m_awaddr [2*`LAWADDR  +: `LAWADDR  ] = lcd_m_awaddr ;
  assign ic_m_awlen  [2*`LAWLEN   +: `LAWLEN   ] = lcd_m_awlen  ;
  assign ic_m_awsize [2*`LAWSIZE  +: `LAWSIZE  ] = lcd_m_awsize ;
  assign ic_m_awburst[2*`LAWBURST +: `LAWBURST ] = lcd_m_awburst;
  assign ic_m_awlock [2*`LAWLOCK  +: `LAWLOCK  ] = lcd_m_awlock ;
  assign ic_m_awcache[2*`LAWCACHE +: `LAWCACHE ] = lcd_m_awcache;
  assign ic_m_awprot [2*`LAWPROT  +: `LAWPROT  ] = lcd_m_awprot ;
  assign ic_m_awvalid[2]                          = lcd_m_awvalid;
  assign lcd_m_awready                            = ic_m_awready[2];

  assign ic_m_wid    [2*`LID      +: `LID      ] = lcd_m_wid    ;
  assign ic_m_wdata  [2*`LWDATA   +: `LWDATA   ] = lcd_m_wdata  ;
  assign ic_m_wstrb  [2*`LWSTRB   +: `LWSTRB   ] = lcd_m_wstrb  ;
  assign ic_m_wlast  [2]                          = lcd_m_wlast  ;
  assign ic_m_wvalid [2]                          = lcd_m_wvalid ;
  assign lcd_m_wready                             = ic_m_wready [2];

  assign lcd_m_bid                                = ic_m_bid   [2*`LID    +: `LID   ];
  assign lcd_m_bresp                              = ic_m_bresp [2*`LBRESP +: `LBRESP];
  assign lcd_m_bvalid                             = ic_m_bvalid[2];
  assign ic_m_bready [2]                          = lcd_m_bready;

  //=====================================================================
  // 互联矩阵例化 (3 主 x 4 从)
  //=====================================================================
  axi_interconnect #(
    .N_MASTER          (N_MASTER       ),
    .N_SLAVE           (N_SLAVE        ),
    .RD_FIFO_DEPTH_LOG (3              )
  ) u_ic (
    .aclk        (aclk       ),
    .aresetn     (aresetn    ),

    .m_awid      (ic_m_awid  ), .m_awaddr (ic_m_awaddr ), .m_awlen   (ic_m_awlen  ),
    .m_awsize    (ic_m_awsize), .m_awburst(ic_m_awburst), .m_awlock  (ic_m_awlock ),
    .m_awcache   (ic_m_awcache),.m_awprot (ic_m_awprot ), .m_awvalid (ic_m_awvalid),
    .m_awready   (ic_m_awready),

    .m_wid       (ic_m_wid   ), .m_wdata  (ic_m_wdata   ), .m_wstrb   (ic_m_wstrb  ),
    .m_wlast     (ic_m_wlast ), .m_wvalid (ic_m_wvalid  ), .m_wready  (ic_m_wready ),

    .m_bid       (ic_m_bid   ), .m_bresp  (ic_m_bresp   ), .m_bvalid  (ic_m_bvalid ),
    .m_bready    (ic_m_bready),

    .m_arid      (ic_m_arid  ), .m_araddr (ic_m_araddr  ), .m_arlen   (ic_m_arlen  ),
    .m_arsize    (ic_m_arsize), .m_arburst(ic_m_arburst ), .m_arlock  (ic_m_arlock ),
    .m_arcache   (ic_m_arcache),.m_arprot (ic_m_arprot  ), .m_arvalid (ic_m_arvalid),
    .m_arready   (ic_m_arready),

    .m_rid       (ic_m_rid   ), .m_rdata  (ic_m_rdata   ), .m_rresp   (ic_m_rresp  ),
    .m_rlast     (ic_m_rlast ), .m_rvalid (ic_m_rvalid  ), .m_rready  (ic_m_rready ),

    .s_awid      (ic_s_awid  ), .s_awaddr (ic_s_awaddr  ), .s_awlen   (ic_s_awlen  ),
    .s_awsize    (ic_s_awsize), .s_awburst(ic_s_awburst ), .s_awlock  (ic_s_awlock ),
    .s_awcache   (ic_s_awcache),.s_awprot (ic_s_awprot  ), .s_awvalid (ic_s_awvalid),
    .s_awready   (ic_s_awready),

    .s_wid       (ic_s_wid   ), .s_wdata  (ic_s_wdata   ), .s_wstrb   (ic_s_wstrb  ),
    .s_wlast     (ic_s_wlast ), .s_wvalid (ic_s_wvalid  ), .s_wready  (ic_s_wready ),

    .s_bid       (ic_s_bid   ), .s_bresp  (ic_s_bresp   ), .s_bvalid  (ic_s_bvalid ),
    .s_bready    (ic_s_bready),

    .s_arid      (ic_s_arid  ), .s_araddr (ic_s_araddr  ), .s_arlen   (ic_s_arlen  ),
    .s_arsize    (ic_s_arsize), .s_arburst(ic_s_arburst ), .s_arlock  (ic_s_arlock ),
    .s_arcache   (ic_s_arcache),.s_arprot (ic_s_arprot  ), .s_arvalid (ic_s_arvalid),
    .s_arready   (ic_s_arready),

    .s_rid       (ic_s_rid   ), .s_rdata  (ic_s_rdata   ), .s_rresp   (ic_s_rresp  ),
    .s_rlast     (ic_s_rlast ), .s_rvalid (ic_s_rvalid  ), .s_rready  (ic_s_rready )
  );

  //=====================================================================
  // S0 : APB-BRIDGE  (出去 -> godson_mcu_cpu 内的 axi2apb_bridge)
  //=====================================================================
  assign apb_s_awid   = ic_s_awid   [0*`LID     +: `LID     ];
  assign apb_s_awaddr = ic_s_awaddr [0*`LAWADDR +: `LAWADDR ];
  assign apb_s_awlen  = ic_s_awlen  [0*`LAWLEN  +: `LAWLEN  ];
  assign apb_s_awsize = ic_s_awsize [0*`LAWSIZE +: `LAWSIZE ];
  assign apb_s_awburst= ic_s_awburst[0*`LAWBURST+: `LAWBURST];
  assign apb_s_awlock = ic_s_awlock [0*`LAWLOCK +: `LAWLOCK ];
  assign apb_s_awcache= ic_s_awcache[0*`LAWCACHE+: `LAWCACHE];
  assign apb_s_awprot = ic_s_awprot [0*`LAWPROT +: `LAWPROT ];
  assign apb_s_awvalid= ic_s_awvalid[0];
  assign ic_s_awready [0] = apb_s_awready;

  assign apb_s_wid    = ic_s_wid    [0*`LID     +: `LID     ];
  assign apb_s_wdata  = ic_s_wdata  [0*`LWDATA  +: `LWDATA  ];
  assign apb_s_wstrb  = ic_s_wstrb  [0*`LWSTRB  +: `LWSTRB  ];
  assign apb_s_wlast  = ic_s_wlast  [0];
  assign apb_s_wvalid = ic_s_wvalid [0];
  assign ic_s_wready  [0] = apb_s_wready;

  assign ic_s_bid     [0*`LID   +: `LID   ] = apb_s_bid   ;
  assign ic_s_bresp   [0*`LBRESP+: `LBRESP] = apb_s_bresp ;
  assign ic_s_bvalid  [0] = apb_s_bvalid;
  assign apb_s_bready     = ic_s_bready  [0];

  assign apb_s_arid   = ic_s_arid   [0*`LID     +: `LID     ];
  assign apb_s_araddr = ic_s_araddr [0*`LARADDR +: `LARADDR ];
  assign apb_s_arlen  = ic_s_arlen  [0*`LARLEN  +: `LARLEN  ];
  assign apb_s_arsize = ic_s_arsize [0*`LARSIZE +: `LARSIZE ];
  assign apb_s_arburst= ic_s_arburst[0*`LARBURST+: `LARBURST];
  assign apb_s_arlock = ic_s_arlock [0*`LARLOCK +: `LARLOCK ];
  assign apb_s_arcache= ic_s_arcache[0*`LARCACHE+: `LARCACHE];
  assign apb_s_arprot = ic_s_arprot [0*`LARPROT +: `LARPROT ];
  assign apb_s_arvalid= ic_s_arvalid[0];
  assign ic_s_arready [0] = apb_s_arready;

  assign ic_s_rid     [0*`LID   +: `LID   ] = apb_s_rid   ;
  assign ic_s_rdata   [0*`LRDATA+: `LRDATA] = apb_s_rdata ;
  assign ic_s_rresp   [0*`LRRESP+: `LRRESP] = apb_s_rresp ;
  assign ic_s_rlast   [0] = apb_s_rlast  ;
  assign ic_s_rvalid  [0] = apb_s_rvalid ;
  assign apb_s_rready     = ic_s_rready  [0];

  //=====================================================================
  // S1 : DMAC 配置寄存器 (axi_dma)
  //=====================================================================
  axi_dma #(
    .BURST (16)
  )u_dma (
    .aclk        (aclk    ),
    .aresetn     (aresetn ),

    .s_awid      (ic_s_awid   [1*`LID     +: `LID     ]),
    .s_awaddr    (ic_s_awaddr [1*`LAWADDR +: `LAWADDR ]),
    .s_awlen     (ic_s_awlen  [1*`LAWLEN  +: `LAWLEN  ]),
    .s_awsize    (ic_s_awsize [1*`LAWSIZE +: `LAWSIZE ]),
    .s_awburst   (ic_s_awburst[1*`LAWBURST+: `LAWBURST]),
    .s_awlock    (ic_s_awlock [1*`LAWLOCK +: `LAWLOCK ]),
    .s_awcache   (ic_s_awcache[1*`LAWCACHE+: `LAWCACHE]),
    .s_awprot    (ic_s_awprot [1*`LAWPROT +: `LAWPROT ]),
    .s_awvalid   (ic_s_awvalid[1]),
    .s_awready   (ic_s_awready[1]),

    .s_wid       (ic_s_wid    [1*`LID     +: `LID     ]),
    .s_wdata     (ic_s_wdata  [1*`LWDATA  +: `LWDATA  ]),
    .s_wstrb     (ic_s_wstrb  [1*`LWSTRB  +: `LWSTRB  ]),
    .s_wlast     (ic_s_wlast  [1]),
    .s_wvalid    (ic_s_wvalid [1]),
    .s_wready    (ic_s_wready [1]),

    .s_bid       (ic_s_bid    [1*`LID     +: `LID     ]),
    .s_bresp     (ic_s_bresp  [1*`LBRESP  +: `LBRESP  ]),
    .s_bvalid    (ic_s_bvalid [1]),
    .s_bready    (ic_s_bready [1]),

    .s_arid      (ic_s_arid   [1*`LID     +: `LID     ]),
    .s_araddr    (ic_s_araddr [1*`LARADDR +: `LARADDR ]),
    .s_arlen     (ic_s_arlen  [1*`LARLEN  +: `LARLEN  ]),
    .s_arsize    (ic_s_arsize [1*`LARSIZE +: `LARSIZE ]),
    .s_arburst   (ic_s_arburst[1*`LARBURST+: `LARBURST]),
    .s_arlock    (ic_s_arlock [1*`LARLOCK +: `LARLOCK ]),
    .s_arcache   (ic_s_arcache[1*`LARCACHE+: `LARCACHE]),
    .s_arprot    (ic_s_arprot [1*`LARPROT +: `LARPROT ]),
    .s_arvalid   (ic_s_arvalid[1]),
    .s_arready   (ic_s_arready[1]),

    .s_rid       (ic_s_rid    [1*`LID     +: `LID     ]),
    .s_rdata     (ic_s_rdata  [1*`LRDATA  +: `LRDATA  ]),
    .s_rresp     (ic_s_rresp  [1*`LRRESP  +: `LRRESP  ]),
    .s_rlast     (ic_s_rlast  [1]),
    .s_rvalid    (ic_s_rvalid [1]),
    .s_rready    (ic_s_rready [1]),

    // ---- 主口 (M1) ----
    .m_arid      (dma_m_arid   ),
    .m_araddr    (dma_m_araddr ),
    .m_arlen     (dma_m_arlen  ),
    .m_arsize    (dma_m_arsize ),
    .m_arburst   (dma_m_arburst),
    .m_arlock    (dma_m_arlock ),
    .m_arcache   (dma_m_arcache),
    .m_arprot    (dma_m_arprot ),
    .m_arvalid   (dma_m_arvalid),
    .m_arready   (dma_m_arready),

    .m_rid       (dma_m_rid    ),
    .m_rdata     (dma_m_rdata  ),
    .m_rresp     (dma_m_rresp  ),
    .m_rlast     (dma_m_rlast  ),
    .m_rvalid    (dma_m_rvalid ),
    .m_rready    (dma_m_rready ),

    .m_awid      (dma_m_awid   ),
    .m_awaddr    (dma_m_awaddr ),
    .m_awlen     (dma_m_awlen  ),
    .m_awsize    (dma_m_awsize ),
    .m_awburst   (dma_m_awburst),
    .m_awlock    (dma_m_awlock ),
    .m_awcache   (dma_m_awcache),
    .m_awprot    (dma_m_awprot ),
    .m_awvalid   (dma_m_awvalid),
    .m_awready   (dma_m_awready),

    .m_wid       (dma_m_wid    ),
    .m_wdata     (dma_m_wdata  ),
    .m_wstrb     (dma_m_wstrb  ),
    .m_wlast     (dma_m_wlast  ),
    .m_wvalid    (dma_m_wvalid ),
    .m_wready    (dma_m_wready ),

    .m_bid       (dma_m_bid    ),
    .m_bresp     (dma_m_bresp  ),
    .m_bvalid    (dma_m_bvalid ),
    .m_bready    (dma_m_bready ),

    .dma_irq     (dma_irq      )
  );

  //=====================================================================
  // S2 : LCD 配置寄存器 + 显存读出主口 (axi_lcd)
  //=====================================================================
  //  ⚠️ 不要在这里覆盖 FB_DEPTH_LOG / PREFILL ！！
  //     显存映射粒度是「1024 字 = 一行」(800 字可见 + 224 字余量), 预取缓冲
  //     必须 >= 一整行。模块默认 FB_DEPTH_LOG=10 (1024 字) / PREFILL=800 即
  //     正确值, 直接沿用, 保证 SoC / TB / 模块三方单一来源。
  //     历史 bug: 此处曾把这两项覆盖成 9 与 256 (即 512 字) -> 缓冲只有 512 字
  //     < 一整行 800 字, 行首节流 (LINE_LEVEL) 永不满足 -> 显示冻结, 现象 =
  //     「屏幕全白 + 无帧同步 (wait_frame 超时) + 状态寄存器 fill 恒 512」。
  axi_lcd #(
    .COLOR_WIDTH  (24 ),
    .MAX_OUT      (4  ),
    .BURST_LEN    (16 )
  ) u_lcd (
    .aclk        (aclk    ),
    .aresetn     (aresetn ),

    .s_awid      (ic_s_awid   [2*`LID     +: `LID     ]),
    .s_awaddr    (ic_s_awaddr [2*`LAWADDR +: `LAWADDR ]),
    .s_awlen     (ic_s_awlen  [2*`LAWLEN  +: `LAWLEN  ]),
    .s_awsize    (ic_s_awsize [2*`LAWSIZE +: `LAWSIZE ]),
    .s_awburst   (ic_s_awburst[2*`LAWBURST+: `LAWBURST]),
    .s_awlock    (ic_s_awlock [2*`LAWLOCK +: `LAWLOCK ]),
    .s_awcache   (ic_s_awcache[2*`LAWCACHE+: `LAWCACHE]),
    .s_awprot    (ic_s_awprot [2*`LAWPROT +: `LAWPROT ]),
    .s_awvalid   (ic_s_awvalid[2]),
    .s_awready   (ic_s_awready[2]),

    .s_wid       (ic_s_wid    [2*`LID     +: `LID     ]),
    .s_wdata     (ic_s_wdata  [2*`LWDATA  +: `LWDATA  ]),
    .s_wstrb     (ic_s_wstrb  [2*`LWSTRB  +: `LWSTRB  ]),
    .s_wlast     (ic_s_wlast  [2]),
    .s_wvalid    (ic_s_wvalid [2]),
    .s_wready    (ic_s_wready [2]),

    .s_bid       (ic_s_bid    [2*`LID     +: `LID     ]),
    .s_bresp     (ic_s_bresp  [2*`LBRESP  +: `LBRESP  ]),
    .s_bvalid    (ic_s_bvalid [2]),
    .s_bready    (ic_s_bready [2]),

    .s_arid      (ic_s_arid   [2*`LID     +: `LID     ]),
    .s_araddr    (ic_s_araddr [2*`LARADDR +: `LARADDR ]),
    .s_arlen     (ic_s_arlen  [2*`LARLEN  +: `LARLEN  ]),
    .s_arsize    (ic_s_arsize [2*`LARSIZE +: `LARSIZE ]),
    .s_arburst   (ic_s_arburst[2*`LARBURST+: `LARBURST]),
    .s_arlock    (ic_s_arlock [2*`LARLOCK +: `LARLOCK ]),
    .s_arcache   (ic_s_arcache[2*`LARCACHE+: `LARCACHE]),
    .s_arprot    (ic_s_arprot [2*`LARPROT +: `LARPROT ]),
    .s_arvalid   (ic_s_arvalid[2]),
    .s_arready   (ic_s_arready[2]),

    .s_rid       (ic_s_rid    [2*`LID     +: `LID     ]),
    .s_rdata     (ic_s_rdata  [2*`LRDATA  +: `LRDATA  ]),
    .s_rresp     (ic_s_rresp  [2*`LRRESP  +: `LRRESP  ]),
    .s_rlast     (ic_s_rlast  [2]),
    .s_rvalid    (ic_s_rvalid [2]),
    .s_rready    (ic_s_rready [2]),

    // ---- 主口 (M2) ----
    .m_arid      (lcd_m_arid   ),
    .m_araddr    (lcd_m_araddr ),
    .m_arlen     (lcd_m_arlen  ),
    .m_arsize    (lcd_m_arsize ),
    .m_arburst   (lcd_m_arburst),
    .m_arlock    (lcd_m_arlock ),
    .m_arcache   (lcd_m_arcache),
    .m_arprot    (lcd_m_arprot ),
    .m_arvalid   (lcd_m_arvalid),
    .m_arready   (lcd_m_arready),

    .m_rid       (lcd_m_rid    ),
    .m_rdata     (lcd_m_rdata  ),
    .m_rresp     (lcd_m_rresp  ),
    .m_rlast     (lcd_m_rlast  ),
    .m_rvalid    (lcd_m_rvalid ),
    .m_rready    (lcd_m_rready ),

    .m_awid      (lcd_m_awid   ),
    .m_awaddr    (lcd_m_awaddr ),
    .m_awlen     (lcd_m_awlen  ),
    .m_awsize    (lcd_m_awsize ),
    .m_awburst   (lcd_m_awburst),
    .m_awlock    (lcd_m_awlock ),
    .m_awcache   (lcd_m_awcache),
    .m_awprot    (lcd_m_awprot ),
    .m_awvalid   (lcd_m_awvalid),
    .m_awready   (lcd_m_awready),

    .m_wid       (lcd_m_wid    ),
    .m_wdata     (lcd_m_wdata  ),
    .m_wstrb     (lcd_m_wstrb  ),
    .m_wlast     (lcd_m_wlast  ),
    .m_wvalid    (lcd_m_wvalid ),
    .m_wready    (lcd_m_wready ),

    .m_bid       (lcd_m_bid    ),
    .m_bresp     (lcd_m_bresp  ),
    .m_bvalid    (lcd_m_bvalid ),
    .m_bready    (lcd_m_bready ),

    // ---- LCD 物理侧 ----
    .lcd_sys_clk (lcd_sys_clk  ),
    .lcd_sys_rstn(lcd_sys_rstn ),
    .lcd_id      (lcd_id       ),
    .lcd_clk     (lcd_clk      ),
    .lcd_rstn    (lcd_rstn     ),
    .lcd_de      (lcd_de       ),
    .lcd_bl      (lcd_bl       ),
    .lcd_hs      (lcd_hs       ),
    .lcd_vs      (lcd_vs       ),
    .lcd_rgb     (lcd_rgb      ),
    .lcd_irq     (lcd_irq      )
  );

  //=====================================================================
  // S3 : DDR3 (axi_ddr_slave -> MIG)
  //=====================================================================
  axi_ddr_slave #(
    .MIG_ADDR_WIDTH (30),
    .MIG_ID_WIDTH   (4 )
  ) u_ddr (
    .soc_aclk      (aclk    ),
    .soc_aresetn   (aresetn ),

    .s1_awid       (ic_s_awid   [3*`LID     +: `LID     ]),
    .s1_awaddr     (ic_s_awaddr [3*`LAWADDR +: `LAWADDR ]),
    .s1_awlen      (ic_s_awlen  [3*`LAWLEN  +: `LAWLEN  ]),
    .s1_awsize     (ic_s_awsize [3*`LAWSIZE +: `LAWSIZE ]),
    .s1_awburst    (ic_s_awburst[3*`LAWBURST+: `LAWBURST]),
    .s1_awlock     (ic_s_awlock [3*`LAWLOCK +: `LAWLOCK ]),
    .s1_awcache    (ic_s_awcache[3*`LAWCACHE+: `LAWCACHE]),
    .s1_awprot     (ic_s_awprot [3*`LAWPROT +: `LAWPROT ]),
    .s1_awvalid    (ic_s_awvalid[3]),
    .s1_awready    (ic_s_awready[3]),

    .s1_wid        (ic_s_wid    [3*`LID     +: `LID     ]),
    .s1_wdata      (ic_s_wdata  [3*`LWDATA  +: `LWDATA  ]),
    .s1_wstrb      (ic_s_wstrb  [3*`LWSTRB  +: `LWSTRB  ]),
    .s1_wlast      (ic_s_wlast  [3]),
    .s1_wvalid     (ic_s_wvalid [3]),
    .s1_wready     (ic_s_wready [3]),

    .s1_bid        (ic_s_bid    [3*`LID     +: `LID     ]),
    .s1_bresp      (ic_s_bresp  [3*`LBRESP  +: `LBRESP  ]),
    .s1_bvalid     (ic_s_bvalid [3]),
    .s1_bready     (ic_s_bready [3]),

    .s1_arid       (ic_s_arid   [3*`LID     +: `LID     ]),
    .s1_araddr     (ic_s_araddr [3*`LARADDR +: `LARADDR ]),
    .s1_arlen      (ic_s_arlen  [3*`LARLEN  +: `LARLEN  ]),
    .s1_arsize     (ic_s_arsize [3*`LARSIZE +: `LARSIZE ]),
    .s1_arburst    (ic_s_arburst[3*`LARBURST+: `LARBURST]),
    .s1_arlock     (ic_s_arlock [3*`LARLOCK +: `LARLOCK ]),
    .s1_arcache    (ic_s_arcache[3*`LARCACHE+: `LARCACHE]),
    .s1_arprot     (ic_s_arprot [3*`LARPROT +: `LARPROT ]),
    .s1_arvalid    (ic_s_arvalid[3]),
    .s1_arready    (ic_s_arready[3]),

    .s1_rid        (ic_s_rid    [3*`LID     +: `LID     ]),
    .s1_rdata      (ic_s_rdata  [3*`LRDATA  +: `LRDATA  ]),
    .s1_rresp      (ic_s_rresp  [3*`LRRESP  +: `LRRESP  ]),
    .s1_rlast      (ic_s_rlast  [3]),
    .s1_rvalid     (ic_s_rvalid [3]),
    .s1_rready     (ic_s_rready [3]),

    // ---- DDR3 物理 ----
    .ddr_refclk          (ddr_refclk         ),
    .ddr_sys_rst         (ddr_sys_rst        ),
    .init_calib_complete (init_calib_complete),
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
    .ddr3_odt            (ddr3_odt           )
  );

endmodule
