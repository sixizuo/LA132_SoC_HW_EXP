module apb_ram #(
    parameter   D_WIDTH = 32    ,
    parameter   D_DEPTH = 1024  
) (
	input  wire                 apb_pclk   ,
	input  wire                 apb_prstn  ,
	input  wire                 apb_psel   ,
	input  wire [31:0]          apb_paddr  ,
	input  wire                 apb_pwrite ,
	input  wire                 apb_penable,
    input  wire [D_WIDTH/8-1:0] apb_pstrb  ,
	input  wire [D_WIDTH - 1:0] apb_pwdata ,
	output wire [D_WIDTH - 1:0] apb_prdata ,
	output wire                 apb_pready 
);

localparam A_WIDTH = (D_DEPTH == 1) ? 1 : $clog2(D_DEPTH);

reg [D_WIDTH - 1 : 0] read_port;
reg read_data_valid;

(* ram_style="block" *)reg [D_WIDTH - 1 : 0] mem [0 : D_DEPTH - 1];
wire wr_en = apb_psel && apb_penable && apb_pwrite;
wire rd_en = apb_psel && ~apb_pwrite;
wire rd_done = read_data_valid && apb_penable;
wire [A_WIDTH - 1 : 0] valid_addr = {apb_paddr[A_WIDTH - 1 : $clog2(D_WIDTH / 8)], 
                                    {$clog2(D_WIDTH / 8){1'b0}}};
wire [D_WIDTH - 1:0] wmask;

genvar i;
generate for (i = 0; i < D_WIDTH; i = i + 8) begin
    assign wmask[i +: 8] = {8{apb_pstrb[i / 8]}};
end endgenerate

always @(posedge apb_pclk) begin
    if (wr_en) begin
        mem[valid_addr] <=  (apb_pwdata[D_WIDTH - 1 : 0] &  wmask) | 
                            (mem[valid_addr]             & ~wmask);
    end
    if (rd_en && !read_data_valid) begin
        read_port <= mem[valid_addr] >> (apb_paddr[$clog2(D_WIDTH/8) - 1 : 0] * 8);
        read_data_valid <= 1'b1;
    end else if (rd_done) begin
        read_data_valid <= 1'b0;
    end
end
    
assign apb_prdata = read_port;
assign apb_pready = rd_en ? read_data_valid : 1'b1;

endmodule