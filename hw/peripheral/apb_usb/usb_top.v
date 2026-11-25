`include "../../config.vh"

module usb_top #(
  parameter CLK_FREQ = 32_000_000
) (
  input  wire        apb_pclk   ,
  input  wire        apb_prstn  ,
  input  wire        apb_psel   ,
  input  wire [31:0] apb_paddr  ,
  input  wire        apb_pwrite ,
  input  wire        apb_penable,
  input  wire [31:0] apb_pwdata ,
  output wire [31:0] apb_prdata ,
  output wire        apb_pready ,

  input  wire        usb_clk_60m,
  input  wire        usb_rxf_n  ,
  input  wire        usb_txf_n  ,
  output wire        usb_oe_n   ,
  output wire        usb_rd_n   ,
  output wire        usb_wr_n   ,
  output wire        usb_siwu_n ,
  inout  wire [7:0]  usb_data   ,

  output wire        usb_irq
);

  reg [31:0] prdata;
  wire wr;
  wire rd;

  wire usb_clk_60m_bufg;

  wire       tx_fifo_wr_en;
  wire [7:0] tx_fifo_din  ;
  wire       tx_fifo_rd_en;
  wire [7:0] tx_fifo_dout ;
  wire       tx_fifo_full ;
  wire       tx_fifo_empty;
  wire       rx_fifo_wr_en;
  wire [7:0] rx_fifo_din  ;
  wire       rx_fifo_rd_en;
  wire [7:0] rx_fifo_dout ;
  wire       rx_fifo_full ;
  wire       rx_fifo_empty;

  assign wr = apb_psel && apb_pwrite && apb_penable;
  assign rd = apb_psel && !apb_pwrite && apb_penable;
  assign apb_pready = apb_penable;

  assign usb_siwu_n = 1'b1;
  assign tx_fifo_wr_en = wr && (apb_paddr[7:0] == `USB_DATA);
  assign rx_fifo_rd_en = rd && (apb_paddr[7:0] == `USB_DATA);
  assign tx_fifo_din = apb_pwdata[7:0];
  assign usb_irq = !rx_fifo_empty;

  assign fifo_status = {6'b0, tx_fifo_full, !rx_fifo_empty};

  always @(*) begin
    if (rd) begin
      case (apb_paddr[7:0])
        `USB_DATA:prdata = {24'b0, rx_fifo_dout};
        `USB_CTRL:prdata = {24'b0, fifo_status};
        default:prdata = 32'b0;
      endcase
    end
    else begin
      prdata = 32'b0;
    end
  end
  assign apb_prdata = prdata;

  BUFG BUFG_usb_clk_60m_inst (
    .I (usb_clk_60m     ), // 1-bit input: Clock input
    .O (usb_clk_60m_bufg)  // 1-bit output: Clock output
  );

  usb_rw usb_rw_inst (
    .usb_clk_60m   (usb_clk_60m_bufg),
    .sys_rstn      (apb_prstn       ),

    .usb_rxf_n     (usb_rxf_n       ),
    .usb_txf_n     (usb_txf_n       ),
    .usb_oe_n      (usb_oe_n        ),
    .usb_rd_n      (usb_rd_n        ),
    .usb_wr_n      (usb_wr_n        ),
    .usb_data      (usb_data        ),

    .tx_fifo_empty (tx_fifo_empty   ),
    .tx_fifo_rd_en (tx_fifo_rd_en   ),
    .tx_fifo_dout  (tx_fifo_dout    ),
    .rx_fifo_wr_en (rx_fifo_wr_en   ),
    .rx_fifo_din   (rx_fifo_din     )
  );

  // native interface, independent clocks block RAM, FWFT, width is 8, depth is 64, asynchronous reset
  usb_fifo_0 usb_fifo_0_tx_inst (
    .wr_clk (apb_pclk        ), // input wire wr_clk
    .wr_rst (!apb_prstn      ), // input wire wr_rst
    .rd_clk (usb_clk_60m_bufg), // input wire rd_clk
    .rd_rst (!apb_prstn      ), // input wire rd_rst
    .wr_en  (tx_fifo_wr_en   ), // input wire wr_en
    .din    (tx_fifo_din     ), // input wire [7:0] din
    .rd_en  (tx_fifo_rd_en   ), // input wire rd_en
    .dout   (tx_fifo_dout    ), // output wire [7:0] dout
    .full   (tx_fifo_full    ), // output wire full
    .empty  (tx_fifo_empty   )  // output wire empty
  );

  // native interface, independent clocks block RAM, width is 8, depth is 64, asynchronous reset
  usb_fifo_0 usb_fifo_0_rx_inst (
    .wr_clk (usb_clk_60m_bufg), // input wire wr_clk
    .wr_rst (!apb_prstn      ), // input wire wr_rst
    .rd_clk (apb_pclk        ), // input wire rd_clk
    .rd_rst (!apb_prstn      ), // input wire rd_rst
    .wr_en  (rx_fifo_wr_en   ), // input wire wr_en
    .din    (rx_fifo_din     ), // input wire [7:0] din
    .rd_en  (rx_fifo_rd_en   ), // input wire rd_en
    .dout   (rx_fifo_dout    ), // output wire [7:0] dout
    .full   (rx_fifo_full    ), // output wire full
    .empty  (rx_fifo_empty   )  // output wire empty
  );

endmodule
