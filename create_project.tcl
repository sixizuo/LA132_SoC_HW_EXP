#=====================================================================
#  create_project.tcl  ——  LA132_SoC_HW 参数化建工程脚本
#---------------------------------------------------------------------
#  一句话 :
#     同一个脚本 + 一个档位参数 = 三个互不冲突的 Vivado 工程,
#     三个档位对应实验箱 J7/J8 三种扩展板组合, 不必再手改 RTL。
#
#  用法一 (批处理, 推荐) :
#     vivado.bat -mode batch -source create_project.tcl -tclargs <档位> <保存目录> [工程名] [是否综合]
#
#     例 1  只建工程 (不综合):
#        C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch \
#            -source create_project.tcl -tclargs 1 D:/xilinx_project/2025_2
#     例 2  建工程 + 综合 + 实现 + bit:
#        ... -tclargs 2 D:/xilinx_project/2025_2 LA132_B2 1
#
#  用法二 (GUI) :
#     改下面 §1 的 BOARD_ARG / OUT_DIR 两个变量, 然后
#         cd {"create_project.tcl脚本所在路径"}
#         source ./create_project.tcl
#
#  档位 (= 参数1, 大小写不限) :
#     1 | b1 | matrix | matrix_motor | array
#           工程一 : J8左 = 8x8 LED点阵 + 4x4 矩阵键盘
#                    J7右 = 电机板 (直流机 PWM + 步进机 gpio12~15)
#     2 | b2 | rtc | rtc_spi | iic_spi | spi
#           工程二 : J8左 = EEPROM / RTC / QSPI Flash (IIC)
#                    J7右 = AD128/DA 板 (SPI, 8路AD + 2路DA)
#     3 | b3 | padc | pardac | adc_dac | parallel
#           工程三 : J8左 = 并行高速 AD/DA 板 (AD9280 + DAC9708)
#                    J7右 = 空闲
#
#  参数2 保存目录 : 工程建在 <保存目录>/<工程名>/<工程名>.xpr
#  参数3 工程名   : 省略 -> LA132_SoC_B1_MatrixMotor / _B2_RtcSpi / _B3_ParAdcDac
#  参数4 是否综合 : 1 = 综合 + 实现 + 生成 bit (耗时长); 0 或省略 = 只建工程
#
#  目录约定 (RTL / 约束 / IP 全在 hw 下):
#    hw/*.v  *.sv  *.vh *.svh   顶层 / CPU / 板级配置宏 / APB 地址表
#    hw/amba/                   APB/AXI 桥、仲裁、互联、CDC
#    hw/LA132/                  LA132 核 (la132_top.v 空壳 + la132_top.edf 网表)
#    hw/peripheral/             全部 APB 外设 + axi_ddr / axi_dma / axi_lcd
#    hw/constraints/*.xdc       引脚/时序约束 (按档位自动挑选, 见 §5)
#    hw/ip/<ip>/<ip>.xci        8 个 Xilinx IP + MIG (mig_7series_0)
#    hw/coe/                    IP 初始化系数文件
#
#  器件 : xc7a100tlfgg484-2L  (LA132 实验箱核心板)
#  工具 : Vivado 2025.2 实测通过 (安装路径 C:/AMDDesignTools/2025.2/Vivado)
#=====================================================================

#---------------------------------------------------------------------
#  1. 默认参数 (GUI 方式直接改这两个变量; 批处理方式由 -tclargs 覆盖)
#---------------------------------------------------------------------
set DEFAULT_BOARD      1     ;# 默认档位: 1/2/3
set BOARD_ARG          ""    ;# 空 = 用 DEFAULT_BOARD
set OUT_DIR            ""    ;# 空 = 下面 DEFAULT_OUT_DIR; 否则 = 用户指定保存目录
set DEFAULT_OUT_DIR    "D:/xilinx_project/2025_2"
set PROJ_NAME_ARG      ""    ;# 空 = 按档位自动命名
set RUN_IMPL_ARG       ""    ;# 空 = 用 DEFAULT_RUN_IMPL
set DEFAULT_RUN_IMPL   0     ;# 1 = 建完工程后自动综合+实现+bit

set PART        "xc7a100tlfgg484-2L"
set RESET_IP    1   ;# 1 = 先 reset_target all 再重新生成全部 IP (IP 出问题时用)
set AUTO_INCR   0   ;# 1 = 允许 Vivado 自动增量综合 (默认关, 保证结果可重现)
set HOLD_FIX2   1   ;# 1 = 布线后再做一次 phys_opt 修残余 hold (默认开, 见 §11 说明)
set JOBS        6   ;# 并行任务数

