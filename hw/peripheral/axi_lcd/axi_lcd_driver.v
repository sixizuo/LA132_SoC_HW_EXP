module axi_lcd_driver #(
  parameter COLOR_WIDTH = 24
) (
  input  wire                     lcd_pclk  , //
  input  wire                     rstn      , // active low
  // ---- 以下两个端口是相对于工程原 apb_lcd/lcd_driver.v 的**新增** ----
  //  hold       : 行首整行节流。1 = 冻结 h_cnt (= 冻结整条扫描链)。
  //               ★ 内部**强制限定只在 h_cnt==0 (行首消隐) 生效**, 行内
  //                 一律忽略。原因: 若允许在可见区冻结, h_cnt 会停在
  //                 data_req==1 的位置, data_req 被拉长成持续为 1 ->
  //                 读指针 px_cnt 一路暴涨甩开写指针 -> fill_level 回绕 ->
  //                 预取永久停摆, 整屏死锁 (曾实测"只显示 4 帧就停")。
  //                 限定行首后, 冻结期间 lcd_en/data_req 恒 0, 只表现为
  //                 "消隐期被拉长", 屏上看不见, 映射不受任何影响。
  //  panel_rstn : 面板复位/背光寄存器的复位参考。必须是**真正的系统复位**
  //               (lcd_sys_rstn), 不能是带流控的 rstn —— 否则预取缓冲每次
  //               瞬时不足都会顺带复位 LCD 面板, 画面在玻璃上重新起扫,
  //               表现为"静止画面位置不停变化"。
  input  wire                     hold      ,
  input  wire                     panel_rstn,

  input  wire [15:0]              lcd_id    , //
  input  wire [COLOR_WIDTH - 1:0] pixel_data, //
  output wire [10:0]              pixel_xpos, // current pixel abscissa
  output wire [10:0]              pixel_ypos, // current pixel ordinate

  // ---- 新增 (AXI 显存预取引擎使用) ----
  output wire                     data_req  , // 每行有效像素取数脉冲, 比 lcd_de 提前 1 拍
  output wire                     frame_start, // 帧首拍 (h_cnt==0 && v_cnt==0)

  // rgb lcd interface
  output wire                     lcd_clk   , // lcd clock signal
  output reg                      lcd_rstn  , // lcd reset signal
  output wire                     lcd_de    , // lcd data enable signal
  output reg                      lcd_bl    , // lcd backlight control signal
  output wire                     lcd_hs    , // lcd line synchronization signal
  output wire                     lcd_vs    , // lcd field synchronization signal
  output wire [COLOR_WIDTH - 1:0] lcd_rgb     // lcd rgb888 color data
);

  // localparam define
  // 4.3' 480*272
  localparam  H_SYNC_4342  = 11'd41 ;
  localparam  H_BACK_4342  = 11'd2  ;
  localparam  H_DISP_4342  = 11'd480;
  localparam  H_FRONT_4342 = 11'd2  ;
  localparam  H_TOTAL_4342 = 11'd525;

  localparam  V_SYNC_4342  = 11'd10 ;
  localparam  V_BACK_4342  = 11'd2  ;
  localparam  V_DISP_4342  = 11'd272;
  localparam  V_FRONT_4342 = 11'd2  ;
  localparam  V_TOTAL_4342 = 11'd286;

  // 7' 800*480
  localparam  H_SYNC_7084  = 11'd128 ;
  localparam  H_BACK_7084  = 11'd88  ;
  localparam  H_DISP_7084  = 11'd800 ;
  localparam  H_FRONT_7084 = 11'd40  ;
  localparam  H_TOTAL_7084 = 11'd1056;

  localparam  V_SYNC_7084  = 11'd2  ;
  localparam  V_BACK_7084  = 11'd33 ;
  localparam  V_DISP_7084  = 11'd480;
  localparam  V_FRONT_7084 = 11'd10 ;
  localparam  V_TOTAL_7084 = 11'd525;

  // 7' 1024*600
  localparam  H_SYNC_7016  = 11'd20  ;
  localparam  H_BACK_7016  = 11'd140 ;
  localparam  H_DISP_7016  = 11'd1024;
  localparam  H_FRONT_7016 = 11'd160 ;
  localparam  H_TOTAL_7016 = 11'd1344;

  localparam  V_SYNC_7016  = 11'd3  ;
  localparam  V_BACK_7016  = 11'd20 ;
  localparam  V_DISP_7016  = 11'd600;
  localparam  V_FRONT_7016 = 11'd12 ;
  localparam  V_TOTAL_7016 = 11'd635;

  // 10.1' 1280*800
  localparam  H_SYNC_1018  = 11'd10  ;
  localparam  H_BACK_1018  = 11'd80  ;
  localparam  H_DISP_1018  = 11'd1280;
  localparam  H_FRONT_1018 = 11'd70  ;
  localparam  H_TOTAL_1018 = 11'd1440;

  localparam  V_SYNC_1018  = 11'd3  ;
  localparam  V_BACK_1018  = 11'd10 ;
  localparam  V_DISP_1018  = 11'd800;
  localparam  V_FRONT_1018 = 11'd10 ;
  localparam  V_TOTAL_1018 = 11'd823;

  // 4.3' 800*480
  localparam  H_SYNC_4384  = 11'd128 ;
  localparam  H_BACK_4384  = 11'd88  ;
  localparam  H_DISP_4384  = 11'd800 ;
  localparam  H_FRONT_4384 = 11'd40  ;
  localparam  H_TOTAL_4384 = 11'd1056;

  localparam  V_SYNC_4384  = 11'd2  ;
  localparam  V_BACK_4384  = 11'd33 ;
  localparam  V_DISP_4384  = 11'd480;
  localparam  V_FRONT_4384 = 11'd10 ;
  localparam  V_TOTAL_4384 = 11'd525;

  reg [10:0] h_sync ;
  reg [10:0] h_back ;
  reg [10:0] h_disp ;
  reg [10:0] h_total;
  reg [10:0] v_sync ;
  reg [10:0] v_back ;
  reg [10:0] v_disp ;
  reg [10:0] v_total;
  reg [10:0] h_cnt  ;
  reg [10:0] v_cnt  ;

  wire lcd_en;
  // data_req / frame_start 已在端口列表中声明

  assign lcd_clk = lcd_pclk;
  assign lcd_de = lcd_en;
  assign lcd_hs = 1'b1;
  assign lcd_vs = 1'b1;

  always @(*) begin
    case (lcd_id)
      16'h4342:begin
        h_sync  = H_SYNC_4342;
        h_back  = H_BACK_4342;
        h_disp  = H_DISP_4342;
        h_total = H_TOTAL_4342;
        v_sync  = V_SYNC_4342;
        v_back  = V_BACK_4342;
        v_disp  = V_DISP_4342;
        v_total = V_TOTAL_4342;
      end
      16'h7084:begin
        h_sync  = H_SYNC_7084;
        h_back  = H_BACK_7084;
        h_disp  = H_DISP_7084;
        h_total = H_TOTAL_7084;
        v_sync  = V_SYNC_7084;
        v_back  = V_BACK_7084;
        v_disp  = V_DISP_7084;
        v_total = V_TOTAL_7084;
      end
      16'h7016:begin
        h_sync  = H_SYNC_7016;
        h_back  = H_BACK_7016;
        h_disp  = H_DISP_7016;
        h_total = H_TOTAL_7016;
        v_sync  = V_SYNC_7016;
        v_back  = V_BACK_7016;
        v_disp  = V_DISP_7016;
        v_total = V_TOTAL_7016;
      end
      16'h4384:begin
        h_sync  = H_SYNC_4384;
        h_back  = H_BACK_4384;
        h_disp  = H_DISP_4384;
        h_total = H_TOTAL_4384;
        v_sync  = V_SYNC_4384;
        v_back  = V_BACK_4384;
        v_disp  = V_DISP_4384;
        v_total = V_TOTAL_4384;
      end
      16'h1018:begin
        h_sync  = H_SYNC_1018;
        h_back  = H_BACK_1018;
        h_disp  = H_DISP_1018;
        h_total = H_TOTAL_1018;
        v_sync  = V_SYNC_1018;
        v_back  = V_BACK_1018;
        v_disp  = V_DISP_1018;
        v_total = V_TOTAL_1018;
      end
      default:begin
        h_sync  = H_SYNC_4342;
        h_back  = H_BACK_4342;
        h_disp  = H_DISP_4342;
        h_total = H_TOTAL_4342;
        v_sync  = V_SYNC_4342;
        v_back  = V_BACK_4342;
        v_disp  = V_DISP_4342;
        v_total = V_TOTAL_4342;
      end
    endcase
  end

  // hold 只在行首有效 —— 见端口说明里的死锁分析, 这一条不能省。
  wire hold_eff = hold && (h_cnt == 11'd0);

  always @(posedge lcd_pclk or negedge rstn) begin
    if (!rstn) begin
      h_cnt <= 11'd0;
    end
    else begin
      if (h_cnt == h_total - 1'b1) begin
        h_cnt <= 11'd0;
      end
      else if (!hold_eff) begin      // hold 时冻结 (= 拉长消隐, 见端口说明)
        h_cnt <= h_cnt + 1'b1;
      end
    end
  end

  always @(posedge lcd_pclk or negedge rstn) begin
    if (!rstn) begin
      v_cnt <= 1'b0;
    end
    else begin
      if (h_cnt == h_total - 1'b1) begin
        if (v_cnt == v_total - 1'b1) begin
          v_cnt <= 1'b0;
        end
        else begin
          v_cnt <= v_cnt + 1'b1;
        end
      end
    end
  end

  // 面板复位 / 背光 : 只跟 panel_rstn (真正的系统复位) 走。
  always @(posedge lcd_pclk or negedge panel_rstn) begin
    if (!panel_rstn) begin
      lcd_bl <= 1'b0;
      lcd_rstn <= 1'b0;
    end
    else begin
      lcd_bl <= 1'b1;
      lcd_rstn <= 1'b1;
    end
  end

  assign lcd_en = ((h_cnt >= h_sync + h_back) && (h_cnt < h_sync + h_back + h_disp)
          && (v_cnt >= v_sync + v_back) && (v_cnt < v_sync + v_back + v_disp))
          ? 1'b1:1'b0;

  assign data_req = ((h_cnt >= h_sync + h_back - 1'b1) && (h_cnt < h_sync + h_back + h_disp - 1'b1)
          && (v_cnt >= v_sync + v_back) && (v_cnt < v_sync + v_back + v_disp))
          ? 1'b1:1'b0;

  assign pixel_xpos = data_req ? (h_cnt - (h_sync + h_back - 1'b1)):11'b0;
  assign pixel_ypos = data_req ? (v_cnt - (v_sync + v_back - 1'b1)):11'b0;

  assign frame_start = (h_cnt == 11'd0) && (v_cnt == 11'd0);

  assign lcd_rgb = lcd_en ? pixel_data:24'b0;

endmodule
