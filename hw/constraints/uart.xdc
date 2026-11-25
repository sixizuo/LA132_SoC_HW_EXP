# [端口自保护] 所有 get_ports 带 -quiet: UART_PERIPHERALS 未 define 时端口不存在, 约束自动失效 (仅 CRITICAL WARNING, 非错误)。XDC 不支持 if/llength, 不能写条件分支。
################################################################ UART

create_interface UART0
set_property INTERFACE UART0 [get_ports -quiet { uart0_rx uart0_tx }]
# {core-board-UART}
set_property -dict {PACKAGE_PIN Y11 IOSTANDARD LVCMOS33} [get_ports -quiet uart0_rx]
set_property -dict {PACKAGE_PIN Y12 IOSTANDARD LVCMOS33} [get_ports -quiet uart0_tx]
set_property PULLTYPE PULLUP [get_ports -quiet uart0_rx]
set_property PULLTYPE PULLUP [get_ports -quiet uart0_tx]
# # {J8-UART}
# set_property -dict {PACKAGE_PIN AA15 IOSTANDARD LVCMOS33} [get_ports uart0_rx]
# set_property -dict {PACKAGE_PIN AB7  IOSTANDARD LVCMOS33} [get_ports uart0_tx]
# set_property PULLUP true [get_ports uart0_rx]
# set_property PULLUP true [get_ports uart0_tx]

################################################################ UART





