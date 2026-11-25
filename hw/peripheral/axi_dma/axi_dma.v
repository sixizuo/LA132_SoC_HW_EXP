`timescale 1ns / 1ps
//=====================================================================
//  File   : axi_dma.v
//  Brief  : 基于 AXI4 总线的 DMA 控制器 (云晓 100T / LA132 SoC)
//  Author : WorkBuddy
//---------------------------------------------------------------------
//  功能
//  --------------------------------------------------------------------
//  1) AXI 从设备 (窗口 0x510E_0000 ~ 0x510E_FFFF):
//       CPU 配置「源地址 / 目的地址 / 传输字节数 / 传输数据类型 / 启动」,
//       并可回读运行状态与已传输字节数。
//  2) AXI 主设备: 从源地址读出数据写入目的地址, 完成存储器之间的数据搬运。
//       源/目的既可以是 DDR, 也可以是本 SoC 上任意 AXI 从设备
//       (APB 桥 / DMAC 寄存器 / LCD 寄存器 / DDR), 见 axi_interconnect.v。
//
//  传输模型 (字节精确, 支持源/目的字节偏移不同的非对齐拷贝)
//  --------------------------------------------------------------------
//   DMA 把 LEN_BYTES 个字节从 SRC_ADDR 依序搬到 DST_ADDR。内部用
//   「一个字的前瞻 + 固定移位」对齐器实现:
//
//     源字流   s[0] s[1] s[2] ...                (字对齐地址 swb0 + i)
//     off     = (SRC_ADDR - DST_ADDR[1:0]) & 3
//     out[m]  = ( { s[m+1], s[m] } >> (off*8) )[31:0]
//
//   目的侧再用 WSTRB 精确掩掉范围外的字节, 因此首字 / 尾字都能正确处理。
//
//  数据类型 DTYPE (CTRL[1:0]) 的作用
//  --------------------------------------------------------------------
//     `00` 8 bit  : 不校验对齐; 不启用突发 (每批只搬 1 个输出字 -> 单拍 len=0)
//     `01` 16 bit : 要求 SRC/DST 2 字节对齐 且 LEN_BYTES 为偶数; 启用 16 拍突发
//     `10` 32 bit : 要求 SRC/DST 4 字节对齐 且 LEN_BYTES 为 4 的倍数; 启用 16 拍突发
//   不满足对齐 / 长度要求时置 STATUS.ERROR 并放弃本次传输。
//
//  性能
//  --------------------------------------------------------------------
//   32bit 模式每批读 16 个字 -> 写 16 个字, 约 36 个 aclk 周期搬 64 字节,
//   32MHz 下约 57 MB/s; 单拍模式约慢 4~8 倍。
//   读通道与写通道完全独立 (先读满一批再写出去), 不会死锁。
//=====================================================================

`include "config.vh"

