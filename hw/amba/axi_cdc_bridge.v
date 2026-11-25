`timescale 1ns / 1ps
//=====================================================================
//  File   : axi_cdc_bridge.v
//  Brief  : AXI4 跨时钟桥（32bit 同宽，异步时钟域）
//  Author : WorkBuddy
//---------------------------------------------------------------------
//  结构
//    s_* (SoC 侧, s_aclk)  <-->  m_* (MIG 侧, m_aclk)
//
//  设计要点
//    - AW / W / AR 命令通道：用异步 FIFO 把「有效载荷」从 SoC 域搬到
//      MIG 域；载荷本身不参与跨域判定，仅格雷码指针跨域同步，
//      因此多比特载荷天然一致。
//    - B / R 响应通道：反向 FIFO（MIG 域 -> SoC 域）。
//    - 写地址与写数据分通道缓存，符合 AXI 独立握手语义。
//    - 不做乱序，ID 原样透传。axi_mux 保证同一时刻仅一路事务在途，
//      因此 FIFO 深度取 4 已足够。
//    - 因为 FIFO 有深度（非握手往返），MIG 域吞吐不受 SoC 域往返延迟
//      限制，可充分发挥 DDR 带宽。
//    - 五条通道都带背压：
//        AW/W/AR : FIFO 满 -> s_*ready = 0，SoC 主设备自动等待
//        B /R    : FIFO 满 -> m_*ready = 0，MIG 保持 valid 不丢响应
//      async_fifo_pulse 的满/空标志本身就是寄存器输出，因此
//      wfull->wpush、rempty->rpop 都不会形成组合环。
//    - rpop 只接对端 ready，绝不与自身 valid 相与：
//      async_fifo_pulse 内部已是 rinc = rpop & ~rempty，
//      再与 valid(=~rempty) 就成组合环 (Vivado Synth 8-295 timing loop)。
//=====================================================================

`include "config.vh"

