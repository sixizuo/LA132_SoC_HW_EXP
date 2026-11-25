module uart_rfifo #(
	parameter DWIDTH = 8,
	parameter AWIDTH = 4
) (
	input  wire                clk   ,
	input  wire                rstn  ,
	input  wire                wr    ,
	input  wire [DWIDTH - 1:0] w_data,
	input  wire                rd    ,
	output wire [DWIDTH - 1:0] r_data,
	output wire                empty ,
	output wire                full  ,
	// 2026-11-02: 当前 FIFO 里的字节个数 (0 ~ 2**AWIDTH)。
	// 由 w_ptr/r_ptr 差值实时算出, 不引入新的状态寄存器, 因此不会影响原有
	// 空/满判定。软件用它可以判断"RX 里已经攒够 N 个字节", 不必靠猜时间。
	output wire [AWIDTH:0]     count
);

	// status definition
	localparam [1:0] RD_ST    = 2'b01;
	localparam [1:0] WE_ST    = 2'b10;
	localparam [1:0] WE_RD_ST = 2'b11;

	reg [DWIDTH - 1:0] array_reg [2**AWIDTH - 1:0];
	reg [AWIDTH - 1:0] w_ptr_reg ;
	reg [AWIDTH - 1:0] w_ptr_next;
	reg [AWIDTH - 1:0] w_ptr_succ;
	reg [AWIDTH - 1:0] r_ptr_reg ;
	reg [AWIDTH - 1:0] r_ptr_next;
	reg [AWIDTH - 1:0] r_ptr_succ;
	
	reg full_reg  ;
	reg empty_reg ;
	reg full_next ;
	reg empty_next;

	wire wr_en;

	always @(posedge clk or negedge rstn) begin: reset_array_reg
		integer i;
		if (!rstn) begin
			for (i = 0; i < (2**AWIDTH); i = i + 1) begin
				array_reg[i] <= 'b0;
			end
		end else if (wr_en) begin
			array_reg[w_ptr_reg] <= w_data;
		end
	end

	assign r_data = (empty && {wr_en, rd}==WE_RD_ST) ? w_data : array_reg[r_ptr_reg];      

	assign wr_en = wr & !full_reg;

	// status machine
	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			w_ptr_reg <= 'b0;
			r_ptr_reg <= 'b0;
			full_reg  <= 1'b0;
			empty_reg <= 1'b1;
		end else begin
			w_ptr_reg <= w_ptr_next;
			r_ptr_reg <= r_ptr_next;
			full_reg  <= full_next ;
			empty_reg <= empty_next;
		end
	end

	// next status logic
	always @(*) begin
		w_ptr_succ = w_ptr_reg + 1'b1;
		r_ptr_succ = r_ptr_reg + 1'b1;
		
		w_ptr_next = w_ptr_reg;
		r_ptr_next = r_ptr_reg;
		full_next  = full_reg ;
		empty_next = empty_reg;
		
		case ({wr_en, rd})
			RD_ST: begin
				if (!empty_reg) begin
					r_ptr_next = r_ptr_succ;
					full_next = 1'b0;
					if (r_ptr_succ == w_ptr_reg) begin
						empty_next = 1'b1;
					end
				end
			end
			WE_ST: begin
				if (!full_reg) begin
					w_ptr_next = w_ptr_succ;
					empty_next = 1'b0;
					if (w_ptr_succ == r_ptr_reg) begin
						full_next = 1'b1;
					end
				end
			end
			WE_RD_ST: begin
				w_ptr_next = w_ptr_succ;
				r_ptr_next = r_ptr_succ;
			end
		endcase
	end

	// set full and empty
	assign full = full_reg;
	assign empty = empty_reg;

	// 字节个数: full 时 w_ptr 与 r_ptr 相等但实际是满, 必须单独处理
	localparam [AWIDTH:0] FULL_CNT = (1 << AWIDTH);

	assign count = full_reg ? FULL_CNT
	                        : {{AWIDTH{1'b0}}, (w_ptr_reg - r_ptr_reg)};

endmodule // uart_rfifo