#---------------------------------------------------------------------
#  2. 档位表: 档位 -> 工程名后缀 / BOARD 宏 / 扩展板引脚约束 / 说明
#---------------------------------------------------------------------
proc normalize_board {s} {
    switch -- [string tolower [string trim $s]] {
        1 - b1 - board1 - matrix - matrix_motor - array - key_led  { return 1 }
        2 - b2 - board2 - rtc - rtc_spi - iic_spi - spi - ad128    { return 2 }
        3 - b3 - board3 - padc - pardac - adc_dac - parallel       { return 3 }
        4 - exp4 - exp_array_spi - array_spi - exp_array           { return 4 }
        5 - exp5 - exp_iic_spi  - rtc_spi_exp - exp_iic            { return 5 }
        default                                                    { return "" }
    }
}

proc board_suffix {b} {
    switch -- $b {
        1 { return "B1_MatrixMotor" }
        2 { return "B2_RtcSpi"      }
        3 { return "B3_ParAdcDac"   }
        4 { return "EXP_ArraySpi"   }
        5 { return "EXP_IicSpi"     }
    }
    return "B?"
}

proc board_define {b} {
    switch -- $b {
        4 { return "EXP_ARRAY_SPI" }
        5 { return "EXP_IIC_SPI"   }
    }
    return "BOARD${b}"
}

# 各档位额外的引脚约束文件 (公共约束见 §5 的 XDC_COMMON)
proc board_xdc {b} {
    switch -- $b {
        1 { return [list matrix_key_led.xdc Motor.xdc]          }
        2 { return [list IIC_RTC_EEPROM.xdc spi_adc_dac.xdc]    }
        3 { return [list parallel_DAC_ADC.xdc]                  }
        4 { return [list matrix_key_led.xdc spi_adc_dac.xdc]    }
        5 { return [list IIC_RTC_EEPROM.xdc spi_adc_dac.xdc]    }
    }
    return {}
}

proc board_desc {b} {
    switch -- $b {
        1 { return "J8左: 8x8点阵 + 4x4矩阵键盘   |  J7右: 直流电机(PWM) + 步进电机(gpio12~15)" }
        2 { return "J8左: EEPROM/RTC/QSPI (IIC)   |  J7右: AD128/DA 板 (SPI, 8AD + 2DA)"        }
        3 { return "J8左: 并行高速 AD/DA (AD9280 + DAC9708)   |  J7右: 空闲"                    }
        4 { return "J8左: 矩阵键盘 + LED 点阵 (ARRAY)   |  J7右: SPI AD/DA 板   实验 1/2/3/5/6/7/8/9" }
        5 { return "J8左: RTC/EEPROM (IIC)   |  J7右: SPI AD/DA 板   实验 1/4/5/8/9" }
    }
    return ""
}

# 该档位启用的 APB 外设 (仅用于打印清单, 与 RTL 里的 `ifdef 对应)
proc board_modules {b} {
    switch -- $b {
        1 { return [list ARRAY_PERIPHERALS PWM_PERIPHERALS Step_motor_PERIPHERALS] }
        2 { return [list IIC_PERIPHERALS SPI_PERIPHERALS]                          }
        3 { return [list ADC_9280_PERIPHERALS DAC_9708_PERIPHERALS]                }
        4 { return [list ARRAY_PERIPHERALS SPI_PERIPHERALS \
                      EXP_INTC16 EXP_KBD EXP_DOT EXP_TOUCH_MULTI EXP_SPI_STREAM]   }
        5 { return [list IIC_PERIPHERALS SPI_PERIPHERALS \
                      EXP_INTC16 EXP_TOUCH_MULTI EXP_SPI_STREAM]                   }
    }
    return {}
}

