#=====================================================================
#  本文件所有 [get_ports ...] 均带 -quiet (端口存在性自保护):
#    本文件端口  <=>  config_sel.vh 的 IIC_PERIPHERALS
#  define 了对应模块 -> 端口存在, 约束生效;
#  未 define         -> 端口不存在, set_property 空集合仅报 CRITICAL
#    WARNING [Common 17-55] (非错误), 约束自动失效, 综合/实现不受影响。
#  说明: XDC 不支持 if/llength 等流程控制 (Designutils 20-1307 会整行
#    跳过), 故不能用条件分支, 只能用 -quiet 自保护。
#  !! 注意: J7/J8 扩展板共用引脚, 多个扩展模块同时 define 会引脚冲突,
#     config_sel.vh 中扩展板只能开一个。
#=====================================================================
#set_property -dict {PACKAGE_PIN C18  IOSTANDARD LVCMOS33} [get_ports J08_05]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports -quiet iic0_scl]
#set_property -dict {PACKAGE_PIN C22  IOSTANDARD LVCMOS33} [get_ports J08_07]
set_property -dict {PACKAGE_PIN A21 IOSTANDARD LVCMOS33} [get_ports -quiet iic0_sda]
#set_property -dict {PACKAGE_PIN B22  IOSTANDARD LVCMOS33} [get_ports J08_09]
set_property -dict {PACKAGE_PIN B21 IOSTANDARD LVCMOS33} [get_ports -quiet iic1_scl]
#set_property -dict {PACKAGE_PIN C20  IOSTANDARD LVCMOS33} [get_ports J08_11]
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33} [get_ports -quiet iic1_sda]
#set_property -dict {PACKAGE_PIN D20  IOSTANDARD LVCMOS33} [get_ports J08_13]
#set_property -dict {PACKAGE_PIN B20  IOSTANDARD LVCMOS33} [get_ports J08_14]
#set_property -dict {PACKAGE_PIN C19  IOSTANDARD LVCMOS33} [get_ports J08_15]
#set_property -dict {PACKAGE_PIN A19  IOSTANDARD LVCMOS33} [get_ports J08_16]
#set_property -dict {PACKAGE_PIN F13  IOSTANDARD LVCMOS33} [get_ports J08_17]
#set_property -dict {PACKAGE_PIN A18  IOSTANDARD LVCMOS33} [get_ports J08_18]
#set_property -dict {PACKAGE_PIN B16  IOSTANDARD LVCMOS33} [get_ports J08_19]
#set_property -dict {PACKAGE_PIN B18  IOSTANDARD LVCMOS33} [get_ports J08_20]
#set_property -dict {PACKAGE_PIN B15  IOSTANDARD LVCMOS33} [get_ports J08_21]
#set_property -dict {PACKAGE_PIN C15  IOSTANDARD LVCMOS33} [get_ports J08_22]
#set_property -dict {PACKAGE_PIN B17  IOSTANDARD LVCMOS33} [get_ports J08_23]
#set_property -dict {PACKAGE_PIN A16  IOSTANDARD LVCMOS33} [get_ports J08_24]
#set_property -dict {PACKAGE_PIN C14  IOSTANDARD LVCMOS33} [get_ports J08_25]
#set_property -dict {PACKAGE_PIN A15  IOSTANDARD LVCMOS33} [get_ports J08_26]
#set_property -dict {PACKAGE_PIN B13  IOSTANDARD LVCMOS33} [get_ports J08_27]
#set_property -dict {PACKAGE_PIN A14  IOSTANDARD LVCMOS33} [get_ports J08_28]
#set_property -dict {PACKAGE_PIN C13  IOSTANDARD LVCMOS33} [get_ports J08_29]
#set_property -dict {PACKAGE_PIN A13  IOSTANDARD LVCMOS33} [get_ports J08_30]

