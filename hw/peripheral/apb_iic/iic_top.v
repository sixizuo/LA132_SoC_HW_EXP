`include "../../config.vh"

module iic_top (
    input  wire        apb_pclk   ,
    input  wire        apb_prstn  ,
    input  wire        apb_psel   ,
	input  wire [31:0] apb_paddr  ,
	input  wire        apb_pwrite ,
    input  wire        apb_penable,
    input  wire [31:0] apb_pwdata ,
    output wire [31:0] apb_prdata ,
	output wire        apb_pready ,

	// inout  wire        iic0_scl   ,
	// inout  wire        iic0_sda   ,
	// inout  wire        iic1_scl   ,
	// inout  wire        iic1_sda   ,
	// inout  wire        iic2_scl   ,
	// inout  wire        iic2_sda   ,
	input	wire [1:0]	scl_i_u,
	output	wire [1:0]	scl_o_u,
	input 	wire [1:0]	sda_i_u,
	output 	wire [1:0]	sda_o_u,
	output 	wire 		scl_oen,
	output	wire 		sda_oen,

	output wire        iic_irq    
);

	// ================================================================ iic bus select below
	reg [7:0] iic_select;
	
	wire scl_i  ;
	wire scl_o  ;
	// wire scl_oen;
	wire sda_i  ;
	wire sda_o  ;
	// wire sda_oen;

	// wire scl_i_u0;
	// wire sda_i_u0;
	// wire scl_o_u0;
	// wire sda_o_u0;
	// wire scl_i_u1;
	// wire sda_i_u1;
	// wire scl_o_u1;
	// wire sda_o_u1;
	// wire scl_i_u2;
	// wire sda_i_u2;
	// wire scl_o_u2;
	// wire sda_o_u2;

	// wire scl_i_u[2:0];
	// wire scl_o_u[2:0];

	// wire sda_i_u[2:0];
	// wire sda_o_u[2:0];
	// IOBUF IIC_SCL_inst0(.IO(iic0_scl), .O(scl_i_u0), .I(scl_o_u0), .T(scl_oen));
	// IOBUF IIC_SDA_inst0(.IO(iic0_sda), .O(sda_i_u0), .I(sda_o_u0), .T(sda_oen));

	// IOBUF IIC_SCL_inst1(.IO(iic1_scl), .O(scl_i_u1), .I(scl_o_u1), .T(scl_oen));
	// IOBUF IIC_SDA_inst1(.IO(iic1_sda), .O(sda_i_u1), .I(sda_o_u1), .T(sda_oen));

	// IOBUF IIC_SCL_inst2(.IO(iic2_scl), .O(scl_i_u2), .I(scl_o_u2), .T(scl_oen));
	// IOBUF IIC_SDA_inst2(.IO(iic2_sda), .O(sda_i_u2), .I(sda_o_u2), .T(sda_oen));


	assign scl_o_u[0] = iic_select[0] ? scl_o : 1'b1;
	assign sda_o_u[0] = iic_select[0] ? sda_o : 1'b1;
	assign scl_o_u[1] = iic_select[1] ? scl_o : 1'b1;
	assign sda_o_u[1] = iic_select[1] ? sda_o : 1'b1;
//	assign scl_o_u[2] = iic_select[2] ? scl_o : 1'b1;
//	assign sda_o_u[2] = iic_select[2] ? sda_o : 1'b1;

	assign scl_i = iic_select[0] ? scl_i_u[0] :
					iic_select[1] ? scl_i_u[1] : 1'b1;
//					iic_select[2] ? scl_i_u[2] : 1'b1;
	assign sda_i = iic_select[0] ? sda_i_u[0] :
					iic_select[1] ? sda_i_u[1] :1'b1;
//					iic_select[2] ? sda_i_u[2] : 1'b1;
	// ================================================================ iic bus select above

	reg [7:0] prdata;
	wire wr;
	wire rd;

	// iic registers
    reg  [15:0] prer       ; // clock division register
	reg  [7:0]  ctr        ; // control register
	reg  [7:0]  treg       ; // transmit register
	wire [7:0]  rreg       ; // receive register
	reg  [7:0]  cr         ; // command register
	wire [7:0]  sr         ; // status register
	reg  [7:0]  buslock_top; // bus lock cycles register

	// control register signals
	wire core_en         ; // core work enable
	wire ien             ; // interrupt enable
	wire master_slave    ; // select master or slave mode
    wire buslock_check_en; // bus lock check enable

	// command register signals
	wire cr_sta    ; // start command
	wire cr_sto    ; // stop command
	wire cr_rd     ; // read command
	wire cr_wr     ; // write command
	wire cr_ack    ; // master ack value
	wire cr_recover; // bus lock recover command
	wire cr_iack   ; // clear interrupt
	
	// status register signals
	reg  rxack  ; // received response
	reg  al     ; // bus lost arbitration
	wire busy   ; // bus busy
	reg  tip    ; // transfer in progress
	reg  iic_int; // interrupt status
	
	wire       busy_master ; // master bus busy
	wire       busy_slave  ; // slave bus busy
	wire       rxack_master; // ack received by master
	wire       rxack_slave ; // ack received by slave
	wire [7:0] rxr_master  ; // master receive register
	wire [7:0] rxr_slave   ; // slave receive register

	// done signal
	wire done_master;
	wire done_slave;

	// master or slave
    wire sda_oen_master;
    wire sda_oen_slave;
    wire scl_oen_master;
    wire scl_oen_slave;

	// synchronization signal
    wire sda_i_sync;
    wire scl_i_sync;

    reg [23:0] buslock_cnt; // bus lock counter
	wire buslock; // bus lock
	wire iic_al; // bus lost arbitration

	assign wr = apb_psel & apb_pwrite & apb_penable;
	assign rd = apb_psel & !apb_pwrite & apb_penable;
	assign apb_pready = apb_penable;
	
	// generate some iic registers
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			prer        <= 16'hffff;
			ctr         <= 8'b0;
			treg        <= 8'b0;
			buslock_top <= 8'hff;
			iic_select  <= 8'b0000_0001;
		end else if (wr) begin
			case (apb_paddr[7:0])
				`IIC_PRERL   : prer[7:0]   <= apb_pwdata[7:0];
				`IIC_PRERH   : prer[15:8]  <= apb_pwdata[7:0];
				`IIC_CTR     : ctr         <= apb_pwdata[7:0];
				`IIC_DR      : treg        <= apb_pwdata[7:0];
				`IIC_BLK_TOP : buslock_top <= apb_pwdata[7:0];
				`IIC_SEL     : iic_select  <= apb_pwdata[7:0];
				default : ;
			endcase
		end else begin
			prer        <= prer;
            ctr         <= ctr;
			treg        <= treg;
			buslock_top <= buslock_top;
			iic_select  <= iic_select;
        end
	end
	// generate command register
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			cr <= 8'b0;
		end else if (wr & core_en & (apb_paddr[7:0] == `IIC_CR_SR)) begin
			cr <= apb_pwdata[7:0];
		end else if ((master_slave & done_master) | (!master_slave & done_slave) | iic_al) begin
			// clear command bits when done or when aribitration lost
			cr <= 8'b0;
		end
	end

	always @(*) begin
		if (rd) begin
			case (apb_paddr[7:0])
				`IIC_PRERL   : prdata = prer[7:0];
				`IIC_PRERH   : prdata = prer[15:8];
				`IIC_CTR     : prdata = ctr;
				`IIC_DR      : prdata = rreg;
				`IIC_CR_SR   : prdata = sr;
				`IIC_BLK_TOP : prdata = buslock_top;
				`IIC_SEL     : prdata = iic_select;
				default : prdata = 8'b0;
			endcase
		end else begin
			prdata = 8'b0;
		end
	end
	assign apb_prdata = {24'b0, prdata};

	assign done_slave = 1'b0;
	assign sda_oen_slave = 1'b0;
	assign scl_oen_slave = 1'b0;
	assign rxack_slave = 1'b1;
	assign busy_slave = 1'b0;

	// decode command register
	assign cr_sta     = cr[7]; 
	assign cr_sto     = cr[6];
	assign cr_rd      = cr[5];
	assign cr_wr      = cr[4];
	assign cr_ack     = cr[3];
    assign cr_recover = cr[2];
	assign cr_iack    = cr[0];

	// decode control register
	assign core_en          = ctr[7];
	assign ien              = ctr[6];
    assign master_slave     = ctr[5];
    assign buslock_check_en = ctr[1];

    assign scl_o = 1'b0;
    assign sda_o = 1'b0;
    assign sda_oen = master_slave ? sda_oen_master : sda_oen_slave;
    assign scl_oen = master_slave ? scl_oen_master : scl_oen_slave;
	assign rreg = master_slave ? rxr_master : rxr_slave;
	
	always @(posedge apb_pclk or negedge apb_prstn) begin
        if (!apb_prstn) begin
			rxack   <= 1'b0;
			al      <= 1'b0;
			tip     <= 1'b0;
			iic_int <= 1'b0;
		end else begin
			rxack   <= master_slave ? rxack_master : rxack_slave;
			al      <= iic_al | (al & !cr_sta);
			tip     <= (cr_sta | cr_rd | cr_wr | cr_recover | cr_sto); // ensure that the startup timing and stop timing are correct
			iic_int <= ((master_slave & done_master) | (!master_slave & done_slave) | iic_al | iic_int) & !cr_iack;
			// when a byte is transmitted or the master loses arbitration, iic_int becomes 1
			// if iic_int becomes 1, iic_int is always 1 until cr_iack becomes 1
			// cr_iack is decided by register, can not automatically reset to zero
		end
	end

	// generate interrupt request signal
	assign iic_irq = iic_int && ien; // iic_irq is only effective when iic_int and ien are both 1

    iic_sync_module #(1) i_sda_i_sync(.async_in(sda_i), .clock(apb_pclk), .sync_out(sda_i_sync));
    iic_sync_module #(1) i_scl_i_sync(.async_in(scl_i), .clock(apb_pclk), .sync_out(scl_i_sync));

    always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn || !buslock_check_en) begin   
			buslock_cnt <= 24'b0;
		end else if (scl_i_sync & !sda_i_sync) begin
			if (buslock_cnt != {buslock_top, 16'b0}) begin
				buslock_cnt <= buslock_cnt + 1'b1;
			end 
		end else begin
			buslock_cnt <= 24'b0;
		end
	end

    assign buslock = buslock_check_en & (buslock_cnt == {buslock_top, 16'b0});
	assign busy = master_slave ? busy_master : busy_slave;

	// generate status register
	assign sr[7] = rxack;
	assign sr[6] = busy;
	assign sr[5] = al;
	assign sr[4] = 1'b0;
    assign sr[3] = 1'b0;
    assign sr[2] = buslock;
	assign sr[1] = tip;
	assign sr[0] = iic_int;

	iic_master_byte_ctrl iic_master_byte_ctrl_isnt (
		.clk      (apb_pclk      ),
		.rstn     (apb_prstn     ),

		.ena      (core_en       ),
		.clk_cnt  (prer          ),

		.start    (cr_sta        ),
		.stop     (cr_sto        ),
		.read     (cr_rd         ),
		.write    (cr_wr         ),
		.ack_in   (cr_ack        ),
        .recover  (cr_recover    ),

		.iic_busy (busy_master   ),
		.iic_al   (iic_al        ),
		.done     (done_master   ),
		.ack_out  (rxack_master  ),

		.din      (treg          ),
		.dout     (rxr_master    ),

		.scl_i    (scl_i         ),
		.scl_oen  (scl_oen_master),
		.sda_i    (sda_i         ),
		.sda_oen  (sda_oen_master) 
	);

endmodule // iic_top