# 该档位占用的扩展槽引脚 (打印用, 与 hw/constraints 里的分配一致)
proc board_pins {b} {
    switch -- $b {
        1 { return [list \
            "矩阵键盘 COL  gpio8~11   (A16 A15 A14 A13)" \
            "矩阵键盘 ROW  gpio16~19  (B17 C14 B13 C13)" \
            "LED点阵  COL  gpio32~39  (C20 B21 A20 F13 A19 C19 C22 C18)" \
            "LED点阵  ROW  gpio40~47  (B16 B22 B18 D20 D14 A18 A21 B20)" \
            "直流电机 PWM  pwm1/pwm2  (F21 D21)" \
            "步进电机      gpio12~15  (G17 D19 G18 G22)"] }
        2 { return [list \
            {IIC0 SCL/SDA  iic0_scl / iic0_sda   (D14 A21)   EEPROM / RTC} \
            {IIC1 SCL/SDA  iic1_scl / iic1_sda   (B21 A20)   QSPI Flash 侧} \
            {SPI  CSN0/1   spi_csn[0] / [1]      (D22 E19)} \
            {SPI  CLK0/1   spi_clk[0] / [1]      (E22 G17)} \
            {SPI  MOSI0/1  spi_mosi[0] / [1]     (D21 D19)} \
            {SPI  MISO0    spi_miso[0]           (F21)}] }
        3 { return [list \
            {DAC  DATA0~7  dac_data[7:0]  (C19 A16 F13 C15 B16 B18 B15 A18)} \
            {DAC  CLK      dac_clk        (B17)} \
            {ADC  DATA0~7  adc_data[7:0]  (A20 D20 B21 C20 B22 A21 C22 D14)} \
            {ADC  CLK      adc_clk        (C18)} \
            {ADC  OTR      adc_otr        (B20)}] }
        4 { return [list \
            "矩阵键盘 ROW  gpio16~19  (B17 C14 B13 C13)   由 apb_kbd 驱动 (低有效)" \
            "矩阵键盘 COL  gpio8~11   (A16 A15 A14 A13)   由 apb_kbd 采样 (板上上拉)" \
            "LED点阵  COL  gpio32~39  (C20 B21 A20 F13 A19 C19 C22 C18)  由 apb_dot 驱动" \
            "LED点阵  ROW  gpio40~47  (B16 B22 B18 D20 D14 A18 A21 B20)  由 apb_dot 驱动" \
            "SPI  CSN0/1   spi_csn[0] / [1]      (D22 E19)" \
            "SPI  CLK0/1   spi_clk[0] / [1]      (E22 G17)" \
            "SPI  MOSI0/1  spi_mosi[0] / [1]     (D21 D19)" \
            "SPI  MISO0    spi_miso[0]           (F21)" \
            "WARNING: Motor.xdc 未启用 (F21/D21/G17/D19 与 SPI 冲突)"] }
        5 { return [list \
            {IIC0 SCL/SDA  iic0_scl / iic0_sda   (D14 A21)   PCF8563 / AT24Cxx} \
            {IIC1 SCL/SDA  iic1_scl / iic1_sda   (B21 A20)   QSPI Flash 侧} \
            {SPI  CSN0/1   spi_csn[0] / [1]      (D22 E19)} \
            {SPI  CLK0/1   spi_clk[0] / [1]      (E22 G17)} \
            {SPI  MOSI0/1  spi_mosi[0] / [1]     (D21 D19)} \
            {SPI  MISO0    spi_miso[0]           (F21)} \
            "WARNING: matrix_key_led.xdc 未启用 (J8 与 IIC 冲突)" \
            "WARNING: Motor.xdc 未启用 (F21/D21/G17/D19 与 SPI 冲突)"] }
    }
    return {}
}

#---------------------------------------------------------------------
#  3. 解析参数
#---------------------------------------------------------------------
#   只有在 -tclargs 里给了合法档位时才覆盖默认值。
#   (GUI 里 source 本脚本时 argv 里是 vivado 自己的参数, 必须忽略)
if {[info exists argv]} { set _argv $argv } else { set _argv {} }
set _use_argv 0
if {[llength $_argv] >= 1} {
    if {[normalize_board [lindex $_argv 0]] ne ""} { set _use_argv 1 }
}

set BOARD $DEFAULT_BOARD
if {$BOARD_ARG ne ""} {
    set _nb [normalize_board $BOARD_ARG]
    if {$_nb eq ""} { error "BOARD_ARG 非法: '$BOARD_ARG' (应为 1/2/3)" }
    set BOARD $_nb
}
if {$_use_argv} {
    set BOARD [normalize_board [lindex $_argv 0]]
    if {[llength $_argv] >= 2} { set OUT_DIR        [string trim [lindex $_argv 1]] }
    if {[llength $_argv] >= 3} { set PROJ_NAME_ARG  [string trim [lindex $_argv 2]] }
    if {[llength $_argv] >= 4} { set RUN_IMPL_ARG   [string trim [lindex $_argv 3]] }
} elseif {[llength $_argv] >= 1} {
    puts "NOTE: 忽略命令行参数 '$argv' (不是合法档位, 按默认档位 $DEFAULT_BOARD 处理)"
}

if {$OUT_DIR eq ""} { set OUT_DIR $DEFAULT_OUT_DIR }

set PROJ_NAME [expr {$PROJ_NAME_ARG ne "" ? $PROJ_NAME_ARG : "LA132_SoC_[board_suffix $BOARD]"}]
set RUN_IMPL  $DEFAULT_RUN_IMPL
if {$RUN_IMPL_ARG ne ""} {
    if {![string is integer -strict $RUN_IMPL_ARG]} {
        error "参数4 (是否综合) 必须是 0 或 1, 收到 '$RUN_IMPL_ARG'"
    }
    set RUN_IMPL [expr {$RUN_IMPL_ARG ? 1 : 0}]
}

