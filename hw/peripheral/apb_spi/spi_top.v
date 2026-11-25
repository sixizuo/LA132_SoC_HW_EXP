`include "../../config.vh"

module spi_top (
    input  wire        apb_pclk   ,
    input  wire        apb_prstn  ,
    input  wire        apb_psel   ,
	input  wire [31:0] apb_paddr  ,
	input  wire        apb_pwrite ,
    input  wire        apb_penable,
    input  wire [31:0] apb_pwdata ,
    output wire [31:0] apb_prdata ,
	output wire        apb_pready ,

	output wire [3:0]  spi_clk    ,
	input  wire [3:0]  spi_miso   ,
	output wire [3:0]  spi_mosi   ,
	output wire [3:0]  spi_csn    ,
	
	output reg  [7:0]  spi_mul    , // serial peripheral multiplex register

	output wire        spi_irq    
);

	reg        sck   ;
	wire       mosi_o;
    wire       miso_i;
    wire [3:0] csn   ; // chicp select enable, low active

	// ================================================================ SPI bus select above
	assign spi_clk[0] = sck;
	assign spi_clk[1] = sck;
	assign spi_clk[2] = sck;
	assign spi_clk[3] = sck;

	assign miso_i = &spi_miso;

	assign spi_mosi[0] = mosi_o;
	assign spi_mosi[1] = mosi_o;
	assign spi_mosi[2] = mosi_o;
	assign spi_mosi[3] = mosi_o;

	assign spi_csn[0] =!csn[0];
	assign spi_csn[1] =!csn[1];
	assign spi_csn[2] =!csn[2];
	assign spi_csn[3] =!csn[3];
	// ================================================================ SPI bus select above

	reg [7:0] prdata;
	wire wr;
	wire rd;
	wire spsr_wr;

	// fifo signals
	wire rfrd;
	wire rffull;
	wire rfempty;
	wire [7:0] rfdout;
	reg rfwe;
	wire wfwe;
	wire wffull;
	wire wfempty;
	wire [7:0] wfdout;
	reg wfrd;

	// spi registers
	reg  [7:0] spcr  ; // serial peripheral control register
	wire [7:0] spsr  ; // serial peripheral status register
	wire [7:0] treg  ; // serial peripheral transmit register
	wire [7:0] rreg  ; // serial peripheral receive register
	reg  [7:0] sper  ; // serial peripheral external register
	reg  [7:0] softcs; // serial peripheral select control register

	// control register signals
	wire       spie; // interrupt enable
	wire       spe ; // core work enable
	wire       ms  ; // select master or slave mode
	wire       cpol; // clock polarity
	wire       cpha; // clock phase
	wire [1:0] spr ; // control clock division

	// external register signals
	wire [1:0] icnt; // number of received bytes triggering interrupt
	wire spi_mode; // select spi interface mode
	// spi_mode = 0 : sampling and sending timing simultaneously
	// spi_mode = 1 : sampling and sending timing are staggered by half a cycle
	wire [1:0] spre; // control clock division

	reg spif; // interrupt status and interrupt clear
	reg wcol; // write register overflow flag bit
	reg busy; // bus busy
	reg [11:0] clk_cnt; // clock division counter
	reg [1:0] status; // the status of transfer status machine 
	reg [2:0] bit_cnt; // transfer bit counter
	reg [7:0] shift_reg; // transmit and receive register
	reg sample; // receive value
	reg [1:0] byte_cnt; // receive byte counter

	wire [3:0] csn_en; // chicp select enable, high active
	wire wfov; // write fifo overrun
	wire [3:0] espr; // control clock division
	wire rirq; // receive interrupt request
	wire clk_en; // spi clock

	assign wr = apb_psel & apb_pwrite & apb_penable;
	assign rd = apb_psel & !apb_pwrite & apb_penable;
	assign apb_pready = apb_penable;
	
	// generate some spi registers
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			spcr    <= 8'h10; // set master bit, clk div 2
			sper    <= 8'h0 ;
			softcs  <= 8'hf0;
			spi_mul <= 8'h0 ;
		end else if (wr) begin
			case (apb_paddr[7:0])
				`SPI_SPCR   : spcr    <= apb_pwdata | 8'h10; // always set master bit
				`SPI_SPER   : sper    <= apb_pwdata;
				`SPI_SOFTCS : softcs  <= apb_pwdata;
				`SPI_MUL    : spi_mul <= apb_pwdata;
				default : ;
			endcase
		end else begin
			spcr    <= spcr   ;
			sper    <= sper   ;
			softcs  <= softcs ;
			spi_mul <= spi_mul;
		end
	end
	assign csn_en[3:0] = softcs[3:0];
	assign csn[3:0] = ~softcs[7:4] & csn_en;

	// write fifo
	assign wfwe = wr & (apb_paddr[7:0] == `SPI_DATA);
	// read fifo
	assign rfrd = rd & (apb_paddr[7:0] == `SPI_DATA);

	assign spsr_wr = wr & (apb_paddr[7:0] == `SPI_SPSR);
	assign treg = apb_pwdata[7:0];

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			spif <= 1'b0;
		end else if (!spe) begin
			spif <= 1'b0;
		end else begin
			spif <= (rirq | spif) & !(spsr_wr & apb_pwdata[7]);
		end
	end

	// generate interrupt request signal
	assign spi_irq = spif & spie; // spi_irq is only effective when spif and spie are both 1

	assign wfov = wr & wffull; // when a write data register operation is required and the write register is full, the write register overflow flag bit 'wfov' is 1.
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			wcol <= 1'b0;
		end else if (!spe) begin
			wcol <= 1'b0;
		end else begin
			wcol <= (wfov | wcol) & !(spsr_wr & apb_pwdata[6]);
		end
	end

	always @(*) begin
		if (rd) begin
			case (apb_paddr[7:0])
				`SPI_SPCR   : prdata = spcr;
				`SPI_SPSR   : prdata = spsr;
				`SPI_DATA   : prdata = rreg;
				`SPI_SPER   : prdata = sper;
				`SPI_SOFTCS : prdata = softcs;
				`SPI_MUL    : prdata = spi_mul;
				default : ;
			endcase
		end else begin
			prdata = 8'b0;
		end
	end
	assign apb_prdata = {24'b0, prdata};

	spi_fifo #(
		.dw (8)
	) spi_fifo_wr (
		.clk   (apb_pclk ),
		.rstn  (apb_prstn),
		.wr    (wfwe     ),
		.din   (treg     ),
		.rd    (wfrd     ),
		.dout  (wfdout   ),
		.clr   (!spe     ),
		.full  (wffull   ),
		.empty (wfempty  ) 
	);

	spi_fifo #(
		.dw (8)
	) spi_fifo_rd (
		.clk   (apb_pclk ),
		.rstn  (apb_prstn),
		.wr    (rfwe     ),
		.din   (shift_reg),
		.rd    (rfrd     ),
		.dout  (rfdout   ),
		.clr   (!spe     ),
		.full  (rffull   ),
		.empty (rfempty  )
	);
	assign rreg = rfdout;

	// decode serial peripheral control register
	assign spie = spcr[7];  
	assign spe  = spcr[6];  
	assign ms   = spcr[4];  
	assign cpol = spcr[3];  
	assign cpha = spcr[2];  
	assign spr  = spcr[1:0];

	// decode serial peripheral extension register
	assign icnt = sper[7:6];
	assign spi_mode = sper[2];
	assign spre = sper[1:0];

	// generate clock division
	assign espr = {spre, spr};

	// generate status register
	assign spsr[7] = spif   ;
	assign spsr[6] = wcol   ;
	assign spsr[5] = 1'b0   ;
	assign spsr[4] = busy   ;
	assign spsr[3] = wffull ;
	assign spsr[2] = wfempty;
	assign spsr[1] = rffull ;
	assign spsr[0] = rfempty;

	// count byte of received data, for interrupt generation
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			byte_cnt <= 2'b0;
		end else if (!spe) begin
			byte_cnt <= icnt;
		end else if (rfwe) begin
			if (|byte_cnt) begin
				byte_cnt <= byte_cnt - 1'b1;
			end else begin
				byte_cnt <= icnt;
			end
		end
	end
	assign rirq = !(|byte_cnt) & rfwe;

	// generate spi bus busy signal 
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			busy <= 1'b0;
		end else begin
			busy <= !wfempty || (|status); // write fifo is not empty or transfer status machine is incomplete 
		end
	end

	// generate spi clock
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			clk_cnt <= 12'b0;
		end else if (spe & (|clk_cnt & |status)) begin
			clk_cnt <= clk_cnt - 1'b1;
		end else begin
			case (espr)
				4'b0000 : clk_cnt <= 12'h0;   // 2
				4'b0001 : clk_cnt <= 12'h1;   // 4
				4'b0010 : clk_cnt <= 12'h3;   // 8
				4'b0011 : clk_cnt <= 12'h7;   // 16
				4'b0100 : clk_cnt <= 12'hf;   // 32
				4'b0101 : clk_cnt <= 12'h1f;  // 64
				4'b0110 : clk_cnt <= 12'h3f;  // 128
				4'b0111 : clk_cnt <= 12'h7f;  // 256
				4'b1000 : clk_cnt <= 12'hff;  // 512
				4'b1001 : clk_cnt <= 12'h1ff; // 1024
				4'b1010 : clk_cnt <= 12'h3ff; // 2048
				4'b1011 : clk_cnt <= 12'h7ff; // 4096
				default : ;
			endcase
		end
	end
	assign clk_en = !(|clk_cnt); // divide apb_pclk by clk_cnt to obtain clk_en: clk_en = apb_pclk / clk_cnt

	// transfer status machine
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			status    <= 2'b0;
			bit_cnt   <= 3'h0;
			shift_reg <= 8'h0;
			wfrd      <= 1'b0;
			rfwe      <= 1'b0;
			sck       <= 1'b0;
		end else if (!spe) begin
			status    <= 2'b0;
			bit_cnt   <= 3'h0;
			shift_reg <= 8'h0;
			wfrd      <= 1'b0;
			rfwe      <= 1'b0;
			sck       <= 1'b0;
		end else if (spi_mode) begin
			wfrd <= 1'b0;
			rfwe <= 1'b0;
			case (status)
				2'b00 : begin
					bit_cnt   <= 3'h7  ; // initialize transfer bit counter
					shift_reg <= wfdout; // load transmit register
					sck       <= cpol  ; // initialize sck

					if (!wfempty) begin
						wfrd   <= 1'b1;
						status <= 2'b1;
					end
				end
				2'b01 : begin
					if (clk_en) begin
						sck    <= !sck;
						status <= 2'b10;
						if (cpha == 0) begin
							sample <= miso_i;
						end
					end
				end
				2'b10 : begin
					if (clk_en) begin
						sck   <= !sck;
						status <= 2'b11;
						if (cpha == 0) begin
							shift_reg <= {shift_reg[6:0], sample};
						end else begin
							sample <= miso_i;
						end
					end
				end
				2'b11 : begin
					if (clk_en) begin
						bit_cnt <= bit_cnt - 1'b1;
						if (cpha == 0) begin
							sample <= miso_i;
						end else begin
							shift_reg <= {shift_reg[6:0], sample};
						end

						if (!(|bit_cnt)) begin
							status <= 2'b0;
							sck    <= cpol;
							rfwe   <= 1'b1;
						end else begin
							status <= 2'b10;
							sck    <= !sck;
						end
					end
				end
			endcase
		end else begin
			wfrd <= 1'b0;
			rfwe <= 1'b0;
			case (status)
				2'b00 : begin
					bit_cnt   <= 3'h7;   // initialize transfer bit counter
					shift_reg <= wfdout; // load transmit register
					sck       <= cpol;   // initialize sck

					if (!wfempty) begin
						wfrd   <= 1'b1;
						status <= 2'b1;
						if (cpha) begin
							sck <= !sck;
						end
					end
				end
				2'b01 : begin
					if (clk_en) begin
						sck    <= !sck;
						status <= 2'b11;
					end
				end
				2'b10 : begin
					status <= 2'b0;
				end
				2'b11 : begin
					if (clk_en) begin
						bit_cnt   <= bit_cnt - 1'b1;
						shift_reg <= {shift_reg[6:0], miso_i};

						if (!(|bit_cnt)) begin
							status <= 2'b0;
							sck    <= cpol;
							rfwe   <= 1'b1;
						end else begin
							status <= 2'b1;
							sck    <= !sck;
						end
					end
				end
				default: begin
					status <= 2'b0;
				end
			endcase
		end
	end

	assign mosi_o = shift_reg[7];

endmodule // spi_top
