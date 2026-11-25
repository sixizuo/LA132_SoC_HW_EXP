`include "../../config.vh"

module touch_top (
	input  wire        apb_pclk   ,
	input  wire        apb_prstn  ,
	input  wire        apb_psel   ,
	input  wire [31:0] apb_paddr  ,
	input  wire        apb_pwrite ,
	input  wire        apb_penable,
	input  wire [31:0] apb_pwdata ,
	output wire [31:0] apb_prdata ,
	output wire        apb_pready ,

	input  wire [15:0] lcd_id     ,

	output wire        touch_scl  ,
    inout  wire        touch_sda  ,
    inout  wire        touch_int  ,
    output wire        touch_rst_n,

	output wire        touch_irq  
);

	parameter CLK_FREQ    = 32_000_000; // iic_dri_m module driver clock frequency
	parameter IIC_FREQ    = 250_000   ; // iic clock frequency
	parameter REG_NUM_WID = 8         ; // the bit width of data transmitted in one read or write operation of iic

	reg [31:0] prdata;
	reg [31:0] touch_ctrl;
	reg [31:0] touch_interval;
	reg cnt_en;
	reg [31:0] touch_delay_cnt;

	wire wr;
	wire rd;

	wire touch_work_en;
	wire touch_int_en;

	wire touch_valid;
	wire [15:0] tp_x_coord;
	wire [15:0] tp_y_coord;

	wire tc_fifo_wren ;
	wire tc_fifo_rden ;
	wire tc_fifo_full ;
	wire tc_fifo_empty;
	wire [31:0] tc_fifo_din;
	wire [31:0] tc_fifo_dout;
	wire [31:0] coord_rdata;

	wire [1:0] fifo_state;

	wire touch_int_dir;
	wire touch_int_in ;
	wire touch_int_out;
	wire touch_sda_dir;
	wire touch_sda_in ;
	wire touch_sda_out;

	wire  [6:0]               slave_addr;
	wire                      iic_exec  ;
	wire                      iic_rh_wl ;
	wire  [15:0]              iic_addr  ;
	wire  [7:0]               iic_data_w;
	wire                      bit_ctrl  ;
	wire  [REG_NUM_WID - 1:0] reg_num   ;
	wire  [7:0]               iic_data  ;
	wire                      iic_done  ;
	wire                      once_done ;
	wire                      iic_ack   ;
	wire                      dri_clk   ;

	assign wr = apb_psel & apb_pwrite & apb_penable;
	assign rd = apb_psel & !apb_pwrite & apb_penable;
	assign apb_pready = apb_penable;
	
	assign tc_fifo_wren = (touch_delay_cnt == 32'b0) ? touch_valid : 1'b0;
	assign tc_fifo_din = {tp_x_coord, tp_y_coord};
	assign tc_fifo_rden = rd & (apb_paddr[7:0] == `TOUCH_DATA);

	assign fifo_state = {tc_fifo_full, !tc_fifo_empty};

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			touch_ctrl     <= 32'b0;
			touch_interval <= 32'd95_000;
		end else if (wr) begin
			case (apb_paddr[7:0])
				`TOUCH_CTRL     : touch_ctrl     <= apb_pwdata;
				`TOUCH_INTERVAL : touch_interval <= apb_pwdata;
			endcase
		end else begin
			touch_ctrl     <= touch_ctrl    ;
			touch_interval <= touch_interval;
		end
	end

	assign touch_work_en =  touch_ctrl[0];
	assign touch_int_en = touch_ctrl[1];
	assign work_rst_n = apb_prstn & touch_work_en;
	assign touch_irq = touch_int_en & (!tc_fifo_empty);

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			cnt_en <= 1'b0;
		end else if (tc_fifo_wren) begin
			cnt_en <= 1'b1;
		end else if (touch_delay_cnt == touch_interval - 1) begin
			cnt_en <= 1'b0;
		end
	end

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			touch_delay_cnt <= 32'b0;
		end else if (touch_delay_cnt == touch_interval - 1) begin
			touch_delay_cnt <= 32'b0;
		end else if (cnt_en) begin
			touch_delay_cnt <= touch_delay_cnt + 1'b1;
		end else begin
			touch_delay_cnt <= 32'b0;
		end
	end

	always @(*) begin
		if (rd) begin
			case (apb_paddr[7:0])
				`TOUCH_CTRL     : prdata = {28'b0, fifo_state, touch_ctrl[1:0]};
				`TOUCH_INTERVAL : prdata = touch_interval;
				`TOUCH_DATA     : prdata = coord_rdata;
				default: prdata = 32'b0;
			endcase
		end else begin
			prdata = 32'b0;
		end
	end
	assign apb_prdata = prdata;

	assign touch_sda = touch_sda_dir ? touch_sda_out : 1'bz;
	assign touch_sda_in = touch_sda;
	assign touch_int = touch_int_dir ? touch_int_out : 1'bz;
	assign touch_int_in = touch_int;

	iic_dri_m #(
		.CLK_FREQ (CLK_FREQ),
		.IIC_FREQ (IIC_FREQ),
		.WIDTH    (REG_NUM_WID)
	) iic_dri_m_inst (
		.clk        (apb_pclk     ),
		// .rst_n      (apb_prstn    ),
		.rst_n      (work_rst_n   ),

		.slave_addr (slave_addr   ),
		.iic_exec   (iic_exec     ),
		.iic_rh_wl  (iic_rh_wl    ),
		.iic_addr   (iic_addr     ),
		.iic_data_w (iic_data_w   ),
		.bit_ctrl   (bit_ctrl     ),
		.reg_num    (reg_num      ),
		.iic_data   (iic_data     ),
		.iic_done   (iic_done     ),
		.once_done  (once_done    ),
		.scl        (touch_scl    ),
		.sda_in     (touch_sda_in ),
		.sda_out    (touch_sda_out),
		.sda_dir    (touch_sda_dir),
		.ack        (iic_ack      ),

		.dri_clk    (dri_clk      ) 
	);

	touch_dri #(
		.WIDTH (REG_NUM_WID)
	) touch_dri_inst (
		.clk           (dri_clk       ),
		// .rst_n         (apb_prstn     ),
		.rst_n         (work_rst_n    ),

		.slave_addr    (slave_addr    ),
		.iic_exec      (iic_exec      ),
		.iic_rh_wl     (iic_rh_wl     ),
		.iic_addr      (iic_addr      ),
		.iic_data_w    (iic_data_w    ),
		.bit_ctrl      (bit_ctrl      ),
		.reg_num       (reg_num       ),
		.iic_data      (iic_data      ),
		.iic_ack       (iic_ack       ),
		.iic_done      (iic_done      ),
		.once_done     (once_done     ),
		
		.lcd_id        (lcd_id        ),
		.touch_valid   (touch_valid   ),
		.tp_x_coord    (tp_x_coord    ),
		.tp_y_coord    (tp_y_coord    ),
		.touch_rst_n   (touch_rst_n   ),
		.touch_int_in  (touch_int_in  ),
		.touch_int_dir (touch_int_dir ),
		.touch_int_out (touch_int_out ) 
	);

	touch_coord_fifo touch_coord_fifo_inst (
		// In standard mode, the data read flags behind the read signal by one clock cycle.
		// In FWFT(First-Word Fall-Through) mode, When the read signal is valid, the read data is also immediately valid.
		// Select FWFT mode.
		.wr_clk (dri_clk      ),  // input wire wr_clk
		.wr_rst (!work_rst_n  ),  // input wire wr_rst
		.rd_clk (apb_pclk     ),  // input wire rd_clk
		.rd_rst (!work_rst_n  ),  // input wire rd_rst
		.wr_en  (tc_fifo_wren ),  // input wire wr_en
		.din    (tc_fifo_din  ),  // input wire [31 : 0] din
		.rd_en  (tc_fifo_rden ),  // input wire rd_en
		.dout   (tc_fifo_dout ),  // output wire [31 : 0] dout
		.full   (tc_fifo_full ),  // output wire full
		.empty  (tc_fifo_empty)   // output wire empty
	);
	assign coord_rdata = tc_fifo_dout;

endmodule