module axi_cdc_bridge #(
  parameter ADDR_WIDTH = 29,   // MIG 侧地址位宽
  parameter ID_WIDTH   = 4     // MIG 侧 ID 位宽
) (
  // ---------------- Slave 侧 : SoC 域 ----------------
  input  wire                    s_aclk,
  input  wire                    s_aresetn,

  input  wire [`LID      -1:0]   s_awid,
  input  wire [`LAWADDR  -1:0]   s_awaddr,
  input  wire [`LAWLEN   -1:0]   s_awlen,
  input  wire [`LAWSIZE  -1:0]   s_awsize,
  input  wire [`LAWBURST -1:0]   s_awburst,
  input  wire [`LAWLOCK  -1:0]   s_awlock,
  input  wire [`LAWCACHE -1:0]   s_awcache,
  input  wire [`LAWPROT  -1:0]   s_awprot,
  input  wire                    s_awvalid,
  output wire                    s_awready,

  input  wire [`LID      -1:0]   s_wid,
  input  wire [`LWDATA   -1:0]   s_wdata,
  input  wire [`LWSTRB   -1:0]   s_wstrb,
  input  wire                    s_wlast,
  input  wire                    s_wvalid,
  output wire                    s_wready,

  output wire [`LID      -1:0]   s_bid,
  output wire [`LBRESP   -1:0]   s_bresp,
  output wire                    s_bvalid,
  input  wire                    s_bready,

  input  wire [`LID      -1:0]   s_arid,
  input  wire [`LARADDR  -1:0]   s_araddr,
  input  wire [`LARLEN   -1:0]   s_arlen,
  input  wire [`LARSIZE  -1:0]   s_arsize,
  input  wire [`LARBURST -1:0]   s_arburst,
  input  wire [`LARLOCK  -1:0]   s_arlock,
  input  wire [`LARCACHE -1:0]   s_arcache,
  input  wire [`LARPROT  -1:0]   s_arprot,
  input  wire                    s_arvalid,
  output wire                    s_arready,

  output wire [`LID      -1:0]   s_rid,
  output wire [`LRDATA   -1:0]   s_rdata,
  output wire [`LRRESP   -1:0]   s_rresp,
  output wire                    s_rlast,
  output wire                    s_rvalid,
  input  wire                    s_rready,

  // ---------------- Master 侧 : MIG 域 ----------------
  input  wire                    m_aclk,
  input  wire                    m_aresetn,

  output wire [ID_WIDTH  -1:0]   m_awid,
  output wire [ADDR_WIDTH-1:0]   m_awaddr,
  output wire [7:0]              m_awlen,
  output wire [2:0]              m_awsize,
  output wire [1:0]              m_awburst,
  output wire [0:0]              m_awlock,
  output wire [3:0]              m_awcache,
  output wire [2:0]              m_awprot,
  output wire                    m_awvalid,
  input  wire                    m_awready,

  output wire [ID_WIDTH  -1:0]   m_wid,
  output wire [`LWDATA   -1:0]   m_wdata,
  output wire [`LWSTRB   -1:0]   m_wstrb,
  output wire                    m_wlast,
  output wire                    m_wvalid,
  input  wire                    m_wready,

  input  wire [ID_WIDTH  -1:0]   m_bid,
  input  wire [`LBRESP   -1:0]   m_bresp,
  input  wire                    m_bvalid,
  output wire                    m_bready,

  output wire [ID_WIDTH  -1:0]   m_arid,
  output wire [ADDR_WIDTH-1:0]   m_araddr,
  output wire [7:0]              m_arlen,
  output wire [2:0]              m_arsize,
  output wire [1:0]              m_arburst,
  output wire [0:0]              m_arlock,
  output wire [3:0]              m_arcache,
  output wire [2:0]              m_arprot,
  output wire                    m_arvalid,
  input  wire                    m_arready,

  input  wire [ID_WIDTH  -1:0]   m_rid,
  input  wire [`LRDATA   -1:0]   m_rdata,
  input  wire [`LRRESP   -1:0]   m_rresp,
  input  wire                    m_rlast,
  input  wire                    m_rvalid,
  output wire                    m_rready
);

  //====================================================================
  // 各通道载荷位宽
  //--------------------------------------------------------------------
  //  !!! len / lock 在 SoC 侧与 MIG 侧位宽不同 !!!
  //      s_awlen  : `LAWLEN = 4bit      m_awlen  : 8bit  (AXI4 标准)
  //      s_awlock : `LAWLOCK = 2bit     m_awlock : 1bit  (AXI4 只用 bit0)
  //
  //  载荷必须按 **M 侧的实际宽度** 打包, 并在拼接时显式补零 / 截取。
  //  早期版本按 SoC 侧宽度打包 (AW_W = 51), 而输出的左值拼接是
  //  54 位 (m_awlen 8bit + m_awlock 1bit), Verilog 会把 51bit 载荷
  //  零扩展后再整体按位赋值, 结果地址错位:
  //      m_awaddr = {s_awid[2:0], s_awaddr[ADDR_WIDTH-1:3]}
  //  即地址被右移 3 位 (仿真实测 0x1000_0000 -> 0x0200_0000),
  //  会让 DDR 访问全部打到错误地址。
  //====================================================================
  // AW 打包 : {id, addr, len, size, burst, lock, cache, prot}
  localparam AW_W = `LID + ADDR_WIDTH + 8 + `LAWSIZE
                  + `LAWBURST + 1 + `LAWCACHE + `LAWPROT;
  // W  打包 : {data, strb, last}
  localparam W_W  = `LWDATA + `LWSTRB + 1;
  // B  打包 : {resp, id}
  localparam B_W  = `LBRESP + ID_WIDTH;
  // AR 打包 : 同 AW
  localparam AR_W = AW_W;
  // R  打包 : {data, resp, id, last}
  localparam R_W  = `LRDATA + `LRRESP + ID_WIDTH + 1;

  //====================================================================
  // 写地址通道 AW
  //====================================================================
  wire [AW_W-1:0] aw_payload_s;
  wire [AW_W-1:0] aw_payload_m;
  wire            aw_empty;

  assign aw_payload_s = {
      s_awid,
      s_awaddr[ADDR_WIDTH-1:0],
      {4'b0, s_awlen},      // 4bit -> 8bit
      s_awsize,
      s_awburst,
      s_awlock[0],          // 2bit -> 1bit
      s_awcache,
      s_awprot
  };

  async_fifo_pulse #(
    .DATA_WIDTH (AW_W),
    .DEPTH_LOG2 (2)
  ) u_aw_fifo (
    .wclk   (s_aclk        ),
    .wrstn  (s_aresetn     ),
    .wpush  (s_awvalid     ),
    .wdata  (aw_payload_s  ),
    .wfull  (              ),
    .wready (s_awready     ),
    .rclk   (m_aclk        ),
    .rrstn  (m_aresetn     ),
    //  rpop 只接对端 ready, 不要再与 m_awvalid 相与!
    //  async_fifo_pulse 内部已经是 rinc = rpop & ~rempty,
    //  而 m_awvalid = ~aw_empty = ~rempty, 若这里再写
    //  (m_awvalid & m_awready) 就会形成
    //      rempty -> aw_empty -> m_awvalid -> rpop -> rinc -> rempty
    //  的组合环 (Vivado: CRITICAL WARNING [Synth 8-295] found timing loop)。
    //  分开写: 空时 FIFO 内部 ~rempty 自动拦住, 不会误弹数据。
    .rpop   (m_awready     ),
    .rdata  (aw_payload_m  ),
    .rempty (aw_empty      )
  );

  assign {m_awid, m_awaddr, m_awlen, m_awsize,
          m_awburst, m_awlock, m_awcache, m_awprot} = aw_payload_m;
  assign m_awvalid = ~aw_empty;

  //====================================================================
  // 写数据通道 W
  //====================================================================
  wire [W_W-1:0] w_payload_s;
  wire [W_W-1:0] w_payload_m;
  wire           w_empty;

  assign w_payload_s = { s_wdata, s_wstrb, s_wlast };

  async_fifo_pulse #(
    .DATA_WIDTH (W_W),
    .DEPTH_LOG2 (2)
  ) u_w_fifo (
    .wclk   (s_aclk      ),
    .wrstn  (s_aresetn   ),
    .wpush  (s_wvalid    ),
    .wdata  (w_payload_s ),
    .wfull  (            ),
    .wready (s_wready    ),
    .rclk   (m_aclk      ),
    .rrstn  (m_aresetn   ),
    .rpop   (m_wready    ),   // 同上: 不与 m_wvalid 相与, 避免组合环
    .rdata  (w_payload_m ),
    .rempty (w_empty     )
  );

  assign {m_wdata, m_wstrb, m_wlast} = w_payload_m;
  assign m_wvalid = ~w_empty;
  assign m_wid    = {ID_WIDTH{1'b0}};

  //====================================================================
  // 写响应通道 B  (MIG 域 -> SoC 域)
  //====================================================================
  wire [B_W-1:0] b_payload_m;
  wire [B_W-1:0] b_payload_s;
  wire           b_empty;
  wire           b_full;          // FIFO 内部满标志已是寄存器输出

  // 注意: m_bid / m_bresp 是来自 MIG 的输入端口, 只用于写入 B 通道 FIFO,
  //       不能反向 assign (原实现多出一行 assign, 与端口方向冲突)。
  //
  // 背压: B 通道是 MIG 域 -> SoC 域, 若 SoC 侧 (s_bready) 长期不收,
  //       跨域 FIFO 会写满。此时把 m_bready 拉低, MIG 会保持 bvalid,
  //       响应不会被覆盖丢失。
  assign m_bready = ~b_full;

  async_fifo_pulse #(
    .DATA_WIDTH (B_W),
    .DEPTH_LOG2 (2)
  ) u_b_fifo (
    .wclk   (m_aclk            ),
    .wrstn  (m_aresetn         ),
    .wpush  (m_bvalid & ~b_full),
    .wdata  ({m_bresp, m_bid}  ),
    .wfull  (b_full            ),
    .wready (                  ),
    .rclk   (s_aclk      ),
    .rrstn  (s_aresetn   ),
    .rpop   (s_bready    ),   // 同上: 不与 s_bvalid 相与, 避免组合环
    .rdata  (b_payload_s ),
    .rempty (b_empty     )
  );

  assign {s_bresp, s_bid} = b_payload_s;
  assign s_bvalid = ~b_empty;

  //====================================================================
  // 读地址通道 AR
  //====================================================================
  wire [AR_W-1:0] ar_payload_s;
  wire [AR_W-1:0] ar_payload_m;
  wire            ar_empty;

  assign ar_payload_s = {
      s_arid,
      s_araddr[ADDR_WIDTH-1:0],
      {4'b0, s_arlen},      // 4bit -> 8bit  (见上面 AW 通道的说明)
      s_arsize,
      s_arburst,
      s_arlock[0],          // 2bit -> 1bit
      s_arcache,
      s_arprot
  };

  async_fifo_pulse #(
    .DATA_WIDTH (AR_W),
    .DEPTH_LOG2 (2)
  ) u_ar_fifo (
    .wclk   (s_aclk        ),
    .wrstn  (s_aresetn     ),
    .wpush  (s_arvalid     ),
    .wdata  (ar_payload_s  ),
    .wfull  (              ),
    .wready (s_arready     ),
    .rclk   (m_aclk        ),
    .rrstn  (m_aresetn     ),
    .rpop   (m_arready     ),   // 同上: 不与 m_arvalid 相与, 避免组合环
    .rdata  (ar_payload_m  ),
    .rempty (ar_empty      )
  );

  assign {m_arid, m_araddr, m_arlen, m_arsize,
          m_arburst, m_arlock, m_arcache, m_arprot} = ar_payload_m;
  assign m_arvalid = ~ar_empty;

  //====================================================================
  // 读数据通道 R  (MIG 域 -> SoC 域)
  //====================================================================
  wire [R_W-1:0] r_payload_m;
  wire [R_W-1:0] r_payload_s;
  wire           r_empty;
  wire           r_full;          // FIFO 内部满标志已是寄存器输出

  assign r_payload_m = { m_rdata, m_rresp, m_rid, m_rlast };

  // 背压: 与 B 通道同理, SoC 侧读得慢时不能把 MIG 回的 R 数据丢掉。
  assign m_rready    = ~r_full;

  async_fifo_pulse #(
    .DATA_WIDTH (R_W),
    .DEPTH_LOG2 (2)
  ) u_r_fifo (
    .wclk   (m_aclk            ),
    .wrstn  (m_aresetn         ),
    .wpush  (m_rvalid & ~r_full),
    .wdata  (r_payload_m       ),
    .wfull  (r_full            ),
    .wready (                  ),
    .rclk   (s_aclk      ),
    .rrstn  (s_aresetn   ),
    .rpop   (s_rready    ),   // 同上: 不与 s_rvalid 相与, 避免组合环
    .rdata  (r_payload_s ),
    .rempty (r_empty     )
  );

  assign {s_rdata, s_rresp, s_rid, s_rlast} = r_payload_s;
  assign s_rvalid = ~r_empty;

endmodule


//=====================================================================
//  async_fifo_pulse : 低延迟异步 FIFO（格雷码指针）
//    - 数据写入双口分布式 RAM
//    - 指针二进制 -> 格雷码，两级同步器跨域
//    - 纯 RTL，可综合
//=====================================================================
module async_fifo_pulse #(
  parameter DATA_WIDTH = 32,
  parameter DEPTH_LOG2 = 2          // 深度 = 2**DEPTH_LOG2
) (
  // 写侧（源域）
  input  wire                    wclk,
  input  wire                    wrstn,
  input  wire                    wpush,
  input  wire [DATA_WIDTH-1:0]   wdata,
  output wire                    wfull,
  output wire                    wready,
  // 读侧（目的域）
  input  wire                    rclk,
  input  wire                    rrstn,
  input  wire                    rpop,
  output wire [DATA_WIDTH-1:0]   rdata,
  output wire                    rempty
);

  localparam PTR_W = DEPTH_LOG2 + 1;    // 多 1 位用于区分满/空
  localparam DEPTH = (1 << DEPTH_LOG2);

  reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

  reg [PTR_W-1:0] wbin, wgray;
  reg [PTR_W-1:0] rbin, rgray;

  //------------------------------------------------------------------
  // 写侧
  //------------------------------------------------------------------
  // !! 满标志必须打一拍 (寄存器输出) !!
  //   若把 wfull 写成组合 (wgray_next == 满模式), 会形成
  //       wfull -> wready -> winc -> wbin_next -> wgray_next -> wfull
  //   的组合环。当写指针到达"再进一步就满"的位置时会来回振荡:
  //     winc=1 -> wbin_next=满位置 -> wgray_next=满模式 -> wfull=1
  //     winc=0 -> wbin_next=原位置 -> wgray_next!=满模式 -> wfull=0
  //   Vivado 会用 CRITICAL WARNING [Synth 8-295] timing loop +
  //   set_disable_timing 把它掩盖过去 (行为不确定), 而 iverilog 会
  //   在零时间内死循环 -> 仿真挂死。
  //   标准 Cummings 异步 FIFO 的做法: wfull 打一拍, winc 用「上一拍的
  //   满标志」, 环被寄存器切断。
  //------------------------------------------------------------------
  reg              wfull_r;
  wire             winc        = wpush & ~wfull_r;
  wire [PTR_W-1:0] wbin_next   = wbin + winc;
  wire [PTR_W-1:0] wgray_next  = (wbin_next >> 1) ^ wbin_next;

  // 读指针同步到写域
  reg [PTR_W-1:0] rgray_s1, rgray_s2;
  always @(posedge wclk or negedge wrstn) begin
    if (!wrstn) begin
      rgray_s1 <= 'b0;
      rgray_s2 <= 'b0;
    end else begin
      rgray_s1 <= rgray;
      rgray_s2 <= rgray_s1;
    end
  end

  // 满 = 下一拍写指针的格雷码 ==「同步过来的读格雷码高两位取反、低位相同」
  wire wfull_val = (wgray_next == {~rgray_s2[PTR_W-1:PTR_W-2],
                                    rgray_s2[PTR_W-3:0]});
  always @(posedge wclk or negedge wrstn) begin
    if (!wrstn) wfull_r <= 1'b0;
    else        wfull_r <= wfull_val;
  end

  assign wfull  = wfull_r;
  assign wready = ~wfull_r;

  always @(posedge wclk) begin
    if (winc)
      mem[wbin[DEPTH_LOG2-1:0]] <= wdata;
  end

  always @(posedge wclk or negedge wrstn) begin
    if (!wrstn) begin
      wbin  <= 'b0;
      wgray <= 'b0;
    end else begin
      wbin  <= wbin_next;
      wgray <= wgray_next;
    end
  end

  //------------------------------------------------------------------
  // 读侧  (空标志同样打一拍, 与写侧对称, 保证两个域的标志都是
  //        纯寄存器输出 -> 任何组合环都不可能出现)
  //------------------------------------------------------------------
  reg              rempty_r;
  wire             rinc        = rpop & ~rempty_r;
  wire [PTR_W-1:0] rbin_next   = rbin + rinc;
  wire [PTR_W-1:0] rgray_next  = (rbin_next >> 1) ^ rbin_next;

  // 写指针同步到读域
  reg [PTR_W-1:0] wgray_s1, wgray_s2;
  always @(posedge rclk or negedge rrstn) begin
    if (!rrstn) begin
      wgray_s1 <= 'b0;
      wgray_s2 <= 'b0;
    end else begin
      wgray_s1 <= wgray;
      wgray_s2 <= wgray_s1;
    end
  end

  // 空 = 下一拍读指针的格雷码 == 同步过来的写格雷码
  wire rempty_val = (rgray_next == wgray_s2);
  always @(posedge rclk or negedge rrstn) begin
    if (!rrstn) rempty_r <= 1'b1;      // 复位时必定为空
    else        rempty_r <= rempty_val;
  end

  assign rempty = rempty_r;
  assign rdata  = mem[rbin[DEPTH_LOG2-1:0]];

  always @(posedge rclk or negedge rrstn) begin
    if (!rrstn) begin
      rbin  <= 'b0;
      rgray <= 'b0;
    end else begin
      rbin  <= rbin_next;
      rgray <= rgray_next;
    end
  end

endmodule
