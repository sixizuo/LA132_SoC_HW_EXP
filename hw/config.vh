`timescale 1ns/1ps

`define FPGA

/*****************
*   AXI interface
******************/

/**************************************************
* 3 主 x 4 从 AXI 互联矩阵 (amba/axi_interconnect.v) 地址窗口
*   命中条件   : (addr & MASK) == BASE
*   ------------------------------------------------------------------
*   三个从设备窗口互不重叠, 译码顺序不影响功能 (下表按地址由低到高排列):
*       0x2000_0000 ~ 0x2000_FFFF   AXI-LCD     64KB   (mask 0xFFFF_0000)
*       0x2001_0000 ~ 0x2001_FFFF   AXI-DMAC    64KB   (mask 0xFFFF_0000)
*       0x4000_0000 ~ 0x7FFF_FFFF   DDR3        1GB    (mask 0xC000_0000)
*       其余地址                    S0 APB-BRIDGE -> 32 个 APB 外设
*       (APB 段 0x3000_0000 ~ 0x3010_FFFF + 0x3200_0000 + 0x3300_0000)
*   ------------------------------------------------------------------
*   !! 地址编排的两条硬约束 (改地址前必读) !!
*   1) 所有窗口必须落在 CPU 的"直连区" 0x0000_0000 ~ 0x7FFF_FFFF。
*      start.S 里 SEGPA = 0x76503210, 把 4 个 VSEG 窗口按 identity 映射到
*      PSEG:  0x8xxx -> 0x0xxx,  0xAxxx -> 0x2xxx,
*             0xCxxx -> 0x4xxx,  0xExxx -> 0x6xxx。
*      也就是说 CPU 写 0x9100_0000, AXI 上出现的是 0x1100_0000; 写在
*      0x8xxx ~ 0xFFFF_FFFF 的地址永远和这里填的 BASE 对不上。
*      (0x8000_0000 只是片内 BRAM 的窗口别名, 由核内 dbus0 窗口直接吃掉)
*   2) AXI 外设窗口不能被 DDR 的 mask 覆盖。
*      1GB 窗口的 mask 是 0xC000_0000 (0x4000_0000 ~ 0x7FFF_FFFF);
*      APB 段必须挑 DDR 之外的空洞, 当前用 0x3000_0000 段 —— 它同时落在
*      AXI-LCD/DMAC (0x2000 段) 之后、DDR (0x4000 段) 之前, 且是直连区。
*   ------------------------------------------------------------------
*   注意: 本板 DDR3 颗粒为 2 x MT41K256M16 (32 bit DQ / 15 row / 10 col /
*         8 bank) = 1GB; MIG IP (ip/mig_7series_0) 已按 DataWidth=32 /
*         C0_S_AXI_ADDR_WIDTH=30 重新生成, 与 0x4000_0000~0x7FFF_FFFF 一致。
*         若日后把 MIG 改回 16bit/29bit, 必须同步把窗口改回 512MB
*         (mask 0xE000_0000) 并同步 axi_ddr_slave 的 MIG_ADDR_WIDTH。
*   ------------------------------------------------------------------
**************************************************/
// S3 DDR3 (peripheral/axi_ddr/axi_ddr_slave.v -> MIG -> DDR3 颗粒)
//   1 GB, 兼作 LCD 显存 (一帧 800x480x4B = 0x17_7000)
//   送 MIG 前按 MIG_ADDR_WIDTH 截断 = 自动减基址, 因此 BASE 必须按窗口对齐
`define AXI_SLV_DDR_ADDR_BASE    32'h40000000
`define AXI_SLV_DDR_ADDR_MASK    32'hC0000000

// S2 LCD  (peripheral/axi_lcd/axi_lcd.v 配置寄存器), 64 KB
`define AXI_SLV_LCD_ADDR_BASE    32'h20000000
`define AXI_SLV_LCD_ADDR_MASK    32'hFFFF0000

