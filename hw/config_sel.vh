//=====================================================================
//  config_sel.vh  ——  LA132 SoC 板级功能配置 (板级档位选择)
//---------------------------------------------------------------------
//  背景 :
//    实验箱只有 J7 (右侧) / J8 (左侧) 两个扩展槽, 两块扩展板的引脚
//    互斥, 不能同时启用 —— 例如 J7 的 SPI (F21/D21/G17/D19) 与 J7 的
//    电机 PWM (F21/D21) 是同一组引脚; J8 的 IIC (D14/A21/B21/A20) 与
//    点阵屏 (gpio32~39) 也是同一组引脚。
//    因此本文件把"扩展板组合"固化成三个档位, 由外部宏 BOARD1/2/3 选择,
//    同一份 RTL 源码即可生成三个互不冲突的工程。
//
//  三个档位 :
//    BOARD1  工程一 : J8左 = 8x8 LED点阵 + 4x4 矩阵键盘 (ARRAY)
//                    J7右 = 电机板, 直流电机 (PWM) + 步进电机 (gpio12~15)
//    BOARD2  工程二 : J8左 = EEPROM/RTC/QSPI Flash (IIC)
//                    J7右 = AD128/DA 板, 8路AD + 2路DA (SPI)
//    BOARD3  工程三 : J8左 = 并行高速 AD/DA 板 (ADC_9280 + DAC_9708)
//                    J7右 = 空闲
//
//  两个实验档位 (第 11 章 11.5 节的实验任务) :
//    EXP_ARRAY_SPI : J8左 = 矩阵键盘 + LED 点阵 (ARRAY)
//                    J7右 = SPI AD/DA 板 (SPI)
//                    J8 的 ARRAY 与 IIC 同脚, 因此禁用 IIC; J7 的 SPI 与
//                    电机 PWM 同脚 (F21/D21), 因此禁用 PWM/步进电机。
//                    覆盖实验 1/2/3/5/6/7/8/9 共 8 项。
//    EXP_IIC_SPI   : J8左 = RTC / EEPROM (IIC)
//                    J7右 = SPI AD/DA 板 (SPI)
//                    覆盖实验 1/4/5/8/9 —— 实验四"数码管实时时钟"需要
//                    PCF8563 对时, 必须占 J8, 与 ARRAY 互斥, 故单列。
//
//  实验模块开关 (与档位正交, 由 create_project.tcl 或手工定义) :
//    EXP_INTC16      16 路中断控制器替代原 8 路 intc_top        (实验一)
//    EXP_KBD         APB 矩阵键盘控制器 apb_kbd  (0x3005_0000)  (实验二/六)
//    EXP_DOT         APB 点阵控制器 apb_dot      (0x3007_0000)  (实验七)
//    EXP_TOUCH_MULTI GT911 多点触摸替代单点 touch_top          (实验八)
//    EXP_SPI_STREAM  流式 SPI 控制器替代原 spi_top             (实验五/九)
//
//  宏从哪里来 (两种方式, 任选其一) :
//    方式A (推荐) : 由 create_project.tcl 通过 -verilog_define 传入,
//                   例如 vivado ... -tclargs 2 D:/prj
//                   -> Tcl 执行 set_property verilog_define {BOARD2} ...
//    方式B (手工) : 在本文件开头的"手工编辑区"里把对应的 `define BOARDn
//                   取消注释 (仅用于快速实验; 缺点是三个工程共用同一配置,
//                   不便于版本管理)。
//    两个宏都没定义时按 BOARD1 处理。
//=====================================================================
//---------------------------------------------------------------------
//  手工编辑区 (仅方式B使用, 用脚本时请整节保持注释)
//      把下面某一行的注释去掉, 即在本文件内固定档位。
//      注意: 三个宏只允许出现一个, 且不要与脚本的 -tclargs 同时使用,
//            否则以本文件中地址靠前的那个为准, 容易误判工程配置。
//---------------------------------------------------------------------
//`define BOARD1
//`define BOARD2
//`define BOARD3

//  三个宏都没定义 -> 默认按工程一 (点阵/矩阵键盘 + 电机) 编译
`ifndef BOARD1
`ifndef BOARD2
`ifndef BOARD3
`ifndef EXP_ARRAY_SPI
`ifndef EXP_IIC_SPI
    `define BOARD1
