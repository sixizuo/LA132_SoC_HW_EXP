# [端口自保护] 所有 get_ports 带 -quiet: GPIO_PERIPHERALS 未 define 时端口不存在, 约束自动失效 (仅 CRITICAL WARNING, 非错误)。XDC 不支持 if/llength, 不能写条件分支。
################################################################ GPIO
#---------------------------------------------------------------------
#  !! gpio0~7 与 gpio24~31 位于 BANK 34/35 -> 1.5V 域 !!
#  (板上装了 DDR3, bank 34/35 的 VCCO = 1.500V，DDR3 用 SSTL15)
#  故这两组的 IOSTANDARD 由 LVCMOS33 改为 LVCMOS15，详见 la132.xdc 头部。
#
#  在 DDR 版工程 la132_FPGA_ddr/hw/xdc/SOCHK.xdc 里，这批**同一个引脚**
#  是这样命名的（标准同为 LVCMOS15）：
#       gpio0~7   (Y9 W9 AB8 AA8 V9 V8 T6 R6)  <->  sw[0..7]    拨码开关
#       gpio24~31 (L6 K4 F4 G4 AB7 AB6 T3 V7)  <->  led[0..7]   主板上 LED
#
#  注意：gpio48 及之后的 gpio 在 bank 13/14/15，仍为 LVCMOS33，未改动。
#---------------------------------------------------------------------

#create_interface GPIO
#set_property INTERFACE GPIO [get_ports { gpio0 gpio1 gpio10 gpio11 gpio16 gpio17 gpio18 gpio19 gpio2 gpio24 gpio25 gpio26 gpio27 gpio28 gpio29 gpio3 gpio30 gpio31 gpio4 gpio40 gpio41 gpio42 gpio43 gpio44 gpio45 gpio46 gpio47 gpio5 gpio56 gpio57 gpio58 gpio59 gpio6 gpio60 gpio61 gpio62 gpio63 gpio7 gpio8 gpio9 }]
#set_property INTERFACE GPIO [get_ports {gpio}]
# {sw0 sw1 sw2 sw3} {gpio0 gpio1 gpio2 gpio3}# {SW4 SW5 SW6 SW7} {gpio4 gpio5 gpio6 gpio7}
set_property -dict {PACKAGE_PIN Y9 IOSTANDARD LVCMOS15} [get_ports -quiet gpio0]
set_property -dict {PACKAGE_PIN W9 IOSTANDARD LVCMOS15} [get_ports -quiet gpio1]
set_property -dict {PACKAGE_PIN AB8 IOSTANDARD LVCMOS15} [get_ports -quiet gpio2]
set_property -dict {PACKAGE_PIN AA8 IOSTANDARD LVCMOS15} [get_ports -quiet gpio3]
set_property -dict {PACKAGE_PIN V9 IOSTANDARD LVCMOS15} [get_ports -quiet gpio4]
set_property -dict {PACKAGE_PIN V8 IOSTANDARD LVCMOS15} [get_ports -quiet gpio5]
set_property -dict {PACKAGE_PIN T6 IOSTANDARD LVCMOS15} [get_ports -quiet gpio6]
set_property -dict {PACKAGE_PIN R6 IOSTANDARD LVCMOS15} [get_ports -quiet gpio7]

# {main-board}
#{LED0~7}(gpio24~31}
set_property -dict {PACKAGE_PIN L6 IOSTANDARD LVCMOS15} [get_ports -quiet gpio24]
set_property -dict {PACKAGE_PIN K4 IOSTANDARD LVCMOS15} [get_ports -quiet gpio25]
set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS15} [get_ports -quiet gpio26]
set_property -dict {PACKAGE_PIN G4 IOSTANDARD LVCMOS15} [get_ports -quiet gpio27]
set_property -dict {PACKAGE_PIN AB7 IOSTANDARD LVCMOS15} [get_ports -quiet gpio28]
set_property -dict {PACKAGE_PIN AB6 IOSTANDARD LVCMOS15} [get_ports -quiet gpio29]
set_property -dict {PACKAGE_PIN T3 IOSTANDARD LVCMOS15} [get_ports -quiet gpio30]
set_property -dict {PACKAGE_PIN V7 IOSTANDARD LVCMOS15} [get_ports -quiet gpio31]

# {main-board}
#{an0~3}(gpio48~50}
set_property -dict {PACKAGE_PIN AA20 IOSTANDARD LVCMOS33} [get_ports -quiet gpio48]
set_property -dict {PACKAGE_PIN AA21 IOSTANDARD LVCMOS33} [get_ports -quiet gpio49]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports -quiet gpio50]
# {seg_a seg_b seg_c seg_d} {seg_e seg_f seg_g seg_dp} {gpio56~64}
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33} [get_ports -quiet gpio56]
set_property -dict {PACKAGE_PIN H14 IOSTANDARD LVCMOS33} [get_ports -quiet gpio57]
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS33} [get_ports -quiet gpio58]
set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS33} [get_ports -quiet gpio59]
set_property -dict {PACKAGE_PIN J19 IOSTANDARD LVCMOS33} [get_ports -quiet gpio60]
set_property -dict {PACKAGE_PIN H19 IOSTANDARD LVCMOS33} [get_ports -quiet gpio61]
set_property -dict {PACKAGE_PIN G16 IOSTANDARD LVCMOS33} [get_ports -quiet gpio62]
set_property -dict {PACKAGE_PIN G15 IOSTANDARD LVCMOS33} [get_ports -quiet gpio63]



################################################################ GPIO





