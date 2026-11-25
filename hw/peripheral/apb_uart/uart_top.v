`include "../../config.vh"

module uart_top (
	input  wire        apb_pclk   ,
	input  wire        apb_prstn  ,
	input  wire        apb_psel   ,
	input  wire [31:0] apb_paddr  ,
	input  wire        apb_pwrite ,
	input  wire        apb_penable,
	input  wire [31:0] apb_pwdata ,
	output wire [31:0] apb_prdata ,
	output wire        apb_pready ,

	input  wire        uart_rx   ,
	output wire        uart_tx   ,

	output wire        uart_irq   
);
	
	reg [7:0] prdata;
	reg [2:0] uart_ctrl;

	wire wr;
	wire rd;
 
	// data between APB and fifo
	wire [7:0] uart_wdata;  
	wire [7:0] uart_rdata;
	
	// fifo control signals
	wire tx_fifo_wren;
	wire rx_fifo_rden;
	
	// data between fifo and tx/rx
	wire [7:0] tx_fifo_out;
	wire [7:0] rx_fifo_out;
	
	// fifo status
	wire tx_full ;
	wire tx_empty;
	wire rx_full ;
	wire rx_empty;
	wire tx_done ;
	wire rx_done ;
	wire [7:0] status;
	wire [4:0] rx_count;   // RX FIFO 里的字节个数 (2026-11-02 新增, 读 UART_STAT)

	wire b_tick; // baudrate signal
	
	assign wr = apb_psel & apb_pwrite & apb_penable;
	assign rd = apb_psel & !apb_pwrite & apb_penable;
	// assign apb_pready = wr || rd;
	// 2026-11-02: 读 UART_DATA 不再要求 rx FIFO 非空.
	//   旧行为: 空 FIFO 时不给 pready -> APB 总线挂起 -> 只能靠 apb_bridge 的
	//   4096 拍超时兜底, DMA 会把超时补回的旧数据当成有效字节重复搬.
	//   新行为: 空 FIFO 读也立即 acpready, 数据返回 0x00. 读指针由 uart_rfifo
	//   内部保护(empty 时不推进), 所以空读不会破坏 FIFO 状态.
	//   软件若需要"有没有新数据", 请读 UART_CTRL 的 rx_nonempty 位再取数.
	assign  apb_pready    =  (apb_paddr[7:0]  == `UART_CTRL &&  (wr || rd)) ? 1'b1:							//ctrl_reg-ack
						   (apb_paddr[7:0]  == `UART_DATA && rd) ? 1'b1:									//rfifo-ack (empty 也响应)
						   (apb_paddr[7:0]  == `UART_DATA && !tx_full  && wr) ? 1'b1:						//wfifo-ack
						   (apb_paddr[7:0]  == `UART_STAT && rd) ? 1'b1:									//rx 字节个数
						   1'b0;

	assign tx_fifo_wren = wr & (apb_paddr[7:0] == `UART_DATA);
	assign uart_ctrl_wr = wr & (apb_paddr[7:0] == `UART_CTRL);
	assign rx_fifo_rden = rd & (apb_paddr[7:0] == `UART_DATA);
	assign uart_wdata = apb_pwdata[7:0];


	assign status = {6'b000000, tx_full, !rx_empty};

	always @(*) begin
		if (rd) begin
			case (apb_paddr[7:0])
				// 空读明确返回 0x00 (而不是 FIFO 里残留的上一个字节),
				// 这样 DMA/调试时一眼能看出这是"读空", 不会误当成有效数据.
				`UART_DATA : prdata = (rx_empty && !rx_done) ? 8'h00 : uart_rdata;
				`UART_CTRL : prdata = status;
				// 2026-11-02: RX FIFO 当前字节个数 [4:0], 0~16。
				// 软件靠它判断"串口已经收够 N 个字节", 不再用固定延时猜。
				`UART_STAT : prdata = {3'b000, rx_count};
				default : prdata = 8'b0;
			endcase
		end else begin
			prdata = 8'b0;
		end
	end
	assign apb_prdata = {24'b0, prdata};

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			uart_ctrl <= 3'b0;
		end else if (uart_ctrl_wr) begin
			uart_ctrl <= apb_pwdata[2:0];
		end
	end
	
	assign uart_irq = !rx_empty;

	baudgen baudgen_isnt (
		.clk           (apb_pclk      ),
		.rstn          (apb_prstn     ),
		.baudtick      (b_tick        ),
		.baudtick_ctrl (uart_ctrl[1:0])
	);
	
	// transmitter fifo
	uart_tfifo #(
		.DWIDTH(8),
		.AWIDTH(4)
	) uart_tfifo_inst (
		.clk    (apb_pclk    ),
		.rstn   (apb_prstn   ),
		.wr     (tx_fifo_wren),
		.w_data (uart_wdata  ),
		.rd     (tx_done     ),
		.r_data (tx_fifo_out ),
		.empty  (tx_empty    ),
		.full   (tx_full     )
	);

	// receiver fifo
	uart_rfifo #(
		.DWIDTH(8),
		.AWIDTH(4)
	) uart_rfifo_inst (
		.clk    (apb_pclk    ),
		.rstn   (apb_prstn   ),
		.wr     (rx_done     ),
		.w_data (rx_fifo_out ),
		.rd     (rx_fifo_rden),
		.r_data (uart_rdata  ),
		.empty  (rx_empty    ),
		.full   (rx_full     ),
		.count  (rx_count    )
	);

	// uart transmitter
	uart_tx uart_tx_inst (
		.clk          (apb_pclk    ),
		.rstn         (apb_prstn   ),
		.b_tick       (b_tick      ),
		.tx_start     (!tx_empty   ),		
		.d_in         (tx_fifo_out ),
		.tx           (uart_tx    ),
		.tx_done      (tx_done     ),
		.parity_check (uart_ctrl[2])
	);

	// uart receiver
	uart_rx uart_rx_inst (
		.clk          (apb_pclk    ),
		.rstn         (apb_prstn   ),
		.b_tick       (b_tick      ),
		.rx           (uart_rx    ),
		.rx_done      (rx_done     ),
		.dout         (rx_fifo_out ),
		.parity_check (uart_ctrl[2])
	);

endmodule // uart_top
