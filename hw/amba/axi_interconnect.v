`timescale 1ns / 1ps
//=====================================================================
//  File   : axi_interconnect.v
//  Brief  : 3 主 x 4 从 AXI4 互联矩阵  (LA132 SoC / 云晓 100T 实验箱)
//  Author : WorkBuddy
//---------------------------------------------------------------------
//  主设备 (M)
//    M0 : CPU      (LA132, 来自 la132_top 的 AXI 主口)
//    M1 : DMAC     (axi_dma  主口, 读写 DDR)
//    M2 : LCD      (axi_lcd  主口, 只读 DDR 显存)
//
//  从设备 (S)   —— 地址窗口见 config.vh 中的 AXI_SLVx_ADDR_* 宏
//    S0 : APB-BRIDGE   axi2apb_bridge -> apb_bridge -> 所有 APB 外设   【默认窗口】
//    S1 : DMAC         axi_dma  配置寄存器 (0x2001_0000, 64KB)
//    S2 : LCD          axi_lcd  配置寄存器 (0x2000_0000, 64KB)
//    S3 : DDR          axi_ddr_slave -> MIG               (0x4000_0000, 1GB)
//
//  设计要点
//  --------------------------------------------------------------------
//  1) 端口采用「打包向量」风格 (与工程 apb_bridge.sv 一致), 便于 generate:
//        第 i 路切片 = 总线名[i*WIDTH +: WIDTH]
//  2) 写通道 (AW/W/B) 采用「单事务独占」: 从 W_IDLE 选中一路主设备后,
//     一直占有到该笔写事务 B 响应握手完成。写流量低频, 无需流水,
//     同时天然保证「跨主设备写顺序」与「B 响应路由」的确定性。
//  3) 读通道 (AR/R) 允许「同从设备 + 同主设备 + 同 ID」多笔流水:
//       - rd_route_fifo 记录每笔在途 AR 的主设备号, R 数据按 FIFO 顺序
//         回送到对应主设备;
//       - 同从设备 + 同 ID 的多笔 AR, AXI 协议保证按序返回,
//         故「FIFO 顺序 == 数据顺序」, 路由必然正确;
//       - 一旦出现「不同从设备」或「不同主设备」的 AR 在等待,
//         立即停止接收新 AR (rd_switch_req), 待 FIFO 排空后切换,
//         保证公平性与有界延迟。
//      —— 这是 LCD 显存预取能获得高带宽的关键: LCD 主口以固定 ID=0
//         连续发多笔 16 拍突发, 互联不会每笔都锁死等待。
//  4) 地址译码 : DDR (1GB, 0x4000_0000 ~ 0x7FFF_FFFF) 与 LCD(0x2000_0000) /
//     DMAC(0x2001_0000) 两个 64KB 配置窗口互不重叠, 顺序不影响功能。
//     早期版本曾把两个配置窗口放在 DDR 窗口内部, 只能靠优先级顺序绕开,
//     详见 dec_slave 里的说明。
//  5) 互联对 len/size/burst 全透明; 不支持的事务由从设备自行返回错误。
//=====================================================================

`include "config.vh"