// S1 DMAC (peripheral/axi_dma/axi_dma.v 配置寄存器), 64 KB
//   紧跟 LCD 窗口之后
`define AXI_SLV_DMA_ADDR_BASE    32'h20010000
`define AXI_SLV_DMA_ADDR_MASK    32'hFFFF0000

`define LAWADDR 32 
`define LAWLEN 4
`define LAWSIZE 3
`define LAWBURST 2
`define LAWLOCK 2
`define LAWCACHE 4
`define LAWPROT 3
`define LWDATA 32
`define LWSTRB 4
`define LWLAST 1
`define LBRESP 2
`define LARADDR 32
`define LARLEN 4
`define LARSIZE 3
`define LARBURST 2
`define LARLOCK 2
`define LARCACHE 4
`define LARPROT 3
`define LRDATA 32
`define LRRESP 2
`define LRLAST 1
`define LID 4


/*****************
*   APB interface 16-way APB
******************/

`define ADDR_APB 32
`define DATA_APB 32


// gpio
`define GPIOA_OE       8'h40
`define GPIOA_O        8'h44
`define GPIOA_I        8'h48
`define GPIOB_OE       8'h50
`define GPIOB_O        8'h54
`define GPIOB_I        8'h58

`define EXINT_EN       8'h20
`define EXINT_POL      8'h24
`define EXINT_EDGE     8'h28
`define EXINT_OUT_CLR  8'h2c
`define EXINT_TWO_EDGE 8'h30

// uart
`define UART_DATA 8'h0
`define UART_CTRL 8'h4
`define UART_STAT 8'h8    // 2026-11-02: 只读, [4:0] = RX FIFO 当前字节个数

// intc
`define INT_EN   8'h0
`define INT_POL  8'h4
`define INT_EDGE 8'h8
`define INT_CLR  8'hc
`define INT_SET  8'h10
`define INT_OUT  8'h14


// timer
`define TIMER_CFG 8'h0
`define TIMER_CNT 8'h4
`define TIMER_CMP 8'h8
`define TIMER_STP 8'hc

// iic
`define IIC_PRERL   8'h00
`define IIC_PRERH   8'h04
`define IIC_CTR     8'h08
`define IIC_DR      8'h0C
`define IIC_CR_SR   8'h10
`define IIC_BLK_TOP 8'h14
`define IIC_SEL     8'h20 

// usb
`define USB_DATA 8'h0
`define USB_CTRL 8'h4

// lcd
`define LCD_CTRL   24'h0
`define LCD_BUFFER 24'h4

// touch
`define TOUCH_CTRL     8'h0
`define TOUCH_INTERVAL 8'h4
`define TOUCH_DATA     8'h8

// audio
`define AUDIO_CTRL   16'h0
`define AUDIO_BUFFER 16'h4

// eth
`define ETH_DATA   8'h00
`define ETH_STATUS 8'h04
`define ETH_MACH   8'h08
`define ETH_MACL   8'h0C
`define ETH_IP     8'h10
`define ETH_BYTE   8'h14

// pwm
`define PWM_DIV_FREQ 8'h0
`define PWM_COMP     8'h4
`define PWM_STATE    8'h8

// spi
`define SPI_SPCR   8'h0
`define SPI_SPSR   8'h4
`define SPI_DATA   8'h8
`define SPI_SPER   8'hc
`define SPI_SOFTCS 8'h14
`define SPI_MUL    8'h18

//ADC_9280
`define ADC_DIV_FREQ 8'h0
`define ADC_CSR 8'h4
`define ADC_DATA 8'h8
//DAC_9708
`define DAC_DIV_FREQ 16'h0
`define DAC_EN 16'h4
`define DAC_FWORD 16'h8
`define DAC_PWORD 16'hc
`define DAC_AWORD 16'h10
`define DAC_DATA 16'b1xxx_xxxx_xxxx_xxxx