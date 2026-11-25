`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: ADC_3PA1030_driver
//
// 说明 (2026-11-09 修改) —— 修"每轮头两个样本偏差大"的问题
//------------------------------------------------------------------
// 现象: 每轮采集的前 32 个字节里, 第 5、6 个(下标 4、5)总比其他值偏离大,
//       CPU 直读和 APB-DMA 完全一样 => 说明是 FIFO 里的数据本身不对,
//       与读通路无关。
// 机理: 本模块原来在 en=0 时把 SCLK 强制拉低, 即每轮之间 ADC 时钟是停的。
//       AD9280 是 3 级流水线 ADC (datasheet: Pipeline Latency = 3 Cycles),
//       时钟停掉后流水线里留着上一轮的 3 个样本; 时钟重启后:
//         第 1 个 FIFO 字节 = DATA 的残留值(上一轮最后一个样本)
//         第 2~4 个字节   = 流水线里残留的 3 个旧样本
//         第 5、6 个字节  = 时钟重启后的头 2 次真实转换 —— 采样保持/内部
//                           偏置刚从"停机"状态恢复, 还没稳, 所以偏差最大
//         第 7 个字节起   = 稳态, 正常
//       前 4 个"旧值"在直流/慢变输入下和当前值接近, 看不出来; 只有第 5、6 个
//       是肉眼可见的偏差 —— 和实测完全一致。
// 修改: 1) SCLK / cnt 改为自由运行, en=0 时也照常输出时钟, ADC 内部流水线
//          始终保持"热"的, 不再有冷启动样本;
//       2) DATA 每个转换节拍都锁存(不再只在 conv_done 时锁), 这样 FIFO 收到的
//          第一个字节就是新样本, 不会掺入上一轮的残留值;
//       3) en 只用来门控写 FIFO, 并在 en 上升后先丢掉 WARMUP 个转换再开写,
//          保证上电后第一轮也不会把上电建立过程的样本写进去。
//------------------------------------------------------------------
// 2026-11-09 二修 (上一版把采样彻底搞停了, 现象是 FIFO 一个字节都不进)
// --------------------------------------------------------------
// 根因: cnt 自由运行后, 上电时 prescale 还是 0, 而判断式是
//         cnt == prescale - 1  ==>  cnt == 32'hFFFF_FFFF
//       这个条件基本永不成立, 于是 cnt 从 0 一路加到 42 亿且**永不归零**。
//       等软件过几十毫秒才写 div=8, 此时 cnt 早已远大于 7,
//       cnt == 7 再也不可能成立 -> SCLK 不再翻转, tick 永不产生,
//       conv_done 恒 0, FIFO 永远空(CPU 直读和 DMA 都读不到东西)。
//       旧版没这问题, 因为旧版 en=0 时把 cnt 清零了。
// 修复: a) 分频值加安全下限 DIV_MIN (prescale 还是 0/1 时按 DIV_MIN 走),
//          这样 prescale-1 不会下溢;
//       b) 终点判断从 "==" 改成 ">=", 即使 cnt 已经越过终点
//          (div 由小改大以外的任何情形, 例如 div 由 8 改 4)
//          也能在当拍归零, 不会永远等下去;
//       c) 注意 tick 的取法保持"SCLK 高电平 + 终点", 所以仍然是每个
//          SCLK 周期出一个 tick, 与旧版节奏一致。
//------------------------------------------------------------------

module ADC_3PA9280_driver #(
    parameter DW     = 8,
    parameter WARMUP = 8            // en 上升后先丢弃的转换个数
)(
    input   wire                clk         ,  //100M
    input   wire                rst_n       ,
    input   wire    [31:0]      prescale    ,
    input   wire                en          ,
    input   wire    [DW-1:0]    adc_data    ,
    output  reg     [DW-1:0]    DATA        ,
    output  reg                 SCLK_3PA1030,
    output  wire                conv_done
    );

    localparam [3:0] WARMUP_LAST = WARMUP - 1;
    localparam [31:0] DIV_MIN    = 32'd4;   // prescale 未配置时的安全下限

    reg [31:0] cnt;
    reg [3:0]  warm;
    reg        armed;

    // 有效分频值: prescale 还是 0/1 时按 DIV_MIN 走, 防止 prescale-1 下溢
    wire [31:0] div = (prescale < DIV_MIN) ? DIV_MIN : prescale;

    // 终点判断用 >=: cnt 越过终点时当拍归零, 不会永远等下去
    wire div_end = (cnt >= (div - 32'd1));

    // 转换节拍: SCLK 高电平结束处(与原来 conv_done 的触发点一致)
    wire tick = SCLK_3PA1030 && div_end;

    // 写 FIFO 使能: 只在 en 有效且预热完成后才写
    assign conv_done = en && armed && tick;

    // 数据锁存: 每个转换节拍都更新(与 en 无关), FIFO 里第一个字节即为新样本
    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)
            DATA <= {DW{1'b0}};
        else if(tick)
            DATA <= adc_data;
    end

    // 分频计数: 自由运行
    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)
            cnt <= 32'd0;
        else if(div_end)
            cnt <= 32'd0;
        else
            cnt <= cnt + 32'd1;
    end

    // ADC 时钟: 自由运行 (en=0 时也不再停, 避免流水线冷启动)
    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)
            SCLK_3PA1030 <= 1'b0;
        else if(div_end)
            SCLK_3PA1030 <= ~SCLK_3PA1030;
    end

    // 预热计数: en 上升后丢掉 WARMUP 个转换, 之后才允许写 FIFO
    always@(posedge clk or negedge rst_n)begin
        if(!rst_n) begin
            warm  <= 4'd0;
            armed <= 1'b0;
        end else if(!en) begin
            warm  <= 4'd0;
            armed <= 1'b0;
        end else if(tick && !armed) begin
            if(warm == WARMUP_LAST)
                armed <= 1'b1;
            else
                warm <= warm + 4'd1;
        end
    end

endmodule
