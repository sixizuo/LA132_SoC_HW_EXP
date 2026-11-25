`timescale 1ns / 1ps
//=====================================================================
//  File   : axi_lcd.v
//  Brief  : 基于 AXI4 总线的 RGB LCD 驱动 (云晓 100T / LA132 SoC)
//  Author : WorkBuddy
//---------------------------------------------------------------------
//  功能
//  --------------------------------------------------------------------
//  1) AXI 从设备 (窗口 0x5200_0000 ~ 0x52FF_FFFF): CPU 通过它配置
//       - LCD_BUFFER : 显存起始地址 (DDR 字节地址, 强制 64 字节对齐)
//       - LCD_CTRL   : EN / GO(预取) / RGB 输出格式
//     并可回读 LCD_STATUS / LCD_FBSIZE / LCD_RES / LCD_ID。
//
//  2) AXI 主设备: 按「一个像素 = 一个 32bit 显存字」的规则从 DDR 突发读取显存。
//       字格式 : [31:24] 无意义  |  [23:16] R8  |  [15:8] G8  |  [7:0] B8
//     即 24bit 颜色 = 显存字[23:0]。
//
//  3) 像素时序: 派生自工程 apb_lcd 的 lcd_driver/clk_div, 因避免与 apb_lcd 重名已改为 axi_lcd_driver/axi_lcd_clkdiv
//       800x480 (lcd_id = 16'h4384),  pclk = lcd_sys_clk / 2 = 25MHz
//
//  数据通路与跨时钟设计 (本模块最关键的部分)
//  --------------------------------------------------------------------
//     aclk 域 (32MHz)                        lcd_pclk 域 (25MHz)
//     ┌───────────────────────┐              ┌────────────────────────┐
//     │ 预取引擎 (AXI 主口读)  │  环形双口RAM  │ lcd_driver 像素时序机   │
//     │  wptr : 绝对字索引     │──(BRAM)─────▶│  px_cnt : 绝对字索引    │
//     │  流控 = wptr - rd_idx  │              │  读地址 = px_cnt        │
//     └───────────────────────┘              └────────────────────────┘
//       ◀────────── rd_idx 格雷码同步 ─────────      wptr 格雷码同步 ──▶
//
//   * ★ 映射的原子单位是「**一行**」: 预取缓冲 = 1024 字
//     (= 一行可见像素 800 字 + 224 字余量)。
//     行首 (h_cnt==0) **只有缓冲里已经攒够整整一行 800 字**才放行这一行,
//     不够就冻结时序机 (= 拉长消隐, 屏上不可见)。行内**绝不节流**。
//
//     为什么这样就"位置绝对不漂": 整行数据在行首就已全部就位, 一行之内
//     读指针 px_cnt 永远追不上写指针 wptr, fill_level 不会回绕, 于是
//     「屏幕第 p 行 ↔ 显存第 p 行」的对应关系恒成立 —— 软件停在静态画面
//     时, 8 条色条的位置一动不动。
//
//   * 反面教材 (旧实现的坑, 也是"位置不停变化"的根因):
//     旧实现 disp_rstn = lcd_sys_rstn && buf_ready, 预取缓冲只要瞬时跌到
//     PREFILL 以下, 像素时序机就被**中途**拉回复位 (h_cnt/v_cnt 归 0), 而
//     px_cnt 继续走 -> 像素↔显存映射永久错位 px_cnt 个字 (= px_cnt/800 行),
//     每错一次再叠一次; 且 axi_lcd_driver 的 lcd_rstn 跟随 rstn, LCD **面板**
//     也被一起复位, 画面在玻璃上重新起扫 —— 位置又跳一次。
//     现在: 缓冲攒够 PREFILL 后 run_lat **一次性放行**, 运行期间任何
//     buf_ready 抖动都不再复位时序机; 面板复位只跟 panel_rstn (真正的
//     系统复位), 与流控彻底解耦。
//     回归用例: sim/tb_axi_system.v 的 T11。
//
//   * 为什么不用"行内随时复位/冻结"来节流: 一旦在可见区冻结 h_cnt,
//     data_req 会被拉长成持续为 1 -> px_cnt 暴涨甩开 wptr -> fill_level
//     回绕 -> 预取永久停摆 (实测"只显示 4 帧就停")。所以 hold 在
//     axi_lcd_driver 内部被**强制限定 h_cnt==0 才生效**。
//
//   * swrst (软件复位) 必须同步到 lcd_pclk 域一起清 px_cnt / run_lat:
//     否则 wptr 归 0 而 px_cnt 不动, fill_level = wptr - px_cnt 立刻回绕成
//     巨值 —— buf_ready 恒 0 且 used 恒 > FB_DEPTH, 预取永久停摆, 整屏死锁。
//
//   * 显存读地址 (AR) 必须**按帧回卷**: 显存只有一帧大小
//     (800*480 = 384000 字 = 0x17_7000 字节), 显示每帧都从头扫一遍。
//     因此 AR 用帧内偏移 ar_word (恒 < FB_WORDS) 而不是无界的 wptr。
//     若用无界索引当地址, 读地址每帧前移 0x17_7000, 只有第 1 帧读的是
//     显存, 第 2 帧起读到显存之外 —— 表现为"屏幕闪一下然后一直黑"。
//     回归用例: sim/tb_axi_system.v 的 T10。
//   * 流控 (写侧): 仅当 (wptr + 在途拍数 + 16) - rd_idx_sync <= FB_DEPTH 时才发新突发。
//   * 流控 (读侧): 缓冲首次攒够 PREFILL 后一次放行; 之后每行行首检查剩余字数
//     是否 >= LINE_LEVEL, 不足就冻结时序机 (= 拉长消隐), 保证
//     px_cnt <= wptr 恒成立, fill_level 永不回绕。
//   * 允许 MAX_OUT 笔在途突发 (固定 ID = 0), 配合互联矩阵「同从设备流水」,
//     16 拍突发可把 32bit@32MHz 的读带宽推到 ~27M 字/s,
//     远高于 800x480@25MHz 所需的 17.3M 字/s。
//   * LCD 主口只读, AW/W/B 通道恒无效。
//=====================================================================

`include "config.vh"