`endif
`endif
`endif
`endif
`endif

//=====================================================================
//  一、公共外设 : 三个工程完全相同 (主板上焊死的外设, 与扩展槽无关)
//=====================================================================
// sys basic function
`define GPIO_PERIPHERALS      // 8位拨码开关 / 8位LED / 数码管 / 扩展槽GPIO
`define UART_PERIPHERALS      // 串口
`define INTC_PERIPHERALS      // 中断控制器
`define TIMER_PERIPHERALS     // 定时器

// LCD_PERIPHERALS 只负责在顶层声明 LCD 物理引脚, 实际时序/显存读取由
// axi_subsys 里的 axi_lcd 完成 (见 AXI_PERIPHERALS)
`define LCD_PERIPHERALS
`define TOUCH_PERIPHERALS
`define USB_PERIPHERALS
`define DMA_PERIPHERALS       // APB DMA 控制器 (dma_top)
`define RAM_PERIPHERALS       // APB DMA 示例用的片内 RAM

// ==================================================================
//  AXI 子系统 : 3 主 (CPU / AXI-DMAC / AXI-LCD) x 4 从
//    (APB-BRIDGE / AXI-DMAC / AXI-LCD / DDR3)
//  地址 : DDR3 0x4000_0000, AXI-LCD 0x2000_0000, AXI-DMAC 0x2001_0000
// ==================================================================
`define AXI_PERIPHERALS
`define DDR_PERIPHERALS

// lcd size
//`define LCD_SIZE_1 // 16'h7016 7' RGB LCD RES:1024x600
`define LCD_SIZE_2   // 16'h4384 4.3' RGB LCD RES:800x480

//=====================================================================
//  二、扩展槽档位 : 以下三组互斥, 只能命中一组
//=====================================================================
`ifdef BOARD1
//---------------------------------------------------------------------
//  工程一 : 点阵 + 矩阵键盘 (J8左) + 直流/步进电机 (J7右)
//---------------------------------------------------------------------
//  J8左 8x8 LED点阵 + 4x4 矩阵键盘 (纯 GPIO 扫描, 无专用 IP)
//    矩阵键盘 : 列 gpio8~11 (输出), 行 gpio16~19 (输入)
//    LED 点阵 : 列 gpio32~39 (输出), 行 gpio40~47 (输出)
`define ARRAY_PERIPHERALS

//  J7右 电机板: 直流电机走 PWM (pwm1/pwm2), 步进电机走 gpio12~15 四相
//  两个外设引脚不重叠, 同一块电机板上可同时启用
`define PWM_PERIPHERALS
`define Step_motor_PERIPHERALS

`elsif BOARD2
//---------------------------------------------------------------------
//  工程二 : EEPROM/RTC (J8左) + AD128/DA 板 (J7右)
//---------------------------------------------------------------------
//  J8左 IIC 模块: iic0 = EEPROM/RTC (AT24Cxx / PCF8563 类), iic1 = QSPI Flash 侧
`define IIC_PERIPHERALS

//  J7右 AD128/DA 板: 8 路 AD + 2 路 DA, SPI 接口
`define SPI_PERIPHERALS

`elsif EXP_ARRAY_SPI
//---------------------------------------------------------------------
//  实验档位一 : J8左 = 矩阵键盘 + LED 点阵 (ARRAY) + J7右 = SPI AD/DA
//  引脚互斥处理 :
//    · ARRAY 与 IIC 共用 J8, 不启用 IIC
//    · SPI 与电机 PWM 共用 F21/D21, 不启用 PWM / Step_motor
//---------------------------------------------------------------------
`define ARRAY_PERIPHERALS
`define SPI_PERIPHERALS

// 实验模块（本档位全部启用，覆盖实验 1/2/3/5/6/7/8/9）
`define EXP_INTC16
`define EXP_KBD
`define EXP_DOT
`define EXP_TOUCH_MULTI
`define EXP_SPI_STREAM

`elsif EXP_IIC_SPI
//---------------------------------------------------------------------
//  实验档位二 : J8左 = RTC/EEPROM (IIC) + J7右 = SPI AD/DA
//  引脚互斥处理 :
//    · IIC 与 ARRAY 共用 J8, 不启用 ARRAY (点阵/键盘)
//    · SPI 与电机 PWM 共用 F21/D21, 不启用 PWM / Step_motor
//---------------------------------------------------------------------
`define IIC_PERIPHERALS
`define SPI_PERIPHERALS

// 实验模块（本档位覆盖实验 1/4/5/8/9；无 ARRAY 引脚，故不含键盘/点阵）
`define EXP_INTC16
`define EXP_TOUCH_MULTI
`define EXP_SPI_STREAM

`else
//---------------------------------------------------------------------
//  工程三 : 并行高速 AD/DA 板 (J8左), J7 右空闲
//---------------------------------------------------------------------
//  同一块板上的两颗片子: AD9280 (并行 8bit ADC) + DAC9708 (并行 8bit DAC)
`define ADC_9280_PERIPHERALS
`define DAC_9708_PERIPHERALS
`endif