module axi_interconnect #(
  parameter N_MASTER          = 3,
  parameter N_SLAVE           = 4,
  parameter RD_FIFO_DEPTH_LOG = 3       // 读路由 FIFO 深度 = 2^3 = 8
) (
  input  wire                              aclk,
  input  wire                              aresetn,

  // ================= 主设备侧 (打包) =================
  input  wire [N_MASTER*`LID      -1:0]    m_awid,
  input  wire [N_MASTER*`LAWADDR  -1:0]    m_awaddr,
  input  wire [N_MASTER*`LAWLEN   -1:0]    m_awlen,
  input  wire [N_MASTER*`LAWSIZE  -1:0]    m_awsize,
  input  wire [N_MASTER*`LAWBURST -1:0]    m_awburst,
  input  wire [N_MASTER*`LAWLOCK  -1:0]    m_awlock,
  input  wire [N_MASTER*`LAWCACHE -1:0]    m_awcache,
  input  wire [N_MASTER*`LAWPROT  -1:0]    m_awprot,
  input  wire [N_MASTER           -1:0]    m_awvalid,
  output wire [N_MASTER           -1:0]    m_awready,

  input  wire [N_MASTER*`LID      -1:0]    m_wid,
  input  wire [N_MASTER*`LWDATA   -1:0]    m_wdata,
  input  wire [N_MASTER*`LWSTRB   -1:0]    m_wstrb,
  input  wire [N_MASTER           -1:0]    m_wlast,
  input  wire [N_MASTER           -1:0]    m_wvalid,
  output wire [N_MASTER           -1:0]    m_wready,

  output wire [N_MASTER*`LID      -1:0]    m_bid,
  output wire [N_MASTER*`LBRESP   -1:0]    m_bresp,
  output wire [N_MASTER           -1:0]    m_bvalid,
  input  wire [N_MASTER           -1:0]    m_bready,

  input  wire [N_MASTER*`LID      -1:0]    m_arid,
  input  wire [N_MASTER*`LARADDR  -1:0]    m_araddr,
  input  wire [N_MASTER*`LARLEN   -1:0]    m_arlen,
  input  wire [N_MASTER*`LARSIZE  -1:0]    m_arsize,
  input  wire [N_MASTER*`LARBURST -1:0]    m_arburst,
  input  wire [N_MASTER*`LARLOCK  -1:0]    m_arlock,
  input  wire [N_MASTER*`LARCACHE -1:0]    m_arcache,
  input  wire [N_MASTER*`LARPROT  -1:0]    m_arprot,
  input  wire [N_MASTER           -1:0]    m_arvalid,
  output wire [N_MASTER           -1:0]    m_arready,

  output wire [N_MASTER*`LID      -1:0]    m_rid,
  output wire [N_MASTER*`LRDATA   -1:0]    m_rdata,
  output wire [N_MASTER*`LRRESP   -1:0]    m_rresp,
  output wire [N_MASTER           -1:0]    m_rlast,
  output wire [N_MASTER           -1:0]    m_rvalid,
  input  wire [N_MASTER           -1:0]    m_rready,

  // ================= 从设备侧 (打包) =================
  output wire [N_SLAVE *`LID      -1:0]    s_awid,
  output wire [N_SLAVE *`LAWADDR  -1:0]    s_awaddr,
  output wire [N_SLAVE *`LAWLEN   -1:0]    s_awlen,
  output wire [N_SLAVE *`LAWSIZE  -1:0]    s_awsize,
  output wire [N_SLAVE *`LAWBURST -1:0]    s_awburst,
  output wire [N_SLAVE *`LAWLOCK  -1:0]    s_awlock,
  output wire [N_SLAVE *`LAWCACHE -1:0]    s_awcache,
  output wire [N_SLAVE *`LAWPROT  -1:0]    s_awprot,
  output wire [N_SLAVE            -1:0]    s_awvalid,
  input  wire [N_SLAVE            -1:0]    s_awready,

  output wire [N_SLAVE *`LID      -1:0]    s_wid,
  output wire [N_SLAVE *`LWDATA   -1:0]    s_wdata,
  output wire [N_SLAVE *`LWSTRB   -1:0]    s_wstrb,
  output wire [N_SLAVE            -1:0]    s_wlast,
  output wire [N_SLAVE            -1:0]    s_wvalid,
  input  wire [N_SLAVE            -1:0]    s_wready,

  input  wire [N_SLAVE *`LID      -1:0]    s_bid,
  input  wire [N_SLAVE *`LBRESP   -1:0]    s_bresp,
  input  wire [N_SLAVE            -1:0]    s_bvalid,
  output wire [N_SLAVE            -1:0]    s_bready,

  output wire [N_SLAVE *`LID      -1:0]    s_arid,
  output wire [N_SLAVE *`LARADDR  -1:0]    s_araddr,
  output wire [N_SLAVE *`LARLEN   -1:0]    s_arlen,
  output wire [N_SLAVE *`LARSIZE  -1:0]    s_arsize,
  output wire [N_SLAVE *`LARBURST -1:0]    s_arburst,
  output wire [N_SLAVE *`LARLOCK  -1:0]    s_arlock,
  output wire [N_SLAVE *`LARCACHE -1:0]    s_arcache,
  output wire [N_SLAVE *`LARPROT  -1:0]    s_arprot,
  output wire [N_SLAVE            -1:0]    s_arvalid,
  input  wire [N_SLAVE            -1:0]    s_arready,

  input  wire [N_SLAVE *`LID      -1:0]    s_rid,
  input  wire [N_SLAVE *`LRDATA   -1:0]    s_rdata,
  input  wire [N_SLAVE *`LRRESP   -1:0]    s_rresp,
  input  wire [N_SLAVE            -1:0]    s_rlast,
  input  wire [N_SLAVE            -1:0]    s_rvalid,
  output wire [N_SLAVE            -1:0]    s_rready
);

  localparam SLV_W = 2;                 // 从设备编号位宽 (N_SLAVE = 4)
  localparam MST_W = 2;                 // 主设备编号位宽 (N_MASTER = 3, 用 2bit)

  //=====================================================================
  // 0. 地址译码
  //=====================================================================
  function [SLV_W-1:0] dec_slave;
    input [`LAWADDR-1:0] addr;
    begin
      // 三个从设备窗口互不重叠 (地址宏见 config.vh), 译码顺序不影响功能。
      // 此处按地址由低到高排列, 便于与地址表对照 :
      //   0x2000_0000 ~ 0x2000_FFFF  AXI-LCD   配置寄存器
      //   0x2001_0000 ~ 0x2001_FFFF  AXI-DMAC  配置寄存器
      //   0x4000_0000 ~ 0x7FFF_FFFF  DDR3      (1GB, 兼作 LCD 显存)
      //   其余地址                    APB-BRIDGE (S0 默认窗口, APB 段在
      //                               0x3000_0000 ~ 0x3010_FFFF / 0x3200_0000 /
      //                               0x3300_0000, 见 apb_addr.svh)
      //
      // !! 历史坑, 不要改回去 !! 早期版本把 DMAC / LCD 放在 0x3000_0000 /
      // 0x3001_0000, 而 DDR 的 mask 会覆盖 0x2000_0000 ~ 0x3FFF_FFFF 整个
      // 512MB —— 那两个 64KB 窗口会被 DDR 完整吞掉, 当时只能靠
      // "DMAC > LCD > DDR" 的优先级顺序绕开。现在地址已经分开,
      // 新增 AXI 外设时务必放到 DDR 窗口 (0x4000_0000~0x7FFF_FFFF) 之外,
      // 且必须留在直连区 0x0000_0000 ~ 0x7FFF_FFFF 内 (原因见 config.vh)。
      if      ((addr & `AXI_SLV_DDR_ADDR_MASK) == `AXI_SLV_DDR_ADDR_BASE) dec_slave = 2'd3;
      else if ((addr & `AXI_SLV_LCD_ADDR_MASK) == `AXI_SLV_LCD_ADDR_BASE) dec_slave = 2'd2;
      else if ((addr & `AXI_SLV_DMA_ADDR_MASK) == `AXI_SLV_DMA_ADDR_BASE) dec_slave = 2'd1;
      else                                                               dec_slave = 2'd0;
    end
  endfunction

  //=====================================================================
  // 1. 写通道 (AW / W / B)
  //=====================================================================
  localparam W_IDLE = 2'd0,
             W_DATA = 2'd1,
             W_RESP = 2'd2;

  reg  [1:0]       wr_state;
  reg  [MST_W-1:0] wr_owner;
  reg  [SLV_W-1:0] wr_slv;
  reg  [MST_W-1:0] wr_rr;

  reg  [MST_W-1:0] aw_gnt;
  reg              aw_gnt_v;

  // ---- 轮转仲裁 (N_MASTER = 3) ----
  always @(*) begin
    aw_gnt   = 2'd0;
    aw_gnt_v = 1'b1;
    case (wr_rr)
      2'd0: begin
        if      (m_awvalid[0]) aw_gnt = 2'd0;
        else if (m_awvalid[1]) aw_gnt = 2'd1;
        else if (m_awvalid[2]) aw_gnt = 2'd2;
        else                   aw_gnt_v = 1'b0;
      end
      2'd1: begin
        if      (m_awvalid[1]) aw_gnt = 2'd1;
        else if (m_awvalid[2]) aw_gnt = 2'd2;
        else if (m_awvalid[0]) aw_gnt = 2'd0;
        else                   aw_gnt_v = 1'b0;
      end
      default: begin
        if      (m_awvalid[2]) aw_gnt = 2'd2;
        else if (m_awvalid[0]) aw_gnt = 2'd0;
        else if (m_awvalid[1]) aw_gnt = 2'd1;
        else                   aw_gnt_v = 1'b0;
      end
    endcase
  end

  wire [SLV_W-1:0] aw_slv_now = dec_slave(m_awaddr[aw_gnt*`LAWADDR +: `LAWADDR]);

  wire aw_hs = (wr_state == W_IDLE) && aw_gnt_v && s_awready[aw_slv_now];
  wire w_hs  = (wr_state == W_DATA) && m_wvalid[wr_owner] && s_wready[wr_slv];
  wire b_hs  = (wr_state == W_RESP) && s_bvalid[wr_slv] && m_bready[wr_owner];

  always @(posedge aclk) begin
    if (!aresetn) begin
      wr_state <= W_IDLE;
      wr_owner <= {MST_W{1'b0}};
      wr_slv   <= {SLV_W{1'b0}};
      wr_rr    <= {MST_W{1'b0}};
    end
    else begin
      case (wr_state)
        W_IDLE: if (aw_hs) begin
          wr_owner <= aw_gnt;
          wr_slv   <= aw_slv_now;
          wr_state <= W_DATA;
          wr_rr    <= (aw_gnt == 2'd2) ? 2'd0 : (aw_gnt + 2'd1);
        end
        W_DATA: if (w_hs && m_wlast[wr_owner]) wr_state <= W_RESP;
        W_RESP: if (b_hs) wr_state <= W_IDLE;
        default: wr_state <= W_IDLE;
      endcase
    end
  end

  genvar gi;
  generate
    for (gi = 0; gi < N_MASTER; gi = gi + 1) begin : g_aw_ready
      assign m_awready[gi] = (wr_state == W_IDLE) && aw_gnt_v && (aw_gnt == gi) &&
                             s_awready[dec_slave(m_awaddr[gi*`LAWADDR +: `LAWADDR])];
    end
    for (gi = 0; gi < N_MASTER; gi = gi + 1) begin : g_w_ready
      assign m_wready[gi] = (wr_state == W_DATA) && (wr_owner == gi) && s_wready[wr_slv];
    end
    for (gi = 0; gi < N_MASTER; gi = gi + 1) begin : g_b_out
      assign m_bvalid[gi]        = (wr_state == W_RESP) && (wr_owner == gi) && s_bvalid[wr_slv];
      assign m_bid   [gi*`LID   +: `LID   ] = s_bid  [wr_slv*`LID   +: `LID   ];
      assign m_bresp [gi*`LBRESP +: `LBRESP] = s_bresp[wr_slv*`LBRESP +: `LBRESP];
    end
    for (gi = 0; gi < N_SLAVE; gi = gi + 1) begin : g_aw_out
      assign s_awvalid[gi] = (wr_state == W_IDLE) && aw_gnt_v && (aw_slv_now == gi);
      assign s_awid   [gi*`LID      +: `LID      ] = m_awid   [aw_gnt*`LID      +: `LID      ];
      assign s_awaddr [gi*`LAWADDR  +: `LAWADDR  ] = m_awaddr [aw_gnt*`LAWADDR  +: `LAWADDR  ];
      assign s_awlen  [gi*`LAWLEN   +: `LAWLEN   ] = m_awlen  [aw_gnt*`LAWLEN   +: `LAWLEN   ];
      assign s_awsize [gi*`LAWSIZE  +: `LAWSIZE  ] = m_awsize [aw_gnt*`LAWSIZE  +: `LAWSIZE  ];
      assign s_awburst[gi*`LAWBURST +: `LAWBURST ] = m_awburst[aw_gnt*`LAWBURST +: `LAWBURST ];
      assign s_awlock [gi*`LAWLOCK  +: `LAWLOCK  ] = m_awlock [aw_gnt*`LAWLOCK  +: `LAWLOCK  ];
      assign s_awcache[gi*`LAWCACHE +: `LAWCACHE ] = m_awcache[aw_gnt*`LAWCACHE +: `LAWCACHE ];
      assign s_awprot [gi*`LAWPROT  +: `LAWPROT  ] = m_awprot [aw_gnt*`LAWPROT  +: `LAWPROT  ];

      assign s_wvalid[gi] = (wr_state == W_DATA) && (wr_slv == gi) && m_wvalid[wr_owner];
      assign s_wid   [gi*`LID      +: `LID      ] = m_wid   [wr_owner*`LID      +: `LID      ];
      assign s_wdata [gi*`LWDATA   +: `LWDATA   ] = m_wdata [wr_owner*`LWDATA   +: `LWDATA   ];
      assign s_wstrb [gi*`LWSTRB   +: `LWSTRB   ] = m_wstrb [wr_owner*`LWSTRB   +: `LWSTRB   ];
      assign s_wlast [gi] = (wr_state == W_DATA) && (wr_slv == gi) && m_wlast[wr_owner];

      assign s_bready[gi] = (wr_state == W_RESP) && (wr_slv == gi) && m_bready[wr_owner];
    end
  endgenerate

  //=====================================================================
  // 2. 读通道 (AR / R)
  //=====================================================================
  localparam RD_FIFO_DEPTH = (1 << RD_FIFO_DEPTH_LOG);

  reg  [MST_W-1:0]           rd_fifo_mem [0:RD_FIFO_DEPTH-1];
  reg  [RD_FIFO_DEPTH_LOG:0] rd_wptr, rd_rptr;

  wire rd_fifo_empty = (rd_wptr == rd_rptr);
  wire rd_fifo_full  = (rd_wptr[RD_FIFO_DEPTH_LOG-1:0] == rd_rptr[RD_FIFO_DEPTH_LOG-1:0]) &&
                       (rd_wptr[RD_FIFO_DEPTH_LOG]    != rd_rptr[RD_FIFO_DEPTH_LOG]);
  wire [MST_W-1:0] rd_head = rd_fifo_mem[rd_rptr[RD_FIFO_DEPTH_LOG-1:0]];

  reg  [SLV_W-1:0] rd_slv;          // 当前占据的从设备 (仅在 !rd_fifo_empty 时有效)
  reg              rd_busy;         // == !rd_fifo_empty (打一拍, 供 AR 受理判定)
  reg  [MST_W-1:0] rd_last_mst;     // 最近一次受理 AR 的主设备
  reg  [`LID-1:0]  rd_last_id;      // 最近一次受理 AR 的 ID

  // 各主设备 AR 的目标从设备
  wire [SLV_W-1:0] m_ar_slv_0 = dec_slave(m_araddr[0*`LARADDR +: `LARADDR]);
  wire [SLV_W-1:0] m_ar_slv_1 = dec_slave(m_araddr[1*`LARADDR +: `LARADDR]);
  wire [SLV_W-1:0] m_ar_slv_2 = dec_slave(m_araddr[2*`LARADDR +: `LARADDR]);

  // 是否存在「想切换到别的从设备 / 别的主设备」的 AR —— 用于让 FIFO 及时排空
  reg rd_switch_req;
  always @(*) begin
    rd_switch_req = 1'b0;
    if (rd_busy) begin
      if (m_arvalid[0] && ((m_ar_slv_0 != rd_slv) || (rd_last_mst != 2'd0))) rd_switch_req = 1'b1;
      if (m_arvalid[1] && ((m_ar_slv_1 != rd_slv) || (rd_last_mst != 2'd1))) rd_switch_req = 1'b1;
      if (m_arvalid[2] && ((m_ar_slv_2 != rd_slv) || (rd_last_mst != 2'd2))) rd_switch_req = 1'b1;
    end
  end

  wire [N_MASTER-1:0] ar_qual;
  assign ar_qual[0] = m_arvalid[0] && !rd_fifo_full &&
                      (!rd_busy || ((m_ar_slv_0 == rd_slv) && (rd_last_mst == 2'd0) &&
                                    (m_arid[0*`LID +: `LID] == rd_last_id))) &&
                      !rd_switch_req;
  assign ar_qual[1] = m_arvalid[1] && !rd_fifo_full &&
                      (!rd_busy || ((m_ar_slv_1 == rd_slv) && (rd_last_mst == 2'd1) &&
                                    (m_arid[1*`LID +: `LID] == rd_last_id))) &&
                      !rd_switch_req;
  assign ar_qual[2] = m_arvalid[2] && !rd_fifo_full &&
                      (!rd_busy || ((m_ar_slv_2 == rd_slv) && (rd_last_mst == 2'd2) &&
                                    (m_arid[2*`LID +: `LID] == rd_last_id))) &&
                      !rd_switch_req;

  reg [MST_W-1:0] ar_gnt;
  reg             ar_gnt_v;
  reg [MST_W-1:0] rd_rr;

  always @(*) begin
    ar_gnt   = 2'd0;
    ar_gnt_v = 1'b1;
    case (rd_rr)
      2'd0: begin
        if      (ar_qual[0]) ar_gnt = 2'd0;
        else if (ar_qual[1]) ar_gnt = 2'd1;
        else if (ar_qual[2]) ar_gnt = 2'd2;
        else                 ar_gnt_v = 1'b0;
      end
      2'd1: begin
        if      (ar_qual[1]) ar_gnt = 2'd1;
        else if (ar_qual[2]) ar_gnt = 2'd2;
        else if (ar_qual[0]) ar_gnt = 2'd0;
        else                 ar_gnt_v = 1'b0;
      end
      default: begin
        if      (ar_qual[2]) ar_gnt = 2'd2;
        else if (ar_qual[0]) ar_gnt = 2'd0;
        else if (ar_qual[1]) ar_gnt = 2'd1;
        else                 ar_gnt_v = 1'b0;
      end
    endcase
  end

  wire [SLV_W-1:0] ar_slv_now = (ar_gnt == 2'd0) ? m_ar_slv_0 :
                                (ar_gnt == 2'd1) ? m_ar_slv_1 : m_ar_slv_2;

  wire ar_hs  = ar_gnt_v && s_arready[ar_slv_now];
  wire rd_fin = !rd_fifo_empty && s_rvalid[rd_slv] && m_rready[rd_head] && s_rlast[rd_slv];

  wire [RD_FIFO_DEPTH_LOG:0] rd_wptr_nxt = rd_wptr + (ar_hs  ? 1'b1 : 1'b0);
  wire [RD_FIFO_DEPTH_LOG:0] rd_rptr_nxt = rd_rptr + (rd_fin ? 1'b1 : 1'b0);

  integer fi;
  always @(posedge aclk) begin
    if (!aresetn) begin
      rd_wptr     <= {(RD_FIFO_DEPTH_LOG+1){1'b0}};
      rd_rptr     <= {(RD_FIFO_DEPTH_LOG+1){1'b0}};
      rd_busy     <= 1'b0;
      rd_slv      <= {SLV_W{1'b0}};
      rd_last_mst <= {MST_W{1'b0}};
      rd_last_id  <= {`LID{1'b0}};
      rd_rr       <= {MST_W{1'b0}};
      for (fi = 0; fi < RD_FIFO_DEPTH; fi = fi + 1) rd_fifo_mem[fi] <= {MST_W{1'b0}};
    end
    else begin
      rd_wptr <= rd_wptr_nxt;
      rd_rptr <= rd_rptr_nxt;
      rd_busy <= (rd_wptr_nxt != rd_rptr_nxt);
      if (ar_hs) begin
        rd_fifo_mem[rd_wptr[RD_FIFO_DEPTH_LOG-1:0]] <= ar_gnt;
        rd_slv      <= ar_slv_now;
        rd_last_mst <= ar_gnt;
        rd_last_id  <= m_arid[ar_gnt*`LID +: `LID];
        rd_rr       <= (ar_gnt == 2'd2) ? 2'd0 : (ar_gnt + 2'd1);
      end
    end
  end

  generate
    for (gi = 0; gi < N_MASTER; gi = gi + 1) begin : g_ar_ready
      assign m_arready[gi] = ar_gnt_v && (ar_gnt == gi) &&
                             s_arready[(gi == 0) ? m_ar_slv_0 : (gi == 1) ? m_ar_slv_1 : m_ar_slv_2];
    end
    for (gi = 0; gi < N_SLAVE; gi = gi + 1) begin : g_ar_out
      assign s_arvalid[gi] = ar_gnt_v && (ar_slv_now == gi);
      assign s_arid   [gi*`LID      +: `LID      ] = m_arid   [ar_gnt*`LID      +: `LID      ];
      assign s_araddr [gi*`LARADDR  +: `LARADDR  ] = m_araddr [ar_gnt*`LARADDR  +: `LARADDR  ];
      assign s_arlen  [gi*`LARLEN   +: `LARLEN   ] = m_arlen  [ar_gnt*`LARLEN   +: `LARLEN   ];
      assign s_arsize [gi*`LARSIZE  +: `LARSIZE  ] = m_arsize [ar_gnt*`LARSIZE  +: `LARSIZE  ];
      assign s_arburst[gi*`LARBURST +: `LARBURST ] = m_arburst[ar_gnt*`LARBURST +: `LARBURST ];
      assign s_arlock [gi*`LARLOCK  +: `LARLOCK  ] = m_arlock [ar_gnt*`LARLOCK  +: `LARLOCK  ];
      assign s_arcache[gi*`LARCACHE +: `LARCACHE ] = m_arcache[ar_gnt*`LARCACHE +: `LARCACHE ];
      assign s_arprot [gi*`LARPROT  +: `LARPROT  ] = m_arprot [ar_gnt*`LARPROT  +: `LARPROT  ];
    end
    for (gi = 0; gi < N_MASTER; gi = gi + 1) begin : g_r_out
      assign m_rvalid[gi] = !rd_fifo_empty && (rd_head == gi) && s_rvalid[rd_slv];
      assign m_rlast [gi] = !rd_fifo_empty && (rd_head == gi) && s_rlast [rd_slv];
      assign m_rid   [gi*`LID   +: `LID   ] = s_rid  [rd_slv*`LID   +: `LID   ];
      assign m_rdata [gi*`LRDATA +: `LRDATA] = s_rdata[rd_slv*`LRDATA +: `LRDATA];
      assign m_rresp [gi*`LRRESP +: `LRRESP] = s_rresp[rd_slv*`LRRESP +: `LRRESP];
    end
    for (gi = 0; gi < N_SLAVE; gi = gi + 1) begin : g_r_ready
      assign s_rready[gi] = !rd_fifo_empty && (rd_slv == gi) && m_rready[rd_head];
    end
  endgenerate

endmodule