module axi_lcd #(
  parameter COLOR_WIDTH   = 24,
  parameter FB_DEPTH_LOG  = 10,     // 环形预取缓冲 = 2^10 = 1024 字 = 一整行的 800 字 + 224 字余量
  parameter PREFILL       = 800,    // 显示启动阈值 (字) = 一整行: 只攒够整整一行才首次放行, 保证第 1 行绝不欠载
  parameter LINE_LEVEL    = 800,    // 行首整行阈值: 行首剩余字数必须 >= 一整行才放行该行
  parameter MAX_OUT       = 4,      // 最大在途读突发数
  parameter BURST_LEN     = 16      // 每笔突发拍数 (1..16, 建议 16)
) (
  // ================= AXI 时钟域 (SoC, 32MHz) =================
  input  wire                        aclk,
  input  wire                        aresetn,

  // ---------------- AXI 从设备 : 配置寄存器 ----------------
  input  wire [`LID      -1:0]       s_awid,
  input  wire [`LAWADDR  -1:0]       s_awaddr,
  input  wire [`LAWLEN   -1:0]       s_awlen,
  input  wire [`LAWSIZE  -1:0]       s_awsize,
  input  wire [`LAWBURST -1:0]       s_awburst,
  input  wire [`LAWLOCK  -1:0]       s_awlock,
  input  wire [`LAWCACHE -1:0]       s_awcache,
  input  wire [`LAWPROT  -1:0]       s_awprot,
  input  wire                        s_awvalid,
  output wire                        s_awready,

  input  wire [`LID      -1:0]       s_wid,
  input  wire [`LWDATA   -1:0]       s_wdata,
  input  wire [`LWSTRB   -1:0]       s_wstrb,
  input  wire                        s_wlast,
  input  wire                        s_wvalid,
  output wire                        s_wready,

  output wire [`LID      -1:0]       s_bid,
  output wire [`LBRESP   -1:0]       s_bresp,
  output wire                        s_bvalid,
  input  wire                        s_bready,

  input  wire [`LID      -1:0]       s_arid,
  input  wire [`LARADDR  -1:0]       s_araddr,
  input  wire [`LARLEN   -1:0]       s_arlen,
  input  wire [`LARSIZE  -1:0]       s_arsize,
  input  wire [`LARBURST -1:0]       s_arburst,
  input  wire [`LARLOCK  -1:0]       s_arlock,
  input  wire [`LARCACHE -1:0]       s_arcache,
  input  wire [`LARPROT  -1:0]       s_arprot,
  input  wire                        s_arvalid,
  output wire                        s_arready,

  output wire [`LID      -1:0]       s_rid,
  output wire [`LRDATA   -1:0]       s_rdata,
  output wire [`LRRESP   -1:0]       s_rresp,
  output wire                        s_rlast,
  output wire                        s_rvalid,
  input  wire                        s_rready,

  // ---------------- AXI 主设备 : 只读 DDR 显存 ----------------
  output wire [`LID      -1:0]       m_arid,
  output wire [`LARADDR  -1:0]       m_araddr,
  output wire [`LARLEN   -1:0]       m_arlen,
  output wire [`LARSIZE  -1:0]       m_arsize,
  output wire [`LARBURST -1:0]       m_arburst,
  output wire [`LARLOCK  -1:0]       m_arlock,
  output wire [`LARCACHE -1:0]       m_arcache,
  output wire [`LARPROT  -1:0]       m_arprot,
  output wire                        m_arvalid,
  input  wire                        m_arready,

  input  wire [`LID      -1:0]       m_rid,
  input  wire [`LRDATA   -1:0]       m_rdata,
  input  wire [`LRRESP   -1:0]       m_rresp,
  input  wire                        m_rlast,
  input  wire                        m_rvalid,
  output wire                        m_rready,

  // 主口写通道恒无效 (便于顶层直接拼进互联矩阵)
  output wire [`LID      -1:0]       m_awid,
  output wire [`LAWADDR  -1:0]       m_awaddr,
  output wire [`LAWLEN   -1:0]       m_awlen,
  output wire [`LAWSIZE  -1:0]       m_awsize,
  output wire [`LAWBURST -1:0]       m_awburst,
  output wire [`LAWLOCK  -1:0]       m_awlock,
  output wire [`LAWCACHE -1:0]       m_awcache,
  output wire [`LAWPROT  -1:0]       m_awprot,
  output wire                        m_awvalid,
  input  wire                        m_awready,
  output wire [`LID      -1:0]       m_wid,
  output wire [`LWDATA   -1:0]       m_wdata,
  output wire [`LWSTRB   -1:0]       m_wstrb,
  output wire                        m_wlast,
  output wire                        m_wvalid,
  input  wire                        m_wready,
  input  wire [`LID      -1:0]       m_bid,
  input  wire [`LBRESP   -1:0]       m_bresp,
  input  wire                        m_bvalid,
  output wire                        m_bready,

  // ================= LCD 像素时钟域 =================
  input  wire                        lcd_sys_clk,    // 50MHz (clk_wiz clk_out2)
  input  wire                        lcd_sys_rstn,   // 低有效

  // ================= LCD 物理接口 =================
  output wire [15:0]                 lcd_id,
  output wire                        lcd_clk,
  output wire                        lcd_rstn,
  output wire                        lcd_de,
  output wire                        lcd_bl,
  output wire                        lcd_hs,
  output wire                        lcd_vs,
  output wire [COLOR_WIDTH - 1:0]    lcd_rgb,

  output wire                        lcd_irq         // 帧结束 / 欠载 中断 (电平)
);

  localparam FB_DEPTH = (1 << FB_DEPTH_LOG);

  // 800x480 固定参数
  localparam [15:0] H_DISP = 16'd800;
  localparam [15:0] V_DISP = 16'd480;
  localparam [31:0] FB_BYTES = 32'd800 * 32'd480 * 32'd4;    // 1_536_000
  localparam [31:0] FB_WORDS = FB_BYTES >> 2;                // 384_000 字/帧
  localparam [15:0] LCDID    = 16'h4384;

  // 寄存器偏移
  localparam [7:0] REG_CTRL   = 8'h00;
  localparam [7:0] REG_BUF    = 8'h04;
  localparam [7:0] REG_STATUS = 8'h08;
  localparam [7:0] REG_FBSIZE = 8'h0C;
  localparam [7:0] REG_RES    = 8'h10;
  localparam [7:0] REG_ID     = 8'h14;

  //=====================================================================
  // 0. 工具函数
  //=====================================================================
  function [31:0] bin2gray;
    input [31:0] b;
    begin bin2gray = b ^ (b >> 1); end
  endfunction

  function [31:0] gray2bin;
    input [31:0] g;
    integer i;
    begin
      gray2bin[31] = g[31];
      for (i = 30; i >= 0; i = i - 1) gray2bin[i] = gray2bin[i+1] ^ g[i];
    end
  endfunction

  //=====================================================================
  // 1. 配置寄存器 (aclk 域)
  //=====================================================================
  reg [31:0] r_ctrl;
  reg [31:0] r_fbbase;

  wire       cfg_en  = r_ctrl[0];
  wire       cfg_go  = r_ctrl[1];
  wire [1:0] cfg_fmt = r_ctrl[3:2];

  //=====================================================================
  // 2. AXI 从设备 : 配置寄存器读写 (仅支持单拍 len==0)
  //=====================================================================
  // ---- 2.1 写通道 ----
  localparam SB_W_IDLE = 2'd0, SB_W_DATA = 2'd1, SB_W_RESP = 2'd2;
  reg [1:0]          sbw_state;
  reg [`LAWADDR-1:0] sbw_addr;
  reg [`LID-1:0]     sbw_id;
  reg [1:0]          sbw_resp;
  reg                sbw_wr_done;

  wire sbw_aw_hs = (sbw_state == SB_W_IDLE) && s_awvalid;
  wire sbw_beat  = (sbw_state == SB_W_DATA) && s_wvalid;
  wire sbw_b_hs  = (sbw_state == SB_W_RESP) && s_bvalid && s_bready;

  assign s_awready = (sbw_state == SB_W_IDLE);
  assign s_wready  = (sbw_state == SB_W_DATA);
  assign s_bvalid  = (sbw_state == SB_W_RESP);
  assign s_bid     = sbw_id;
  assign s_bresp   = sbw_resp;

  wire [7:0] sbw_off = sbw_addr[7:0];
  wire       cfg_wr  = sbw_beat && !sbw_wr_done && (sbw_resp == 2'b00);

  always @(posedge aclk) begin
    if (!aresetn) begin
      sbw_state   <= SB_W_IDLE;
      sbw_addr    <= {`LAWADDR{1'b0}};
      sbw_id      <= {`LID{1'b0}};
      sbw_resp    <= 2'b00;
      sbw_wr_done <= 1'b0;
    end
    else begin
      case (sbw_state)
        SB_W_IDLE: if (sbw_aw_hs) begin
          sbw_addr    <= s_awaddr;
          sbw_id      <= s_awid;
          sbw_resp    <= (s_awlen == 0) ? 2'b00 : 2'b10;   // 非单拍 -> SLVERR
          sbw_wr_done <= 1'b0;
          sbw_state   <= SB_W_DATA;
        end
        SB_W_DATA: if (sbw_beat) begin
          sbw_wr_done <= 1'b1;
          if (s_wlast) sbw_state <= SB_W_RESP;             // 把整笔写数据的最后一拍收完
        end
        SB_W_RESP: if (sbw_b_hs) sbw_state <= SB_W_IDLE;
        default:   sbw_state <= SB_W_IDLE;
      endcase
    end
  end

  // ---- 2.2 寄存器写入 ----
  reg st_underrun;
  reg st_frame;

  wire swrst = cfg_wr && (sbw_off == REG_CTRL) && s_wdata[31];
  wire clr_uf = cfg_wr && (sbw_off == REG_STATUS) && s_wdata[2];
  wire clr_fr = cfg_wr && (sbw_off == REG_STATUS) && s_wdata[3];

  always @(posedge aclk) begin
    if (!aresetn) begin
      r_ctrl      <= 32'h0000_0000;
      r_fbbase    <= 32'h0000_0000;
      st_underrun <= 1'b0;
      st_frame    <= 1'b0;
    end
    else begin
      if (cfg_wr) begin
        case (sbw_off)
          REG_CTRL: begin
            if (s_wdata[31]) r_ctrl <= 32'h0000_0000;         // SWRST 自清
            else             r_ctrl <= {1'b0, 23'h0, s_wdata[7:4], s_wdata[3:2],
                                        s_wdata[1:0]};
          end
          REG_BUF:    r_fbbase <= {s_wdata[31:6], 6'b0};      // 强制 64B 对齐
          REG_STATUS: begin
            if (s_wdata[2]) st_underrun <= 1'b0;              // W1C
            if (s_wdata[3]) st_frame    <= 1'b0;              // W1C
          end
          default: ;
        endcase
      end
      // ---- 跨域打点置位 ----
      if (frame_edge) st_frame    <= 1'b1;
      if (under_edge) st_underrun <= 1'b1;
    end
  end

  // ---- 2.3 读通道 ----
  reg [1:0]      sbr_state;
  reg [`LID-1:0] sbr_id;
  reg [31:0]     sbr_data;

  always @(posedge aclk) begin
    if (!aresetn) begin
      sbr_state <= 2'd0;
      sbr_id    <= {`LID{1'b0}};
      sbr_data  <= 32'h0;
    end
    else begin
      case (sbr_state)
        2'd0: if (s_arvalid) begin
          sbr_id <= s_arid;
          case (s_araddr[7:0])
            REG_CTRL  : sbr_data <= r_ctrl;
            REG_BUF   : sbr_data <= r_fbbase;
            REG_STATUS: sbr_data <= status_word;
            REG_FBSIZE: sbr_data <= FB_BYTES;
            REG_RES   : sbr_data <= {H_DISP, V_DISP};
            REG_ID    : sbr_data <= {16'h0, LCDID};
            default   : sbr_data <= 32'h0;
          endcase
          sbr_state <= 2'd1;
        end
        2'd1: if (s_rvalid && s_rready) sbr_state <= 2'd0;
        default: sbr_state <= 2'd0;
      endcase
    end
  end

  assign s_arready = (sbr_state == 2'd0);
  assign s_rvalid  = (sbr_state == 2'd1);
  assign s_rid     = sbr_id;
  assign s_rdata   = sbr_data;
  assign s_rresp   = 2'b00;
  assign s_rlast   = 1'b1;

  //=====================================================================
  // 3. 显存预取引擎 (aclk 域)
  //=====================================================================
  reg [31:0] wptr;        // 已确认写入缓冲的起点绝对字索引 (每完成一笔突发 +BURST_LEN)
  reg [2:0]  out_cnt;     // 在途突发数
  reg [31:0] rq_idx;      // 当前 AR 请求的**帧内**字偏移 (恒 < FB_WORDS)
  reg [31:0] ar_word;     // 下一笔 AR 的帧内字偏移, 恒在 [0, FB_WORDS)
  reg        rq_ar;       // AR 已发出, 等待 arready
  reg [3:0]  beat_cnt;    // 当前突发内已收到的拍数

  // ---- 显示域 rd_idx (= px_cnt) 的格雷码同步到 aclk ----
  reg [31:0] rd_idx_g_s1, rd_idx_g_s2, rd_idx_s;
  always @(posedge aclk) begin
    if (!aresetn) begin
      rd_idx_g_s1 <= 32'h0; rd_idx_g_s2 <= 32'h0; rd_idx_s <= 32'h0;
    end
    else begin
      rd_idx_g_s1 <= bin2gray(px_cnt);
      rd_idx_g_s2 <= rd_idx_g_s1;
      rd_idx_s    <= gray2bin(rd_idx_g_s2);
    end
  end

  wire [31:0] fill_level  = wptr - rd_idx_s;                 // 已写入未消费字数 (可负 = 读指针超前)
  wire [31:0] in_flight   = {29'd0, out_cnt} * BURST_LEN;
  // 溢出安全判据 —— 用「留白比较」, 彻底杜绝无符号减法回绕:
  //   再发一笔 BURST_LEN 后, 已向缓冲预留(含在途)的字数上界 = wptr+in_flight+BURST_LEN;
  //   环形缓冲的容量上界 (以读指针为基准)            = rd_idx_s + FB_DEPTH。
  //   仅当  req_end <= buf_end  才发下一笔 —— 即绝不会写爆缓冲。
  // ★ 读指针超前 (rd_idx_s 远大于 wptr) 时, buf_end 远 > req_end -> 必然放行,
  //   于是 AXI 继续补数、wptr 追上 rd_idx_s, 自行解除欠载。
  //   (若改用 "write_ahead = wptr+in_flight-rd_idx_s; write_ahead <= FB_DEPTH-BURST_LEN"
  //    则读超前时 write_ahead 无符号回绕成巨大正数 -> "<=1008" 为假 -> 只发 32 笔就
  //    永久停摆。已踩过这个坑。)
  wire [31:0] req_end = wptr + in_flight + {28'd0, BURST_LEN};
  wire [31:0] buf_end = rd_idx_s + {22'd0, FB_DEPTH};
  wire issue_ok = cfg_go && cfg_en && !rq_ar &&
                  (out_cnt < MAX_OUT) &&
                  (req_end <= buf_end);

  // 显示启动条件: 已写入且未消费的字数 >= PREFILL
  wire buf_ready = (fill_level < 32'h8000_0000) && (fill_level >= PREFILL);

  // ---------------------------------------------------------------------
  //  (a) 显存读地址必须按帧回卷  —— 曾经最严重的一个 bug
  // ---------------------------------------------------------------------
  //  显存只有一帧大小 (FB_WORDS = 384000 字 = 0x17_7000 字节), 显示每帧都要
  //  从头扫一遍, 所以 AR 的字偏移必须在 [0, FB_WORDS) 内回卷。
  //
  //  若像原来那样直接用"永不回卷的绝对字索引"当地址
  //      (m_araddr = fbbase + rq_idx*4, rq_idx = wptr + in_flight 无界增长),
  //  读地址就会每帧前移 0x17_7000: 第 1 帧读 [FB, FB+0x177000) 正确,
  //  第 2 帧读到 [FB+0x177000, FB+0x2EE000), 第 3 帧更远……
  //  现象就是**屏幕上只闪一下 (22 ms = 一帧) 然后一直黑**, 且串口日志全绿。
  //  回归用例: sim/tb_axi_system.v 的 T10 (连跑 3 帧查地址是否越界)。
  //
  //  注意: 只回卷 AR 地址 ar_word, **不动** wptr / px_cnt —— 它们要参与
  //  fill_level / used 的减法, 保持无界增长才不会在帧边界出现"负数"
  //  (514 字的预取深度跨过回卷点时会 wptr < rd_idx, 一减就成大数, 会让
  //   buf_ready 掉 0 从而中途复位像素时序发生器)。
  //  wptr 与 ar_word 的关系: ar_word == (wptr + in_flight) mod FB_WORDS。
  //  FB_WORDS = 384000 是 BURST_LEN(16) 也是环形缓冲深度(512) 的整数倍,
  //  所以突发永不跨帧, 且 wptr 回卷时低 9 位不变、环形读地址仍然自洽。
  // ---------------------------------------------------------------------
  wire [31:0] ar_word_next = ar_word + BURST_LEN;
  wire [31:0] ar_word_wrap = (ar_word_next >= FB_WORDS) ? (ar_word_next - FB_WORDS)
                                                        : ar_word_next;

  // ---------------------------------------------------------------------
  //  (b) AR 受理与"本笔突发最后一拍"可能落在同一拍
  // ---------------------------------------------------------------------
  //  原来在这两个分支里各写了一次 out_cnt (先 +1 后被 -1 覆盖), 同拍发生
  //  时会**少算一笔在途突发**, 使 in_flight / used 偏小、预取多放一笔.
  //  这里合并成一次结算。
  // ---------------------------------------------------------------------
  wire       ar_take = rq_ar && m_arready;
  wire       r_last  = m_rvalid && m_rready && m_rlast;
  wire [2:0] out_inc = (ar_take ? 3'd1 : 3'd0) - (r_last ? 3'd1 : 3'd0);

  always @(posedge aclk) begin
    if (!aresetn || swrst) begin
      wptr     <= 32'h0;
      out_cnt  <= 3'd0;
      rq_idx   <= 32'h0;
      ar_word  <= 32'h0;
      rq_ar    <= 1'b0;
      beat_cnt <= 4'd0;
    end
    else begin
      // ---- 发起 AR (地址取帧内回卷后的 ar_word) ----
      if (issue_ok) begin
        rq_idx <= ar_word;
        rq_ar  <= 1'b1;
      end
      else if (ar_take) begin
        rq_ar <= 1'b0;
      end

      // ---- 在途计数 + AR 地址推进 (合并结算, 见上面 (b)) ----
      out_cnt <= out_cnt + out_inc;
      if (ar_take) begin
        ar_word <= ar_word_wrap;
      end

      // ---- 接收 R 数据, 写入环形缓冲 ----
      if (m_rvalid && m_rready) begin
        if (m_rlast) begin
          wptr     <= wptr + BURST_LEN;
          beat_cnt <= 4'd0;
        end
        else begin
          beat_cnt <= beat_cnt + 4'd1;
        end
      end
    end
  end

  wire [31:0]            buf_waddr_full = wptr + {28'd0, beat_cnt};
  wire [FB_DEPTH_LOG-1:0] buf_waddr     = buf_waddr_full[FB_DEPTH_LOG-1:0];
  wire                   buf_we         = m_rvalid & m_rready;

  assign m_arid    = {`LID{1'b0}};                 // 固定 ID=0, 保证按序返回
  assign m_araddr  = r_fbbase + (rq_idx << 2);     // 1 像素 = 1 个 32bit 字
  assign m_arlen   = BURST_LEN - 1;
  assign m_arsize  = 3'b010;                       // 4 字节
  assign m_arburst = 2'b01;                        // INCR
  assign m_arlock  = 2'b00;
  assign m_arcache = 4'b0010;
  assign m_arprot  = 3'b000;
  assign m_arvalid = rq_ar;
  assign m_rready  = 1'b1;                         // 永远接收, 避免阻塞互联

  // 主口写通道恒无效
  assign m_awid    = {`LID{1'b0}};
  assign m_awaddr  = {`LAWADDR{1'b0}};
  assign m_awlen   = 4'h0;
  assign m_awsize  = 3'b010;
  assign m_awburst = 2'b01;
  assign m_awlock  = 2'b00;
  assign m_awcache = 4'b0000;
  assign m_awprot  = 3'b000;
  assign m_awvalid = 1'b0;
  assign m_wid     = {`LID{1'b0}};
  assign m_wdata   = {`LWDATA{1'b0}};
  assign m_wstrb   = {`LWSTRB{1'b0}};
  assign m_wlast   = 1'b0;
  assign m_wvalid  = 1'b0;
  assign m_bready  = 1'b1;

  //=====================================================================
  // 4. 双口环形预取缓冲 (aclk 写 / lcd_pclk 读)
  //=====================================================================
  reg [31:0] buf_mem [0:FB_DEPTH-1];
  reg [31:0] buf_rdata;

  always @(posedge aclk) begin
    if (buf_we) buf_mem[buf_waddr] <= m_rdata;
  end

  //=====================================================================
  // 5. LCD 像素时钟域
  //=====================================================================
  wire lcd_pclk;

  axi_lcd_clkdiv clk_div_inst (
    .clk      (lcd_sys_clk ),
    .rstn     (lcd_sys_rstn),
    .lcd_id   (LCDID),
    .lcd_pclk (lcd_pclk    )
  );

  // ---- 5.1 配置跨域: toggle 握手, 保证 FMT/EN 原子更新 ----
  reg cfg_tgl;
  always @(posedge aclk) begin
    if (!aresetn) cfg_tgl <= 1'b0;
    else if (cfg_wr && (sbw_off == REG_CTRL)) cfg_tgl <= ~cfg_tgl;
  end

  // ---- 5.1b swrst (aclk) -> lcd_pclk 域 toggle 握手 ----
  //  aclk 域的 swrst 只清了 wptr/ar_word/rq_idx, 显示域的 px_cnt 不动。
  //  两边不同时清 -> fill_level = wptr - px_cnt 立刻回绕成巨值, buf_ready
  //  恒 0 (画面永远黑) 且 used 恒 > FB_DEPTH (预取永久停摆)。所以必须把
  //  swrst 同步过来, 与 px_cnt / run_lat 一起清。
  reg sw_tgl;
  always @(posedge aclk) begin
    if (!aresetn) sw_tgl <= 1'b0;
    else if (swrst) sw_tgl <= ~sw_tgl;
  end

  reg sw_s1, sw_s2, sw_s3;
  always @(posedge lcd_pclk or negedge lcd_sys_rstn) begin
    if (!lcd_sys_rstn) begin
      sw_s1 <= 1'b0; sw_s2 <= 1'b0; sw_s3 <= 1'b0;
    end
    else begin
      sw_s1 <= sw_tgl;
      sw_s2 <= sw_s1;
      sw_s3 <= sw_s2;
    end
  end
  wire sw_pulse = sw_s2 ^ sw_s3;                       // 显示域的 swrst 单拍脉冲

  reg       cfg_tgl_s1, cfg_tgl_s2, cfg_tgl_s3;
  reg [1:0] fmt_p;
  reg       en_p;

  always @(posedge lcd_pclk or negedge lcd_sys_rstn) begin
    if (!lcd_sys_rstn) begin
      cfg_tgl_s1 <= 1'b0; cfg_tgl_s2 <= 1'b0; cfg_tgl_s3 <= 1'b0;
      fmt_p <= 2'b11; en_p <= 1'b0;
    end
    else begin
      cfg_tgl_s1 <= cfg_tgl;
      cfg_tgl_s2 <= cfg_tgl_s1;
      cfg_tgl_s3 <= cfg_tgl_s2;
      if (cfg_tgl_s2 ^ cfg_tgl_s3) begin
        fmt_p <= cfg_fmt;
        en_p  <= cfg_en;
      end
    end
  end

  // ---- 5.2 wptr (aclk) -> lcd_pclk 域 ----
  reg [31:0] wptr_g_s1, wptr_g_s2, wptr_s;
  always @(posedge lcd_pclk or negedge lcd_sys_rstn) begin
    if (!lcd_sys_rstn) begin
      wptr_g_s1 <= 32'h0; wptr_g_s2 <= 32'h0; wptr_s <= 32'h0;
    end
    else begin
      wptr_g_s1 <= bin2gray(wptr);
      wptr_g_s2 <= wptr_g_s1;
      wptr_s    <= gray2bin(wptr_g_s2);
    end
  end

  // ---- 5.3 缓冲就绪 -> 显示域, 并生成「一次性放行」 ----
  //  旧实现:  wire disp_rstn = lcd_sys_rstn && br_s2;
  //     只要 buf_ready 抖动一下 (预取被抢占 / 带宽不足 / 软件停-起), 时序机
  //     就被**中途**拉回复位, h_cnt/v_cnt 归 0 而 px_cnt 继续走 -> 像素↔显存
  //     映射永久错位。这是「静止画面位置不停变化」的根因。
  //  新实现: 首次攒够 PREFILL 后 run_lat 锁存, 此后只由真正的复位
  //     (lcd_sys_rstn / swrst) 清 —— 运行期间再不打断时序机。
  reg br_s1, br_s2;
  always @(posedge lcd_pclk or negedge lcd_sys_rstn) begin
    if (!lcd_sys_rstn) begin br_s1 <= 1'b0; br_s2 <= 1'b0; end
    else begin br_s1 <= buf_ready; br_s2 <= br_s1; end
  end

  reg run_lat;
  always @(posedge lcd_pclk or negedge lcd_sys_rstn) begin
    if      (!lcd_sys_rstn) run_lat <= 1'b0;
    else if (sw_pulse)      run_lat <= 1'b0;
    else if (br_s2)         run_lat <= 1'b1;
  end

  wire disp_rstn = lcd_sys_rstn && !sw_pulse && run_lat;

  // ---- 5.4 像素绝对索引 / 读地址 ----
  //   px_cnt 在每个 data_req 上 +1, 是一个永不回卷的绝对字索引。
  //   BRAM 读地址 = px_cnt, 输出 buf_rdata 再寄存一拍恰好对应
  //   lcd_driver 中 lcd_de 所对应的像素, 见文件头时序说明。
  //   ★ 复位源必须与像素时序机 (disp_rstn) **完全一致**, 否则映射会错位。
  reg [31:0] px_cnt;
  wire [31:0] px_fill = wptr_s - px_cnt;

  wire data_req_w;

  always @(posedge lcd_pclk or negedge lcd_sys_rstn) begin
    if      (!lcd_sys_rstn) px_cnt <= 32'h0;
    else if (sw_pulse)      px_cnt <= 32'h0;
    else if (data_req_w)    px_cnt <= px_cnt + 32'd1;
  end

  wire [FB_DEPTH_LOG-1:0] buf_raddr = px_cnt[FB_DEPTH_LOG-1:0];

  always @(posedge lcd_pclk or negedge lcd_sys_rstn) begin
    if (!lcd_sys_rstn) buf_rdata <= 32'h0;
    else               buf_rdata <= buf_mem[buf_raddr];
  end

  // ---- 5.4b 行首「整行放行」: 保证行内读指针永不越过写指针 ----
  //  行的原子性: 行首只放行"缓冲里已攒够整整一行 (LINE_LEVEL = 800 字)"的
  //  情况。这样一进入可见区, 这一行所需的 800 个字全部就位, 行内消耗多少
  //  都追不上写指针, 于是:
  //     * px_cnt <= wptr 恒成立 -> fill_level 永不回绕 -> buf_ready 不会掉;
  //     * used 永不 > FB_DEPTH  -> 预取不会停摆;
  //     * 「屏幕第 p 行 <-> 显存第 p 行」恒成立 -> 静止画面位置绝不漂移。
  //  不满足就在 h_cnt==0 冻结时序机 (= 拉长消隐, 屏上不可见)。
  //  ★ hold 只能作用于行首: axi_lcd_driver 内部已强制限定 h_cnt==0 才生效。
  //    若允许行内冻结, data_req 会被拉长成持续为 1, px_cnt 暴涨 -> 永久死锁。
  wire px_ahead = (px_fill >= 32'h8000_0000);          // 读指针已越过写指针
  wire buf_low  = px_ahead || (px_fill < LINE_LEVEL);
  wire hold_w   = buf_low;

  // ---- 5.5 欠载检测 (仅诊断, 不影响对齐) ----
  wire under_now = data_req_w && (px_fill >= 32'h8000_0000);

  // ---- 5.6 RGB 输出格式转换 (与工程原 apb_lcd/lcd_top.v 一致) ----
  wire [COLOR_WIDTH-1:0] pixel_raw  = buf_rdata[COLOR_WIDTH-1:0];
  reg  [COLOR_WIDTH-1:0] pixel_fmt;

  always @(*) begin
    case (fmt_p)
      2'b00:   pixel_fmt = {pixel_raw[7:5], 6'b0, pixel_raw[4:2], 5'b0, pixel_raw[1:0], 6'b0}; // RGB332
      2'b01:   pixel_fmt = {pixel_raw[11:8],4'b0, pixel_raw[7:4], 4'b0, pixel_raw[3:0], 4'b0}; // RGB444
      2'b10:   pixel_fmt = {pixel_raw[15:11],3'b0,pixel_raw[10:5],2'b0,pixel_raw[4:0], 3'b0}; // RGB565
      default: pixel_fmt = pixel_raw;                                                          // RGB888
    endcase
  end

  wire [COLOR_WIDTH-1:0] pixel_to_lcd = en_p ? pixel_fmt : {COLOR_WIDTH{1'b0}};

  // ---- 5.7 像素时序发生器 ----
  wire frame_start_w;
  wire lcd_de_w;

  axi_lcd_driver #(
    .COLOR_WIDTH (COLOR_WIDTH)
  ) lcd_driver_inst (
    .lcd_pclk    (lcd_pclk       ),
    .rstn        (disp_rstn      ),
    .hold        (hold_w         ),   // 行首节流 (见 5.4b)
    .panel_rstn  (lcd_sys_rstn   ),   // 面板复位只认系统复位, 不认流控
    .lcd_id      (LCDID        ),
    .pixel_data  (pixel_to_lcd   ),
    .pixel_xpos  (               ),
    .pixel_ypos  (               ),
    .data_req    (data_req_w     ),
    .frame_start (frame_start_w  ),
    .lcd_clk     (lcd_clk        ),
    .lcd_rstn    (lcd_rstn       ),
    .lcd_de      (lcd_de_w       ),
    .lcd_bl      (lcd_bl         ),
    .lcd_hs      (lcd_hs         ),
    .lcd_vs      (lcd_vs         ),
    .lcd_rgb     (lcd_rgb        )
  );

  assign lcd_de = lcd_de_w;
  assign lcd_id = LCDID;

  // ---- 5.8 事件打点 -> aclk (toggle 方式, 保证可同步) ----
  //  frame_start_w 是电平 (h_cnt==0 && v_cnt==0), 行首节流时会在 h_cnt==0
  //  停很多拍, 直接用它翻转 toggle 会把帧计数打飞, 所以先取上升沿。
  reg  fs_d;
  always @(posedge lcd_pclk or negedge lcd_sys_rstn) begin
    if (!lcd_sys_rstn) fs_d <= 1'b0;
    else               fs_d <= frame_start_w;
  end
  wire frame_pulse = frame_start_w && !fs_d;

  reg frame_tgl, under_tgl, under_seen;

  always @(posedge lcd_pclk or negedge lcd_sys_rstn) begin
    if (!lcd_sys_rstn) begin
      frame_tgl <= 1'b0; under_tgl <= 1'b0; under_seen <= 1'b0;
    end
    else begin
      if (frame_pulse) begin
        frame_tgl  <= ~frame_tgl;
        under_seen <= 1'b0;
      end
      if (under_now && !under_seen) begin
        under_seen <= 1'b1;
        under_tgl  <= ~under_tgl;
      end
    end
  end

  reg ft_s1, ft_s2, ut_s1, ut_s2;
  always @(posedge aclk) begin
    if (!aresetn) begin ft_s1<=1'b0; ft_s2<=1'b0; ut_s1<=1'b0; ut_s2<=1'b0; end
    else begin
      ft_s1 <= frame_tgl; ft_s2 <= ft_s1;
      ut_s1 <= under_tgl; ut_s2 <= ut_s1;
    end
  end
  wire frame_edge = ft_s1 ^ ft_s2;
  wire under_edge = ut_s1 ^ ut_s2;

  //=====================================================================
  // 6. 状态字 / 中断
  //=====================================================================
  wire [31:0] status_word = {fill_level[15:0], 12'h000,
                             st_frame, st_underrun, 1'b0, buf_ready};

  assign lcd_irq = st_frame | st_underrun;

endmodule
