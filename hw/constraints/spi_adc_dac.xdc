#=====================================================================
#  本文件所有 [get_ports ...] 均带 -quiet (端口存在性自保护):
#    本文件端口  <=>  config_sel.vh 的 SPI_PERIPHERALS
#  define 了对应模块 -> 端口存在, 约束生效;
#  未 define         -> 端口不存在, set_property 空集合仅报 CRITICAL
#    WARNING [Common 17-55] (非错误), 约束自动失效, 综合/实现不受影响。
#  说明: XDC 不支持 if/llength 等流程控制 (Designutils 20-1307 会整行
#    跳过), 故不能用条件分支, 只能用 -quiet 自保护。
#  !! 注意: J7/J8 扩展板共用引脚, 多个扩展模块同时 define 会引脚冲突,
#     config_sel.vh 中扩展板只能开一个。
#=====================================================================
############################ J7 start #############################
# J7 eeprom/rtc/spi, AD/DA right
# less io
# J7_01 J8_03 ==> GND
# J7_02 ==> +5v
# J7_04 ==> +3.3v

set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports -quiet {spi_csn[1]}]
set_property -dict {PACKAGE_PIN D22 IOSTANDARD LVCMOS33} [get_ports -quiet {spi_csn[0]}]
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33} [get_ports -quiet {spi_clk[1]}]
set_property -dict {PACKAGE_PIN E22 IOSTANDARD LVCMOS33} [get_ports -quiet {spi_clk[0]}]
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports -quiet {spi_mosi[1]}]
set_property -dict {PACKAGE_PIN F21 IOSTANDARD LVCMOS33} [get_ports -quiet {spi_miso[0]}]
#set_property -dict {PACKAGE_PIN G18  IOSTANDARD LVCMOS33} [get_ports J07_11]
set_property -dict {PACKAGE_PIN D21 IOSTANDARD LVCMOS33} [get_ports -quiet {spi_mosi[0]}]
#set_property -dict {PACKAGE_PIN G22  IOSTANDARD LVCMOS33} [get_ports J07_13]
#set_property -dict {PACKAGE_PIN E21  IOSTANDARD LVCMOS33} [get_ports J07_14]
#set_property -dict {PACKAGE_PIN G21  IOSTANDARD LVCMOS33} [get_ports J07_15]
#set_property -dict {PACKAGE_PIN E18  IOSTANDARD LVCMOS33} [get_ports J07_16]
#set_property -dict {PACKAGE_PIN F20  IOSTANDARD LVCMOS33} [get_ports J07_17]
#set_property -dict {PACKAGE_PIN F18  IOSTANDARD LVCMOS33} [get_ports J07_18]
#set_property -dict {PACKAGE_PIN F19  IOSTANDARD LVCMOS33} [get_ports J07_19]
#set_property -dict {PACKAGE_PIN F15  IOSTANDARD LVCMOS33} [get_ports J07_20]
#set_property -dict {PACKAGE_PIN E17  IOSTANDARD LVCMOS33} [get_ports J07_21]
#set_property -dict {PACKAGE_PIN C17  IOSTANDARD LVCMOS33} [get_ports J07_22]
#set_property -dict {PACKAGE_PIN D17  IOSTANDARD LVCMOS33} [get_ports J07_23]
#set_property -dict {PACKAGE_PIN F16  IOSTANDARD LVCMOS33} [get_ports J07_24]
#set_property -dict {PACKAGE_PIN E14  IOSTANDARD LVCMOS33} [get_ports J07_25]
#set_property -dict {PACKAGE_PIN D16  IOSTANDARD LVCMOS33} [get_ports J07_26]
#set_property -dict {PACKAGE_PIN E13  IOSTANDARD LVCMOS33} [get_ports J07_27]
#set_property -dict {PACKAGE_PIN E16  IOSTANDARD LVCMOS33} [get_ports J07_28]
#set_property -dict {PACKAGE_PIN F14  IOSTANDARD LVCMOS33} [get_ports J07_29]
#set_property -dict {PACKAGE_PIN D15  IOSTANDARD LVCMOS33} [get_ports J07_30]
############################# J7 end ##############################

