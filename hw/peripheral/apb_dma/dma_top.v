module dma_top (
  input  wire           pclk        ,
  input  wire           prstn       ,

  input  wire           cfg_psel    ,
  input  wire [31 : 0]  cfg_paddr   ,
  input  wire           cfg_pwrite  ,
  input  wire           cfg_penable ,
  input  wire [31 : 0]  cfg_pwdata  ,
  output wire [31 : 0]  cfg_prdata  ,
  output wire           cfg_pready  ,

  output reg            dat_psel    ,
  output reg  [31 : 0]  dat_paddr   ,
  output wire [ 3 : 0]  dat_pstrb   ,
  output reg            dat_pwrite  ,
  output reg            dat_penable ,
  output reg  [31 : 0]  dat_pwdata  ,
  input  wire [31 : 0]  dat_prdata  ,
  input  wire           dat_pready  ,

  output reg            dma_int     
);

  localparam  S_IDLE    = 0,
              S_READ    = 1,
              S_WRITE   = 2;

  reg [31:0] r_src_addr_base;
  reg [31:0] r_dst_addr_base;
  reg [31:0] r_number_of_words;
  reg r_start;
  reg r_int_clr;
  reg r_src_addr_inc;         //地址是否递增
  reg r_dst_addr_inc;
  reg [1:0] r_word_length;    // 00:8bit, 01:16bit, 10:32bit
  reg r_int_en;

  reg [31:0] fsm_curr_status;
  reg [31:0] fsm_next_status;

  reg [31:0] dma_data_q, dma_data_d;
  reg [31:0] dma_src_addr_q, dma_src_addr_d;
  reg [31:0] dma_dst_addr_q, dma_dst_addr_d;
  reg [31:0] dma_count_q, dma_count_d;

  always @(posedge pclk or negedge prstn) begin
    if (!prstn) begin
      r_src_addr_base   <= 'b0;
      r_dst_addr_base   <= 'b0;
      r_number_of_words <= 'b0;
      r_start           <= 'b0;
      r_src_addr_inc    <= 'b0;
      r_dst_addr_inc    <= 'b0;
      r_word_length     <= 'b0;
      r_int_en          <= 'b0;
    end else begin
      if (cfg_psel && cfg_penable && cfg_pwrite &&(fsm_curr_status == S_IDLE)) begin
          case (cfg_paddr[7:0])
            'h00: r_src_addr_base   <= cfg_pwdata;
            'h04: r_dst_addr_base   <= cfg_pwdata;
            'h08: r_number_of_words <= cfg_pwdata;
            'h0C: {r_int_clr,r_start}           <= cfg_pwdata[1:0];
            'h10: {r_int_en, r_dst_addr_inc, r_src_addr_inc, r_word_length} <= cfg_pwdata[5:0];
          endcase
      end else begin
        r_start   <= 1'b0;
        r_int_clr <= 1'b0;
      end
    end
  end

  always @(posedge pclk or negedge prstn) begin
    if (!prstn) begin
      fsm_curr_status <= S_IDLE;
      dma_data_q <= 0;
      dma_src_addr_q <= 0;
      dma_dst_addr_q <= 0;
      dma_count_q <= 0;
    end else begin
      fsm_curr_status <= fsm_next_status;
      dma_data_q <= dma_data_d;
      dma_src_addr_q <= dma_src_addr_d;
      dma_dst_addr_q <= dma_dst_addr_d;
      dma_count_q <= dma_count_d;
    end
  end

  always @* begin
    dat_psel = 1'b0;
    dat_pwrite = 1'b0;
    dat_penable = 1'b0;
    dat_paddr = 'd0;
    dat_pwdata = 'd0;

    fsm_next_status = fsm_curr_status;
    dma_data_d = dma_data_q;
    dma_src_addr_d = dma_src_addr_q;
    dma_dst_addr_d = dma_dst_addr_q;
    dma_count_d = dma_count_q;
    case (fsm_curr_status)
      S_IDLE: begin
        dat_psel = 1'b0;
        dat_pwrite = 1'b0;
        dat_penable = 1'b0;
        if (r_start) begin
          fsm_next_status = S_READ;
          dma_src_addr_d = r_src_addr_base;
          dma_dst_addr_d = r_dst_addr_base;
          dma_count_d = 0;
        end
      end
      S_READ: begin
        dat_psel = 1'b1;
        dat_pwrite = 1'b0;
        dat_penable = 1'b1;
        dat_paddr = dma_src_addr_q;
        if (dat_pready) begin
          dma_count_d = dma_count_q + 1;
          fsm_next_status = S_WRITE;
          case (r_word_length)
//            'b00: dma_data_d = {24'b0, dat_prdata[dat_paddr[1:0]*8 +:  8]};
//            'b01: dma_data_d = {16'b0, dat_prdata[dat_paddr[1:0]*8 +: 16]};
            'b00: dma_data_d = dat_prdata;
            'b01: dma_data_d = dat_prdata;
            default: dma_data_d = dat_prdata;
          endcase
          if (r_src_addr_inc) begin
            case (r_word_length)
              'b00: dma_src_addr_d = dma_src_addr_q + 1;
              'b01: dma_src_addr_d = dma_src_addr_q + 2;
              default: dma_src_addr_d = dma_src_addr_q + 4;
            endcase
          end
        end
      end
      S_WRITE: begin
        dat_psel = 1'b1;
        dat_pwrite = 1'b1;
        dat_penable = 1'b1;
        dat_paddr = dma_dst_addr_q;
        case (r_word_length)
          'b00: dat_pwdata = dma_data_q[ 7:0] << (dat_paddr[1:0] * 8);
          'b01: dat_pwdata = dma_data_q[15:0] << (dat_paddr[1:0] * 8);
          default: dat_pwdata = dma_data_q;
        endcase
        if (dat_pready) begin
          if (dma_count_q == r_number_of_words) begin
            fsm_next_status = S_IDLE;
          end else begin
            fsm_next_status = S_READ;
          end
          if (r_dst_addr_inc) begin
            case (r_word_length)
              'b00: dma_dst_addr_d = dma_dst_addr_q + 1;
              'b01: dma_dst_addr_d = dma_dst_addr_q + 2;
              default: dma_dst_addr_d = dma_dst_addr_q + 4;
            endcase
          end
        end
      end
    endcase
  end

  wire dma_busy;
  assign dma_busy = (fsm_curr_status == S_IDLE)?0:1;
  assign dat_pstrb =  r_word_length == 2'b00 ? (4'b0001 << dma_dst_addr_q[1:0]) :
                      r_word_length == 2'b01 ? (4'b0011 << dma_dst_addr_q[1:0]) : 4'b1111;

  assign cfg_pready = 1'b1;
  assign cfg_prdata = (cfg_paddr[7:0] == 'h10) ? {r_int_en, r_dst_addr_inc, r_src_addr_inc, r_word_length} :
                      (cfg_paddr[7:0] == 'h00) ? r_src_addr_base :
                      (cfg_paddr[7:0] == 'h04) ? r_dst_addr_base :
                      (cfg_paddr[7:0] == 'h08) ? r_number_of_words :
                      (cfg_paddr[7:0] == 'h0C) ? {dma_int, dma_busy} :
                      0;

  always @(posedge pclk or negedge prstn) begin
    if (!prstn) begin
      dma_int <= 1'b0;
    end else begin
      if (fsm_curr_status == S_WRITE && fsm_next_status == S_IDLE && r_int_en == 1'b1) begin
        dma_int <= 1'b1;
      end else if(r_int_clr)begin
        dma_int <= 1'b0;
      end
    end
  end

  
endmodule