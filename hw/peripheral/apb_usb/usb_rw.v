module usb_rw (
  input  wire       usb_clk_60m  ,
  input  wire       sys_rstn     ,

  // FT232H
  input  wire       usb_rxf_n    ,
  input  wire       usb_txf_n    ,
  output reg        usb_oe_n     ,
  output wire       usb_rd_n     ,
  output wire       usb_wr_n     ,
  inout  wire [7:0] usb_data     ,

  // fifo
  input  wire       tx_fifo_empty,
  output wire       tx_fifo_rd_en,
  input  wire [7:0] tx_fifo_dout ,
  output wire       rx_fifo_wr_en,
  output wire [7:0] rx_fifo_din
);

  localparam IDLE  = 0;
  localparam READ  = 1;
  localparam WRITE = 2;

  reg [1:0] state;
  reg usb_oe_n_m1; // the suffix _m1 indicates that the signal is a one-beat signal

  assign usb_wr_n = (state == WRITE && usb_txf_n == 1'b0 && tx_fifo_empty == 1'b0) ? 1'b0:1'b1;
  assign usb_data = (state == WRITE) ? tx_fifo_dout:8'hzz;
  assign usb_rd_n = (usb_oe_n_m1 == 1'b0 && usb_oe_n == 1'b0 && usb_rxf_n == 1'b0) ? 1'b0:1'b1;

  assign tx_fifo_rd_en = (state == WRITE && usb_txf_n == 1'b0 && tx_fifo_empty == 1'b0) ? 1'b1:1'b0;
  assign rx_fifo_wr_en = (usb_oe_n_m1 == 1'b0 && usb_rxf_n == 1'b0) ? 1'b1:1'b0;
  assign rx_fifo_din = (state == READ) ? usb_data:8'hzz;

  always @(posedge usb_clk_60m or negedge sys_rstn) begin
    if (!sys_rstn)
      usb_oe_n <= 1'b1;
    else if (usb_rxf_n == 1'b0)
      usb_oe_n <= 1'b0;
    else if (usb_rxf_n)
      usb_oe_n <= 1'b1;
    else
      usb_oe_n <= usb_oe_n;
  end

  always @(posedge usb_clk_60m or negedge sys_rstn) begin
    if (!sys_rstn)
      usb_oe_n_m1 <= 1'b1;
    else
      usb_oe_n_m1 <= usb_oe_n;
  end

  always @(posedge usb_clk_60m or negedge sys_rstn) begin
    if (!sys_rstn) begin
      state <= IDLE;
    end
    else begin
      case (state)
        IDLE:begin
          if (usb_rxf_n == 1'b0)
            state <= READ;
          else if (usb_txf_n == 1'b0 && tx_fifo_empty == 1'b0)
            state <= WRITE;
        end
        READ:begin
          if (usb_rxf_n == 1'b1)
            state <= IDLE;
        end
        WRITE:begin
          if (usb_txf_n == 1'b1 || tx_fifo_empty == 1'b1)
            state <= IDLE;
        end
        default:state <= IDLE;
      endcase
    end
  end

endmodule