#---------------------------------------------------------------------
#  4. 定位目录
#---------------------------------------------------------------------
set SCRIPT_DIR  [file normalize [file dirname [info script]]]
set HW_DIR      [file normalize [file join $SCRIPT_DIR hw]]
set OUT_DIR     [file normalize $OUT_DIR]
set PROJ_PATH   [file normalize [file join $OUT_DIR $PROJ_NAME]]

if {![file isdirectory $HW_DIR]} {
    error "找不到 hw 目录: $HW_DIR  (请把脚本放在 LA132_SoC_HW 目录下)"
}
if {![file isdirectory $OUT_DIR]} {
    file mkdir $OUT_DIR
    puts "已创建保存目录 : $OUT_DIR"
}

puts "====================================================================="
puts " LA132_SoC_HW  Vivado 工程创建脚本"
puts "   档位 BOARDn : $BOARD  ([board_define $BOARD])"
puts "   扩展板配置  : [board_desc $BOARD]"
puts "   script dir  : $SCRIPT_DIR"
puts "   hw  dir     : $HW_DIR"
puts "   保存目录    : $OUT_DIR"
puts "   工程名      : $PROJ_NAME"
puts "   工程路径    : $PROJ_PATH"
puts "   器件        : $PART"
puts "   建完是否综合: [expr {$RUN_IMPL ? "是 (含 bit)" : "否"}]"
puts "====================================================================="

#---------------------------------------------------------------------
#  5. 创建工程 + 传入板级宏 BOARDn
#---------------------------------------------------------------------
# 若目标工程正好是当前已打开的工程, 先关掉 (否则 create_project -force 会报
# "project already open")
catch {
    set _ps [get_projects -quiet]
    if {[llength $_ps] > 0} {
        set _pd [file normalize [get_property DIRECTORY [lindex $_ps 0]]]
        if {$_pd eq [file normalize $PROJ_PATH]} { close_project }
    }
}

create_project $PROJ_NAME $PROJ_PATH -part $PART -force
if {[llength [get_projects -quiet $PROJ_NAME]] > 0} {
    current_project $PROJ_NAME
}

set_property simulator_language Mixed        [current_project]
set_property target_language    Verilog      [current_project]
set_property default_lib        xil_defaultlib [current_project]

# ---------------------------------------------------------------
#  !! 关键一步 !! 板级档位就是靠这个宏传进 config_sel.vh 的。
#  写进 sources_1 的 verilog_define, 综合/仿真都会带上;
#  不要在 RTL 里硬编码 `define BOARDn。
# ---------------------------------------------------------------
set_property verilog_define [list [board_define $BOARD]] [get_filesets sources_1]
puts "\[0/8\] 板级宏         : [board_define $BOARD]  (config_sel.vh 据此选择扩展外设)"

#---------------------------------------------------------------------
#  6. 加入 RTL 源文件
#---------------------------------------------------------------------
# 6.1 收集目录: 顶层 / amba / LA132 / (可选 new) / peripheral 的每个子目录
set rtl_dirs [list $HW_DIR $HW_DIR/amba $HW_DIR/LA132]
foreach extra {new} {
    if {[file isdirectory [file join $HW_DIR $extra]]} {
        lappend rtl_dirs [file normalize [file join $HW_DIR $extra]]
    }
}
foreach sub [glob -nocomplain -directory $HW_DIR/peripheral -type d *] {
    lappend rtl_dirs [file normalize $sub]
}

set n_rtl 0
foreach d $rtl_dirs {
    set fs [concat \
        [glob -nocomplain -directory $d -type f *.v] \
        [glob -nocomplain -directory $d -type f *.sv]]
    # 去掉 testbench: exp_* 目录里 tb_*.v 与 RTL 放在一起, 它们没有端口,
    # 加进 sources_1 只会让综合多打一堆 "unused module" 警告。
    # (仿真请走 tools/run_xsim_exp.sh 或各自的 iverilog 命令)
    set fs_keep {}
    foreach f $fs {
        if {[string match "tb_*" [file tail $f]]} { continue }
        lappend fs_keep $f
    }
    set fs $fs_keep
    if {[llength $fs] > 0} {
        # 注意: 一律用 [list ...] 传文件参数。工作区路径可能含空格
        # (…/03 教材建设/…), Vivado 会把未加引号的路径按空格拆开,
        # 报 "File or Directory 'D:/06_xxx/03' does not exist"。
        add_files -norecurse -fileset sources_1 [list {*}$fs]
        incr n_rtl [llength $fs]
    }
}
puts "\[1/8\] RTL 源文件      : $n_rtl 个 .v/.sv"

