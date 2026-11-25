#=====================================================================
#  本文件所有 [get_ports ...] 均带 -quiet (端口存在性自保护):
#    本文件端口  <=>  config_sel.vh 的 ARRAY_PERIPHERALS
#  define 了对应模块 -> 端口存在, 约束生效;
#  未 define         -> 端口不存在, set_property 空集合仅报 CRITICAL
#    WARNING [Common 17-55] (非错误), 约束自动失效, 综合/实现不受影响。
#  说明: XDC 不支持 if/llength 等流程控制 (Designutils 20-1307 会整行
#    跳过), 故不能用条件分支, 只能用 -quiet 自保护。
#  !! 注意: J7/J8 扩展板共用引脚, 多个扩展模块同时 define 会引脚冲突,
#     config_sel.vh 中扩展板只能开一个。
#=====================================================================
#expand board J8
#{col0~3}(gpio8~11}
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS33} [get_ports -quiet gpio8]
set_property -dict {PACKAGE_PIN A15 IOSTANDARD LVCMOS33} [get_ports -quiet gpio9]
set_property -dict {PACKAGE_PIN A14 IOSTANDARD LVCMOS33} [get_ports -quiet gpio10]
set_property -dict {PACKAGE_PIN A13 IOSTANDARD LVCMOS33} [get_ports -quiet gpio11]
#{row0 row1 row2 row3}{ gpio8,gpio9,gpio10,gpio11}
set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS33} [get_ports -quiet gpio16]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33} [get_ports -quiet gpio17]
set_property -dict {PACKAGE_PIN B13 IOSTANDARD LVCMOS33} [get_ports -quiet gpio18]
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports -quiet gpio19]

#expand board J8 LED_MATRIX
set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33} [get_ports -quiet gpio32]
set_property -dict {PACKAGE_PIN B21 IOSTANDARD LVCMOS33} [get_ports -quiet gpio33]
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33} [get_ports -quiet gpio34]
set_property -dict {PACKAGE_PIN F13 IOSTANDARD LVCMOS33} [get_ports -quiet gpio35]
set_property -dict {PACKAGE_PIN A19 IOSTANDARD LVCMOS33} [get_ports -quiet gpio36]
set_property -dict {PACKAGE_PIN C19 IOSTANDARD LVCMOS33} [get_ports -quiet gpio37]
set_property -dict {PACKAGE_PIN C22 IOSTANDARD LVCMOS33} [get_ports -quiet gpio38]
set_property -dict {PACKAGE_PIN C18 IOSTANDARD LVCMOS33} [get_ports -quiet gpio39]

set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS33} [get_ports -quiet gpio40]
set_property -dict {PACKAGE_PIN B22 IOSTANDARD LVCMOS33} [get_ports -quiet gpio41]
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports -quiet gpio42]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports -quiet gpio43]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports -quiet gpio44]
set_property -dict {PACKAGE_PIN A18 IOSTANDARD LVCMOS33} [get_ports -quiet gpio45]
set_property -dict {PACKAGE_PIN A21 IOSTANDARD LVCMOS33} [get_ports -quiet gpio46]
set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33} [get_ports -quiet gpio47]