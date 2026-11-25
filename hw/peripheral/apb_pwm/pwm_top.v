`include "../../config.vh"

module pwm_top (
    input  wire        apb_pclk   ,
    input  wire        apb_prstn  ,
    input  wire        apb_psel   ,
    input  wire [31:0] apb_paddr  ,
    input  wire        apb_pwrite ,
    input  wire        apb_penable,
    input  wire [31:0] apb_pwdata ,
    output wire [31:0] apb_prdata ,
	output wire        apb_pready ,

    output reg [1:0]       pwm       
);

	reg [31:0] div_freq;
	reg [31:0] comp;
	reg [31:0] state;

	reg [31:0] pwm_cnt;
	reg [31:0] prdata;

	wire wr;
	wire rd;
	wire start;
	wire direction;

	assign wr = apb_penable & apb_psel & apb_pwrite;
	assign rd = apb_penable & apb_psel &!apb_pwrite;
	assign apb_pready = apb_penable;
	
	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			div_freq <= 32'b0;
			comp     <= 32'b0;
			state    <= 32'b0;
		end else if (wr) begin
			case (apb_paddr[7:0])
				`PWM_DIV_FREQ : div_freq <= apb_pwdata;
				`PWM_COMP     : comp     <= apb_pwdata;
				`PWM_STATE    : state    <= apb_pwdata;
				default : ;
			endcase
		end else begin
			div_freq <= div_freq;
			comp     <= comp    ;
			state    <= state   ;
		end
	end
	assign start = state[0];
	assign direction = state[1];//Direct motor direction

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			pwm_cnt <= 32'b0;
		end else if (pwm_cnt >= div_freq - 1) begin
			pwm_cnt <= 32'b0;
		end else if (start) begin
			pwm_cnt <= pwm_cnt + 1'b1;
		end else begin
			pwm_cnt <= pwm_cnt;
		end
	end

	always @(posedge apb_pclk or negedge apb_prstn) begin
		if (!apb_prstn) begin
			pwm <= 2'b0;
		end else if (!start || div_freq == 32'b0 || comp == 32'b0) begin
			pwm <= 2'b0;
		end else if (pwm_cnt < comp || comp >= div_freq) begin
			if(direction) pwm <= 2'b01;
			else pwm <= 2'b10;
		end else begin
			pwm <= 2'b00;
		end
	end

	always @(*) begin
		if (rd) begin
			case (apb_paddr[7:0])
				`PWM_DIV_FREQ : prdata = div_freq;
				`PWM_COMP     : prdata = comp;
				`PWM_STATE    : prdata = state;
				default: prdata = 32'b0;
			endcase
		end else begin
			prdata = 32'b0;
		end
	end
	assign apb_prdata = prdata;

endmodule // pwm_top
