`include "../apb_addr.svh"

module apb_bridge #(
  N_MASTER  = 1   ,
  N_SLAVE   = 16  ,
  W_DATA    = 32  ,
  W_ADDR    = 32  
) (
  input  logic apb_clk   ,
  input  logic apb_rstn  ,

  input  logic [N_MASTER - 1 : 0]           m_psel    ,
  input  logic [N_MASTER * W_ADDR - 1 : 0]  m_paddr   ,
  input  logic [N_MASTER * 4 - 1 : 0]       m_pstrb   ,
  input  logic [N_MASTER - 1 : 0]           m_pwrite  ,
  input  logic [N_MASTER - 1 : 0]           m_penable ,
  input  logic [N_MASTER * W_DATA - 1 : 0]  m_pwdata  ,
  output logic [N_MASTER * W_DATA - 1 : 0]  m_prdata  ,
  output logic [N_MASTER - 1 : 0]           m_pready  ,

  output logic [N_SLAVE - 1 : 0]            s_psel    ,
  output logic [N_SLAVE * W_ADDR - 1 : 0]   s_paddr   ,
  output logic [N_SLAVE * 4 - 1 : 0]        s_pstrb   ,
  output logic [N_SLAVE - 1 : 0]            s_pwrite  ,
  output logic [N_SLAVE - 1 : 0]            s_penable ,
  output logic [N_SLAVE * W_DATA - 1 : 0]   s_pwdata  ,
  input  logic [N_SLAVE * W_DATA - 1 : 0]   s_prdata  ,
  input  logic [N_SLAVE - 1 : 0]            s_pready  
);

  logic                    no_transfer ;
  logic                    curr_psel   ;
  logic [W_ADDR - 1 : 0]   curr_paddr  ;
  logic [3 : 0]            curr_pstrb  ;
  logic                    curr_pwrite ;
  logic                    curr_penable;
  logic [W_DATA - 1 : 0]   curr_pwdata ;
  logic [W_DATA - 1 : 0]   curr_prdata ;
  logic                    curr_pready ;

  logic [N_MASTER - 1 : 0]     curr_grant    ;
  logic [N_MASTER - 1 : 0]     curr_grant_m1 ;
  logic [$clog2(N_MASTER) : 0] curr_master   ;

  logic [N_SLAVE * W_ADDR * 2 - 1 : 0] addr_table = `APB_ADDR_TABLE;
  logic [W_ADDR - 1 : 0]       s_paddr_base [N_SLAVE - 1 : 0];
  logic [W_ADDR - 1 : 0]       s_paddr_mask [N_SLAVE - 1 : 0];
  logic [N_SLAVE - 1 : 0]      curr_ssel_m1  ;
  logic [$clog2(N_SLAVE)  : 0] curr_slave    ;

  // ------------------------------------------------------------------
  //  Timeout protection for undecoded / stuck APB accesses
  //  (added 2026-10-31)
  // ------------------------------------------------------------------
  //  Failure mode without this:
  //    A CPU access to an address that no slave decodes leaves every
  //    s_psel at 0. Then `s_psel - 1` is all ones, curr_slave saturates
  //    to N_SLAVE, `s_pready[curr_slave]` indexes out of range and reads
  //    0 forever -> curr_pready never asserts -> axi2apb_bridge stays in
  //    state 3'h2 -> no bvalid/rvalid -> the core hangs, unrecoverable
  //    (LALINK cannot even enter debug mode).
  //    The same hang happens when a decoded slave forgets to assert
  //    pready (e.g. reading an empty UART data FIFO).
  //
  //  FIX (2026-11-02): every address that no slave decodes is now routed to
  //  a dedicated DUMMY slave (apb_dummy_slave.sv) instead of being dropped.
  //  The dummy answers in the APB ACCESS phase with prdata = 0 and swallows
  //  writes, so a hole in the address map costs exactly one cycle.
  //  The 4096-clk timeout is kept as a second-level safety net for the
  //  remaining case: a *decoded* slave that never asserts pready.
  //  4096 clk @32MHz = 128us, far longer than any real APB slave on this
  //  SoC needs (they all answer combinationally in 1-2 cycles).
  // ------------------------------------------------------------------
  localparam [11:0] TIMEOUT_MAX = 12'd4095;   // 4096 clk window

  logic [11:0] to_cnt;        // 0 .. 4095
  logic        to_fire;
  logic        any_sel;
  logic        dev_pready;

  // ---- default (dummy) slave for undecoded addresses ----
  logic                dummy_psel;
  logic                dummy_pready;
  logic [W_DATA - 1:0] dummy_prdata;

  assign any_sel    = |s_psel;
  assign dev_pready = any_sel ? s_pready[curr_slave] : 1'b0;
  assign dummy_psel = curr_psel & ~any_sel;

  apb_dummy_slave #(.W_DATA(W_DATA)) dummy_slave_inst (
    .apb_psel    (dummy_psel   ),
    .apb_penable (curr_penable ),
    .apb_pwrite  (curr_pwrite  ),
    .apb_paddr   (curr_paddr   ),
    .apb_pwdata  (curr_pwdata  ),
    .apb_prdata  (dummy_prdata ),
    .apb_pready  (dummy_pready )
  );

  // Clear on every completed / aborted transfer, so the next access
  // starts with a fresh window. NOTE: clear condition uses dev_pready
  // (not curr_pready) to avoid a combinational loop through to_fire.
  always_ff @(posedge apb_clk or negedge apb_rstn) begin
    if (!apb_rstn)
      to_cnt <= 12'd0;
    else if (!curr_psel || dev_pready || dummy_pready)
      to_cnt <= 12'd0;
    else if (to_cnt != TIMEOUT_MAX)
      to_cnt <= to_cnt + 12'd1;
  end

  assign to_fire = (to_cnt == TIMEOUT_MAX);

  arbiter #( N_MASTER ) arbiter_inst (
    .request(m_psel     ),
    .grant  (curr_grant )
  );
  assign no_transfer = ~|curr_grant;

  integer i, j;
  generate
    always_comb begin
      curr_master = 0;
      curr_grant_m1 = curr_grant - 1'b1;
      for (i = 0; i < N_MASTER; i = i + 1) begin: master_interface_gen
        m_prdata [i * W_DATA +: W_DATA] = no_transfer ? 'h0 : curr_prdata;
        m_pready [i] = no_transfer ? 1'b0 : curr_grant[i] ? curr_pready : 1'b0;
        curr_master  = curr_master + curr_grant_m1[i];
      end
    end
  endgenerate

  assign curr_psel    = no_transfer ? 'b0 : m_psel   [curr_master];
  assign curr_paddr   = no_transfer ? 'b0 : m_paddr  [curr_master * W_ADDR +: W_ADDR];
  assign curr_pstrb   = no_transfer ? 'b0 : m_pstrb  [curr_master * 4 +: 4];
  assign curr_pwrite  = no_transfer ? 'b0 : m_pwrite [curr_master];
  assign curr_penable = no_transfer ? 'b0 : m_penable[curr_master];
  assign curr_pwdata  = no_transfer ? 'b0 : m_pwdata [curr_master * W_DATA +: W_DATA];

  genvar slv_num;
  generate
    for (slv_num = 0; slv_num < N_SLAVE; slv_num = slv_num + 1) begin: slave_macro_gen
      assign s_paddr_base[slv_num] = addr_table[slv_num * W_ADDR * 2 + 32 +: 32];
      assign s_paddr_mask[slv_num] = addr_table[slv_num * W_ADDR * 2 +: 32];
      assign s_psel   [slv_num] = curr_psel && 
        ((curr_paddr & ~s_paddr_mask[slv_num]) == s_paddr_base[slv_num]);
      assign s_paddr  [slv_num * W_ADDR +: W_ADDR] = s_psel[slv_num] ? curr_paddr   : 'b0;
      assign s_pstrb  [slv_num * 4 +: 4] = s_psel[slv_num] ? curr_pstrb   : 'b0;
      assign s_pwrite [slv_num] = s_psel[slv_num] ? curr_pwrite  : 'b0;
      assign s_penable[slv_num] = s_psel[slv_num] ? curr_penable : 'b0;
      assign s_pwdata [slv_num * W_DATA +: W_DATA] = s_psel[slv_num] ? curr_pwdata  : 'b0;
    end
  endgenerate

  generate
    always_comb begin
      curr_slave = 0;
      curr_ssel_m1 = s_psel - 1'b1;
      for (j = 0; j < N_SLAVE; j = j + 1) begin: slave_interface_gen
        curr_slave   = curr_slave + curr_ssel_m1[j]; 
      end
      // s_psel == 0 makes the sum above saturate to N_SLAVE; clamp it so the
      // s_prdata / s_pready index is never out of range.
      if (!any_sel) curr_slave = '0;
    end
  endgenerate

  // Read data: undecoded addresses are served by the dummy slave (returns 0).
  assign curr_prdata  = no_transfer ? 'b0
                      : (~any_sel)  ? dummy_prdata
                      : s_prdata [curr_slave * W_DATA +: W_DATA];
  // ready: dummy slave answers holes at once; a decoded-but-silent slave is
  // still caught by the timeout so the bus can never lock up.
  assign curr_pready  = no_transfer ? 'b0
                      : (~any_sel)  ? dummy_pready
                      : (dev_pready | to_fire);
  
endmodule