# 6.2 LA132 的 EDIF 网表 (la132_top.v 只是供 lint 用的空壳, 二者同名不同层次)
set edf [glob -nocomplain -directory $HW_DIR/LA132 -type f *.edf]
if {[llength $edf] > 0} {
    add_files -norecurse -fileset sources_1 [list [lindex $edf 0]]
    puts "\[2/8\] EDIF 网表       : [file tail [lindex $edf 0]]"
} else {
    puts "\[2/8\] EDIF 网表       : 未找到 (*.edf), LA132 核将不可用!"
}

# 6.3 头文件 (config.vh / config_sel.vh / apb_addr.svh)
set hdrs [concat \
    [glob -nocomplain -directory $HW_DIR -type f *.vh] \
    [glob -nocomplain -directory $HW_DIR -type f *.svh]]
if {[llength $hdrs] > 0} {
    add_files -norecurse -fileset sources_1 [list {*}$hdrs]
}
puts "\[3/8\] 头文件         : [llength $hdrs] 个"

# 6.4 `include 搜索路径
#     apb_bridge.sv 里写的是 `include "../apb_addr.svh"
#     其余文件写的是 `include "config.vh" / "apb_addr.svh"
set_property include_dirs [list $HW_DIR $HW_DIR/amba $HW_DIR/peripheral] [current_fileset]

#---------------------------------------------------------------------
#  7. 加入约束 : 公共约束 + 本档位扩展板约束
#---------------------------------------------------------------------
set XDC_COMMON {la132.xdc ddr.xdc gpio.xdc uart.xdc INTC.xdc usb.xdc lcd_touch.xdc}
set xdc_names  [concat $XDC_COMMON [board_xdc $BOARD]]

set xdcs [list]
foreach n $xdc_names {
    set f [file join $HW_DIR/constraints $n]
    if {[file exists $f]} {
        lappend xdcs $f
    } else {
        puts "        !! 缺少约束文件: $n (该组端口将不受引脚约束, 请检查 hw/constraints)"
    }
}
if {[llength $xdcs] > 0} {
    add_files -fileset constrs_1 [list {*}$xdcs]
}
set xdc_target [glob -nocomplain -directory $HW_DIR/constraints -type f la132.xdc]
if {[llength $xdc_target] > 0} {
    set_property target_constrs_file [lindex $xdc_target 0] [current_fileset -constrset]
}
puts "\[4/8\] 约束文件       : [llength $xdcs] 个 -> [join [lmap f $xdcs {file tail $f}] {, }]"

# 打印被排除的约束文件, 便于核对"只加了本档位需要的约束"
set xdc_other [list]
foreach b {1 2 3 4 5} {
    if {$b == $BOARD} { continue }
    foreach n [board_xdc $b] { lappend xdc_other $n }
}
if {[llength $xdc_other] > 0} {
    puts "        已排除(属其它档位): [join $xdc_other {, }]"
}