module axi_dma #(
  parameter BURST = 16          // 每批最大字数 (1..16)
) (
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

  // ---------------- AXI 主设备 : 读源 ----------------
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

  // ---------------- AXI 主设备 : 写目的 ----------------
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

  output wire                        dma_irq
);

  //=====================================================================
  // 0. 寄存器地址映射
  //=====================================================================
  localparam [7:0] REG_SRC   = 8'h00;   // R/W 源地址 (字节)
  localparam [7:0] REG_DST   = 8'h04;   // R/W 目的地址 (字节)
  localparam [7:0] REG_LEN   = 8'h08;   // R/W 传输字节数
  localparam [7:0] REG_START = 8'h0C;   // W   bit0 START(自清), bit1 ABORT(自清)
  localparam [7:0] REG_CTRL  = 8'h10;   // R/W [1:0] DTYPE, [8] INT_EN
  localparam [7:0] REG_STAT  = 8'h14;   // R   bit0 BUSY, bit1 DONE, bit2 ERROR, bit3 ABORT  (bit1/2 W1C)
  localparam [7:0] REG_DONE  = 8'h18;   // R   已传输字节数
  localparam [7:0] REG_VER   = 8'h1C;   // R   版本

  localparam [31:0] VERSION = 32'h4158_444D;   // "AXDM"

  reg [31:0] r_src;
  reg [31:0] r_dst;
  reg [31:0] r_len;
  reg [31:0] r_ctrl;
  reg [31:0] r_done_bytes;

  reg        st_done;
  reg        st_error;
  reg        st_abort;

  wire [1:0] dtype  = r_ctrl[1:0];
  wire       int_en = r_ctrl[8];

  //=====================================================================
  // 1. AXI 从设备 : 配置寄存器读写 (仅支持单拍 len==0)
  //=====================================================================
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
          sbw_resp    <= (s_awlen == 0) ? 2'b00 : 2'b10;
          sbw_wr_done <= 1'b0;
          sbw_state   <= SB_W_DATA;
        end
        SB_W_DATA: if (sbw_beat) begin
          sbw_wr_done <= 1'b1;
          if (s_wlast) sbw_state <= SB_W_RESP;
        end
        SB_W_RESP: if (sbw_b_hs) sbw_state <= SB_W_IDLE;
        default:   sbw_state <= SB_W_IDLE;
      endcase
    end
  end

  wire start_wr = cfg_wr && (sbw_off == REG_START) && s_wdata[0];
  wire abort_wr = cfg_wr && (sbw_off == REG_START) && s_wdata[1];
  wire clr_done = cfg_wr && (sbw_off == REG_STAT ) && s_wdata[1];
  wire clr_err  = cfg_wr && (sbw_off == REG_STAT ) && s_wdata[2];

  //=====================================================================
  // 2. DMA 传输引擎 (aclk 域)
  //=====================================================================
  localparam S_IDLE    = 4'd0,
             S_CHK     = 4'd1,
             S_SEED_AR = 4'd2,
             S_SEED_RD = 4'd3,
             S_RD_AR   = 4'd4,
             S_RD_DATA = 4'd5,
             S_WR_AW   = 4'd6,
             S_WR_WD   = 4'd7,
             S_WR_BR   = 4'd8;

  reg  [3:0]  state;
  reg  [31:0] m_total;      // 总输出字数 M = ceil((DST_OFF + LEN)/4)
  reg  [31:0] swb0;         // 第一个源字索引 = ((SRC - DST[1:0]) & ~3) >> 2
  reg  [31:0] dw0;          // 第一个目的字字节地址 = DST & ~3
  reg  [1:0]  align_off;    // off = (SRC - DST[1:0]) & 3
  reg  [1:0]  out_off;      // DST[1:0]
  reg  [31:0] produced;     // 已产生的输出字数
  reg  [31:0] carry;        // 上一批最后一个源字
  reg  [4:0]  nsrc_r;       // 本批源字数 = 本批输出字数 (1..BURST, BURST<=16)
  reg  [4:0]  rd_cnt;
  reg  [4:0]  wr_cnt;

  reg  [31:0] sbuf [0:BURST-1];

  wire busy = (state != S_IDLE);

  // ---- 参数合法性 ----
  wire [31:0] dt_bytes = (dtype == 2'b00) ? 32'd1 :
                         (dtype == 2'b01) ? 32'd2 : 32'd4;
  wire [31:0] dt_mask = dt_bytes - 32'd1;      // 1/2/4 -> 0/1/3, 用位与代替取模
  wire align_ok = ((r_src & dt_mask) == 32'd0) &&
                  ((r_dst & dt_mask) == 32'd0) &&
                  ((r_len & dt_mask) == 32'd0);
  wire param_ok = align_ok && (r_len != 32'd0);

  wire use_burst = (dtype != 2'b00);

  // BURST 的定宽常量副本 (对 parameter 做位选 iverilog 不支持)
  localparam [4:0] BURST_N = BURST;

  // m_total 的「当前周期组合值」, 供 S_CHK 内计算首批字数使用
  wire [31:0] m_total_a = (r_len + {30'd0, r_dst[1:0]} + 32'd3) >> 2;

  // 本批字数 = min(BURST, 剩余输出字数); 8bit 模式恒为 1
  wire [31:0] left_now = m_total_a - produced;
  wire [4:0]  nsrc_now = use_burst ? ((left_now > {27'd0, BURST_N}) ? BURST_N : left_now[4:0])
                                   : 5'd1;

  wire [31:0] produced_nxt = produced + {27'd0, nsrc_r};
  wire [31:0] left_nxt     = m_total - produced_nxt;
  wire [4:0]  nsrc_nxt     = use_burst ? ((left_nxt > {27'd0, BURST_N}) ? BURST_N : left_nxt[4:0])
                                       : 5'd1;

  // ---- 目的侧 WSTRB ----
  function [3:0] calc_strb;
    input [31:0] m;        // 输出字序号
    input [1:0]  ooff;     // DST[1:0]
    input [31:0] len;
    integer p, t;
    begin
      calc_strb = 4'h0;
      for (p = 0; p < 4; p = p + 1) begin
        t = (m * 4) + p - ooff;
        if ((t >= 0) && (t < len)) calc_strb[p] = 1'b1;
      end
    end
  endfunction

  // ---- 目的侧写数据 (固定移位对齐器) ----
  wire [31:0] wr_strb32 = calc_strb(produced + {27'd0, wr_cnt}, out_off, r_len);
  wire [3:0]  wr_strb   = wr_strb32;
  wire [3:0]  wr_cur    = wr_cnt[3:0];
  wire [4:0]  wr_prev5  = (wr_cnt == 5'd0) ? 5'd0 : (wr_cnt - 5'd1);
  wire [3:0]  wr_prev   = wr_prev5[3:0];
  wire [63:0] wr_pair   = (wr_cnt == 5'd0) ? {sbuf[0], carry}
                                           : {sbuf[wr_cur], sbuf[wr_prev]};
  wire [31:0] wr_data   = wr_pair >> (align_off * 8);

  wire [4:0] nsrc_m1 = nsrc_r - 5'd1;
  wire rd_last_beat  = m_rvalid && (rd_cnt == nsrc_m1);
  wire wr_last_beat  = m_wready && (wr_cnt == nsrc_m1);

  always @(posedge aclk) begin
    if (!aresetn) begin
      state        <= S_IDLE;
      r_src        <= 32'h0;
      r_dst        <= 32'h0;
      r_len        <= 32'h0;
      r_ctrl       <= 32'h0;
      r_done_bytes <= 32'h0;
      st_done      <= 1'b0;
      st_error     <= 1'b0;
      st_abort     <= 1'b0;
      m_total      <= 32'h0;
      swb0         <= 32'h0;
      dw0          <= 32'h0;
      align_off    <= 2'd0;
      out_off      <= 2'd0;
      produced     <= 32'h0;
      carry        <= 32'h0;
      nsrc_r       <= 5'd0;
      rd_cnt       <= 5'd0;
      wr_cnt       <= 5'd0;
    end
    else begin
      // ---------------- 配置寄存器写入 ----------------
      if (cfg_wr) begin
        case (sbw_off)
          REG_SRC: r_src <= s_wdata;
          REG_DST: r_dst <= s_wdata;
          REG_LEN: r_len <= s_wdata;
          REG_CTRL: r_ctrl <= {23'h0, s_wdata[8], 14'h0, s_wdata[1:0]};
          default: ;
        endcase
      end
      if (start_wr && !busy) begin
        st_done  <= 1'b0;
        st_error <= 1'b0;
        st_abort <= 1'b0;
      end
      if (abort_wr && busy) st_abort <= 1'b1;
      if (clr_done) st_done  <= 1'b0;
      if (clr_err ) st_error <= 1'b0;

      // ---------------- 主状态机 ----------------
      case (state)
        // ---------------------------------------------------- 空闲
        S_IDLE: begin
          produced <= 32'h0;
          rd_cnt   <= 5'd0;
          wr_cnt   <= 5'd0;
          if (start_wr) state <= S_CHK;
        end

        // ---------------------------------------------------- 参数检查 / 预计算
        S_CHK: begin
          out_off   <= r_dst[1:0];
          align_off <= r_src[1:0] - r_dst[1:0];                     // 2bit 截断即 &3
          swb0      <= ((r_src - {30'd0, r_dst[1:0]}) & 32'hFFFF_FFFC) >> 2;
          dw0       <= {r_dst[31:2], 2'b00};
          m_total   <= (r_len + {30'd0, r_dst[1:0]} + 32'd3) >> 2;
          produced  <= 32'h0;
          rd_cnt    <= 5'd0;
          wr_cnt    <= 5'd0;
          nsrc_r    <= nsrc_now;
          if (!param_ok) begin
            st_error <= 1'b1;
            state    <= S_IDLE;
          end
          else state <= S_SEED_AR;
        end

        // ---------------------------------------------------- 预读 1 个字 -> carry
        S_SEED_AR: if (m_arready) state <= S_SEED_RD;

        S_SEED_RD: if (m_rvalid) begin
          carry <= m_rdata;
          state <= S_RD_AR;
        end

        // ---------------------------------------------------- 批读地址
        S_RD_AR: begin
          if (st_abort) state <= S_IDLE;
          else if (m_arready) state <= S_RD_DATA;
        end

        // ---------------------------------------------------- 批读数据
        S_RD_DATA: begin
          if (m_rvalid) begin
            sbuf[rd_cnt[3:0]] <= m_rdata;
            if (rd_last_beat) begin
              rd_cnt <= 5'd0;
              wr_cnt <= 5'd0;
              state  <= S_WR_AW;
            end
            else rd_cnt <= rd_cnt + 5'd1;
          end
        end

        // ---------------------------------------------------- 批写地址
        S_WR_AW: if (m_awready) state <= S_WR_WD;

        // ---------------------------------------------------- 批写数据
        S_WR_WD: begin
          if (m_wready) begin
            if (wr_last_beat) begin
              wr_cnt <= 5'd0;
              state  <= S_WR_BR;
            end
            else wr_cnt <= wr_cnt + 5'd1;
          end
        end

        // ---------------------------------------------------- 批写响应
        S_WR_BR: begin
          if (m_bvalid) begin
            produced <= produced_nxt;
            carry    <= sbuf[nsrc_m1[3:0]];
            rd_cnt   <= 5'd0;
            if (st_abort) begin
              // 中止发生在批次边界: 记录已写入字节数后回到空闲
              r_done_bytes <= ({produced[29:0], 2'b00} > {30'd0, out_off})
                             ? ({produced[29:0], 2'b00} - {30'd0, out_off}) : 32'h0;
              state        <= S_IDLE;
            end
            else if (produced_nxt >= m_total) begin
              r_done_bytes <= r_len;
              st_done      <= 1'b1;
              state        <= S_IDLE;
            end
            else begin
              nsrc_r <= nsrc_nxt;
              state  <= S_RD_AR;
            end
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

  // ---- 主口读通道 ----
  assign m_arid    = {`LID{1'b0}};
  assign m_araddr  = (state == S_SEED_AR) ? (swb0 << 2)
                                          : ((swb0 + produced + 32'd1) << 2);
  assign m_arlen   = (state == S_SEED_AR) ? 4'h0 : (nsrc_r[3:0] - 4'h1);
  assign m_arsize  = 3'b010;
  assign m_arburst = 2'b01;
  assign m_arlock  = 2'b00;
  assign m_arcache = 4'b0010;
  assign m_arprot  = 3'b000;
  assign m_arvalid = ((state == S_SEED_AR) || (state == S_RD_AR)) && !st_abort;
  assign m_rready  = 1'b1;

  // ---- 主口写通道 ----
  assign m_awid    = {`LID{1'b0}};
  assign m_awaddr  = dw0 + (produced << 2);
  assign m_awlen   = nsrc_r[3:0] - 4'h1;
  assign m_awsize  = 3'b010;
  assign m_awburst = 2'b01;
  assign m_awlock  = 2'b00;
  assign m_awcache = 4'b0010;
  assign m_awprot  = 3'b000;
  assign m_awvalid = (state == S_WR_AW);

  assign m_wid     = {`LID{1'b0}};
  assign m_wdata   = wr_data;
  assign m_wstrb   = wr_strb;
  assign m_wlast   = (state == S_WR_WD) && (wr_cnt == nsrc_m1);
  assign m_wvalid  = (state == S_WR_WD);
  assign m_bready  = 1'b1;

  //=====================================================================
  // 3. AXI 从设备 : 读通道
  //=====================================================================
  reg [1:0]      sbr_state;
  reg [`LID-1:0] sbr_id;
  reg [31:0]     sbr_data;

  wire [31:0] status_word = {27'h0, st_abort, st_error, st_done, busy};

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
            REG_SRC : sbr_data <= r_src;
            REG_DST : sbr_data <= r_dst;
            REG_LEN : sbr_data <= r_len;
            REG_CTRL: sbr_data <= r_ctrl;
            REG_STAT: sbr_data <= status_word;
            REG_DONE: sbr_data <= r_done_bytes;
            REG_VER : sbr_data <= VERSION;
            default : sbr_data <= 32'h0;
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

  assign dma_irq = (st_done | st_error | st_abort) & int_en;

endmodule
