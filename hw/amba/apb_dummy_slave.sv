// -----------------------------------------------------------------------------
//  apb_dummy_slave.sv
//
//  Default APB slave for every address that no real peripheral decodes.
//
//  The APB bridge instantiates exactly one of these and selects it whenever
//  `|s_psel == 0` while a transfer is in flight. Instead of leaving the bus
//  without a responder (the CPU would wait forever), the dummy completes the
//  access in the APB ACCESS phase:
//      * reads  -> prdata = 0
//      * writes -> accepted and discarded
//      * pready -> asserted for one cycle (psel & penable)
//
//  It is purely combinational (no state, no clock), so it costs a couple of
//  LUTs and adds no latency: a bad address now takes the same single cycle as
//  a good one.
//
//  Added 2026-11-02. Before this, an undecoded address stalled the APB bridge
//  until the 4096-clk timeout fired (see apb_bridge.sv).
// -----------------------------------------------------------------------------
module apb_dummy_slave #(
  parameter W_DATA = 32
) (
  input  logic              apb_psel   ,
  input  logic              apb_penable,
  input  logic              apb_pwrite ,
  input  logic [31 : 0]     apb_paddr  ,
  input  logic [W_DATA-1:0] apb_pwdata ,
  output logic [W_DATA-1:0] apb_prdata ,
  output logic              apb_pready
);

  // There is nothing behind this address: reads always return 0.
  assign apb_prdata = 'b0;

  // Answer on the ACCESS phase only (SETUP must not see pready).
  assign apb_pready = apb_psel & apb_penable;

endmodule