#---------------------------------------------------------------------
#  8. 加入 IP (含 MIG), 并生成
#---------------------------------------------------------------------
#  !! 必须用 import_ip 把 IP 复制进工程, 不能用 add_files !!
#---------------------------------------------------------------------
#  预检: IP 依赖的初始化系数文件是否齐全。
#  缺 coe 时 import_ip 只报 WARNING 并把 IP 恢复成"上一版合法配置",
#  直到 generate_target 才报 "Failed to customize IP", 报错位置离根因很远。
foreach c {apb_write.coe sine_32768.coe} {
    if {![file exists [file join $HW_DIR/coe $c]]} {
        error "hw/coe/$c 缺失 —— blk_mem_gen_0 / DDS_BRAM 的初始化文件不全, IP 生成必然失败"
    }
}
set ip_xcis [list]
set ip_seen [list]
foreach d [glob -nocomplain -directory $HW_DIR/ip -type d *] {
    set xs [glob -nocomplain -directory $d -type f *.xci]
    if {[llength $xs] == 0} {
        # 少数 IP 多套了一层同名目录 (例: ip/DDS_BRAM/DDS_BRAM/DDS_BRAM.xci)
        set xs [glob -nocomplain -directory $d -type f */*.xci]
    }
    foreach x $xs {
        set x [file normalize $x]
        set bn [file rootname [file tail $x]]
        if {[lsearch -exact $ip_seen $bn] >= 0} {
            puts "        !! 跳过重名 IP: $x"
            continue
        }
        lappend ip_seen $bn
        lappend ip_xcis $x
    }
}
puts "\[5/8\] IP (.xci)       : [llength $ip_xcis] 个"

set ip_names [list]
foreach xci $ip_xcis {
    set ipname [file rootname [file tail $xci]]
    lappend ip_names $ipname
    # 必须写成 import_ip -name <name> [list <xci>]:
    #   1) import_ip 没有 -files 选项, 文件是位置参数;
    #   2) 路径含空格, 不加 [list ...] 会被 Vivado 按空格拆成 2 个文件参数,
    #      报 "Can only specify '-name' with a single file argument"。
    if {[catch {import_ip -name $ipname [list $xci]} ierr]} {
        if {[llength [get_ips -quiet $ipname]] > 0} {
            # IP 对象已建好, 只是某个参数校验失败 (常见: .coe 路径失效),
            # 后面 fix_ip_coe 会修; 此时再 add_files 只会报 "name already in use"
            puts "        !! import_ip $ipname 参数校验告警 (IP 已存在, 继续): $ierr"
        } else {
            puts "        !! import_ip $ipname 失败, 退回就地引用: $ierr"
            add_files -norecurse -fileset sources_1 [list $xci]
        }
    }
}
puts "        已导入工程       : [join $ip_names {, }]"

# ---- IP 需要的系数文件也复制到工程目录 (ASCII 路径) ----------------
set coe_dir [file normalize [file join $PROJ_PATH coe]]
file mkdir $coe_dir
set n_coe 0
foreach c [glob -nocomplain -directory $HW_DIR/coe -type f *.coe] {
    file copy -force $c [file join $coe_dir [file tail $c]]
    incr n_coe
}
puts "        系数文件         : $n_coe 个 -> $coe_dir"

if {[llength $ip_xcis] > 0} {
    # 换器件 (LA132_YUNXIAO 的 -1 -> 本工程的 -2L) 后 IP 会被 Vivado 标成
    # "locked: part mismatch", 先升级一次; 失败也不致命, generate_target 会处理
    if {[catch {upgrade_ip [get_ips]} uerr]} {
        puts "        upgrade_ip : $uerr"
    } else {
        puts "        upgrade_ip : OK"
    }

    # 系数文件路径: import 之后原来的相对路径 ../../coe/xxx.coe 已失效,
    # 必须重新指向工程目录里的那份
    proc fix_ip_coe {ipname confname coefile} {
        if {[llength [get_ips -quiet $ipname]] == 0} { return }
        if {[catch {set_property -dict [list CONFIG.$confname $coefile] [get_ips $ipname]} e]} {
            puts "        !! 设置 $ipname 的 $confname 失败: $e"
        } else {
            puts "        $ipname : $confname = [file tail $coefile]"
        }
    }
    fix_ip_coe DDS_RAM       coefficient_file [file join $coe_dir sine_32768.coe]
    # 片内 128K flash (blk_mem_gen_0) 的上电初值 = LA132 启动程序镜像
    # xci 里写的是相对路径 ../../coe/apb_write.coe, 导入工程后必然失效
    fix_ip_coe blk_mem_gen_0 Coe_File         [file join $coe_dir apb_write.coe]
    # 现在的 IP 名是 DDS_BRAM (blk_mem_gen), 系数参数名为 Coe_File;
    # xci 里写的是相对路径 ../../../coe/sine_32768.coe, 导入工程后必然失效
    fix_ip_coe DDS_BRAM      Coe_File         [file join $coe_dir sine_32768.coe]

    if {$RESET_IP} {
        puts "        RESET_IP=1 -> reset_target all \[get_ips\]"
        reset_target all [get_ips]
    }

    # 生成全部 IP 目标 (MIG 的生成要跑 1~3 分钟, 请耐心等待)
    puts "        generate_target all ..."
    generate_target all [get_ips]
    catch {report_ip_status -file [file join $PROJ_PATH ip_status.rpt]}
    puts "        IP 生成完成, 状态见 $PROJ_PATH/ip_status.rpt"
}

#---------------------------------------------------------------------
#  9. 顶层设置
#---------------------------------------------------------------------
set_property top     godson_mcu_top  [current_fileset]
set_property top_lib xil_defaultlib  [current_fileset]
update_compile_order -fileset sources_1
puts "\[6/8\] 顶层           : [get_property top [current_fileset]]"

#---------------------------------------------------------------------
#  10. 自动增量综合开关
#      Vivado 2024.2+ 默认会尝试 auto incremental compile: 若上次的
#      godson_mcu_top.dcp 还在, 就把它当参考只重综合改动的部分。
#      但参考里的 xdc/RTL 与当前不一致时会带来隐患, 为了结果可重现,
#      这里默认显式关闭 (AUTO_INCR=0)。
#---------------------------------------------------------------------
puts "\[7/8\] 自动增量综合 : [expr {$AUTO_INCR ? "允许 (AUTO_INCR=1)" : "关闭 (AUTO_INCR=0)"}]"
foreach rn {synth_1 impl_1} {
    if {[llength [get_runs -quiet $rn]] > 0} {
        if {$AUTO_INCR} {
            set_property AUTO_INCREMENTAL_CHECKPOINT 1 [get_runs $rn]
        } else {
            set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs $rn]
        }
    }
}

#---------------------------------------------------------------------
#  11. 可选: 综合 + 实现 + bit
#---------------------------------------------------------------------
set BIT_FILE [file join $PROJ_PATH ${PROJ_NAME}.runs impl_1 godson_mcu_top.bit]

if {$RUN_IMPL} {
    puts "\[8/8\] 开始综合 (synth_1, jobs=$JOBS) ..."
    reset_run synth_1
    launch_runs synth_1 -jobs $JOBS
    wait_on_run synth_1

    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
        puts "!! 综合未完成, 请查看 synth_1 日志"
    } else {
        #---------------------------------------------------------------
        #  修 hold (实测必需, 不要删) —— 分两级
        #---------------------------------------------------------------
        #  现象: 32MHz 域 (clk_out1_clk_wiz_0) 上有几十个 hold 违例,
        #  最差 WHS = -0.295ns / THS = -3.863ns (35 个端点)。根因不是逻辑
        #  太多, 而是 hw/constraints/ddr.xdc 里的 CLOCK_DEDICATED_ROUTE
        #  BACKBONE: 50MHz 从普通 IO (R4) 经 BACKBONE 进 MMCM, 实测
        #  Clock Path Skew 达 3.72ns, 数据路径 3.69ns 追不上这个偏斜。
        #
        #  一级 (布线前, post-place phys_opt):
        #     默认 DIRECTIVE -> WHS = -0.533ns
        #     ExploreWithHoldFix -> 把大部分违例压掉
        #
        #  二级 (布线后, post-route phys_opt):
        #     route 之后重新算一次真实偏斜, 再插延时修残余 hold。
        #     实测 (档位一完整跑通):
        #        只有一级 -> WHS = -0.295ns, THS = -3.863ns, 35 个违例端点
        #        加上二级 -> WNS = +0.431ns, WHS = +0.003ns, THS = 0.000, 0 个违例端点
        #     余量只有 3ps, 想留更多裕度可以把 route 指令换成 Explore
        #     (STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE = Explore, 多花约 20% 布线时间)。
        #
        #  踩过的坑 (2025.2):
        #     STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE 设
        #     ExploreWithHoldFix -> ERROR [Common 17-110] Invalid property
        #     value。布线后这一级只认 ExploreWithAggressiveHoldFix, 见下。
        if {[catch {set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE \
                        ExploreWithHoldFix [get_runs impl_1]} e]} {
            puts "        !! 设置 PHYS_OPT_DESIGN directive 失败: $e"
        } else {
            puts "        PHYS_OPT_DESIGN = ExploreWithHoldFix (一级修 hold)"
        }

        if {$HOLD_FIX2} {
            foreach {prop val} {
                STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED         1
                STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE     ExploreWithAggressiveHoldFix
            } {
                if {[catch {set_property $prop $val [get_runs impl_1]} e]} {
                    puts "        !! 设置 $prop 失败: $e"
                }
            }
            puts "        POST_ROUTE_PHYS_OPT_DESIGN = ExploreWithAggressiveHoldFix (二级修 hold)"
        }

        puts "        综合完成, 开始实现 (到 write_bitstream) ..."
        launch_runs impl_1 -to_step write_bitstream -jobs $JOBS
        wait_on_run impl_1
        puts "        实现状态: [get_property STATUS [get_runs impl_1]]"

        if {[get_property PROGRESS [get_runs impl_1]] eq "100%"} {
            if {![catch {open_run impl_1}]} {
                set _wns [get_property SLACK [get_timing_paths -delay_type max]]
                set _whs [get_property SLACK [get_timing_paths -delay_type min]]
                puts "        时序 WNS = $_wns ns   (期望 > 0)"
                puts "        时序 WHS = $_whs ns   (期望 > 0, 靠上面的 HoldFix)"
            }
        }

        #---------------------------------------------------------------
        #  产出检查 + 退出码缺陷提示
        #---------------------------------------------------------------
        if {[file exists $BIT_FILE]} {
            puts "        BIT 已生成: $BIT_FILE ([format %.0f [expr {[file size $BIT_FILE]/1024.0}]] KB)"
        } else {
            puts "        !! 没有找到 $BIT_FILE"
            puts "        !! 若各 run 的 runme.log 写着 completed successfully、.dcp 也在,"
            puts "        !! 说明是本机 Vivado 2025.2 的退出码缺陷 (0xC0000409):"
            puts "        !! 进程干完活后崩在退出路径上, run manager 只看退出码, 于是判 failed。"
            puts "        !! 修法见 docs 实验指导书 5.7 节：把只做退出码映射的 vivado.bat"
            puts "        !! 放到 C:/AMDDesignTools/2025.2/Vitis/bin/ 下 (rundef.js 优先查这个目录)。"
        }
    }
} else {
    puts "\[8/8\] 跳过综合/实现 (RUN_IMPL=0, 需要 bit 时把参数4 设为 1 重跑)"
}

#---------------------------------------------------------------------
#  12. 写下本工程的档位说明 (交付/复现用)
#---------------------------------------------------------------------
set fh [open [file join $PROJ_PATH board_profile.txt] w]
# 显式按 UTF-8 写: Tcl 默认用系统代码页 (中文 Windows 是 cp936),
# 遇到 GBK 里没有落点的字节会写成 '?', 中文标题会被截成乱码。
fconfigure $fh -encoding utf-8
puts $fh "LA132_SoC_HW  工程档位说明"
puts $fh "创建时间      : [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts $fh "工程名        : $PROJ_NAME"
puts $fh "档位          : $BOARD  ([board_define $BOARD])"
puts $fh "扩展板配置    : [board_desc $BOARD]"
puts $fh "器件          : $PART"
puts $fh "启用的外设宏  : [join [concat {GPIO UART INTC TIMER LCD TOUCH USB DMA RAM AXI DDR} [board_modules $BOARD]] {, }]"
puts $fh "引脚约束      : [join $xdc_names {, }]"
puts $fh ""
puts $fh "扩展槽引脚分配:"
foreach p [board_pins $BOARD] { puts $fh "    $p" }
puts $fh ""
puts $fh "重新生成本工程的命令:"
puts $fh "    vivado -mode batch -source create_project.tcl -tclargs $BOARD $OUT_DIR $PROJ_NAME $RUN_IMPL"
close $fh

#---------------------------------------------------------------------
#  13. 汇总
#---------------------------------------------------------------------
puts ""
puts "====================================================================="
puts " 工程已创建 : $PROJ_PATH/$PROJ_NAME.xpr"
puts " 档位说明   : $PROJ_PATH/board_profile.txt"
if {$RUN_IMPL && [file exists $BIT_FILE]} {
    puts " bit 文件   : $BIT_FILE"
} else {
    puts " bit 文件   : 尚未生成 (参数4=1 时自动生成, 位置 $BIT_FILE)"
}
puts ""
puts " 本档位启用的扩展外设:"
foreach m [board_modules $BOARD] { puts "   + $m" }
puts " 扩展槽引脚分配:"
foreach p [board_pins $BOARD] { puts "   - $p" }
puts ""
puts " APB 从设备地址 (0x3000_0000 + ID*0x1_0000):"
puts "   ID  0 0x3000_0000 gpio      ID  1 0x3001_0000 uart"
puts "   ID  2 0x3002_0000 intc      ID  3 0x3003_0000 timer"
puts "   ID  4 0x3004_0000 iic       ID  6 0x3006_0000 touch"
puts "   ID  9 0x3009_0000 pwm       ID 10 0x300A_0000 spi"
puts "   ID 11 0x300B_0000 adc9280   ID 12 0x300C_0000 dac9708"
puts "   ID 14 0x300E_0000 dma_apb   ID 15 0x300F_0000 ram"
puts "   ID 16 0x3010_0000 usb       ID 17 0x3200_0000 lcd(空设备)"
puts " AXI 从设备地址:"
puts "   0x2000_0000 AXI-LCD 64KB   0x2001_0000 AXI-DMAC 64KB   0x4000_0000 DDR3 1GB"
puts ""
puts " 下一步 (任选):"
puts "   * 打开 GUI      : start_gui"
puts "   * 只跑综合      : launch_runs synth_1 -jobs $JOBS; wait_on_run synth_1"
puts "   * 综合+实现+bit : launch_runs impl_1 -to_step write_bitstream; wait_on_run impl_1"
puts "                     (记得先设 PHYS_OPT_DESIGN = ExploreWithHoldFix, 见脚本 §11)"
puts ""
puts " 板上验证要点:"
puts "   1) clk_wiz_0 的 CLKOUT4 必须是 200MHz (供 MIG 作 sys_clk_i)"
puts "   2) bank 34/35 是 1.5V 域 (板上已装 DDR3): gpio0~7 / gpio24~31"
puts "      在 gpio.xdc 里是 LVCMOS15"
puts "   3) 换档位后必须重新综合, 只改 bit 不重新综合会保留旧档位的引脚"
puts "====================================================================="
