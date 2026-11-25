# [端口自保护] 所有 get_ports 带 -quiet: LCD_PERIPHERALS(lcd_*) / TOUCH_PERIPHERALS(touch_*) 未 define 时对应约束自动失效 (仅 CRITICAL WARNING, 非错误)。XDC 不支持 if/llength, 不能写条件分支。
################################################################ lcd_new

create_interface LCD
set_property INTERFACE LCD [get_ports -quiet { lcd_rgb[23] lcd_rgb[22] lcd_rgb[21] lcd_rgb[20] lcd_rgb[19] lcd_rgb[18] lcd_rgb[17] lcd_rgb[16] lcd_rgb[15] lcd_rgb[14] lcd_rgb[13] lcd_rgb[12] lcd_rgb[11] lcd_rgb[10] lcd_rgb[9] lcd_rgb[8] lcd_rgb[7] lcd_rgb[6] lcd_rgb[5] lcd_rgb[4] lcd_rgb[3] lcd_rgb[2] lcd_rgb[1] lcd_rgb[0] lcd_hs lcd_vs lcd_de lcd_bl lcd_clk lcd_rst_n }]
# new LCD
################################################################ LCD
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[23]}]
set_property -dict {PACKAGE_PIN W10 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[22]}]
set_property -dict {PACKAGE_PIN AA9 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[21]}]
set_property -dict {PACKAGE_PIN AB10 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[20]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[19]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[18]}]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[17]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[16]}]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[15]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[14]}]
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[13]}]
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[12]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[11]}]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[10]}]
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[9]}]
set_property -dict {PACKAGE_PIN N13 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[8]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[7]}]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[6]}]
set_property -dict {PACKAGE_PIN AB17 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[5]}]
set_property -dict {PACKAGE_PIN AB16 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[4]}]
set_property -dict {PACKAGE_PIN AA16 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[3]}]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[2]}]
set_property -dict {PACKAGE_PIN AB15 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[1]}]
set_property -dict {PACKAGE_PIN AA15 IOSTANDARD LVCMOS33} [get_ports -quiet {lcd_rgb[0]}]

set_property -dict {PACKAGE_PIN AA14 IOSTANDARD LVCMOS33} [get_ports -quiet lcd_hs]
set_property -dict {PACKAGE_PIN Y13 IOSTANDARD LVCMOS33} [get_ports -quiet lcd_vs]
set_property -dict {PACKAGE_PIN AB13 IOSTANDARD LVCMOS33} [get_ports -quiet lcd_de]
set_property -dict {PACKAGE_PIN AA13 IOSTANDARD LVCMOS33} [get_ports -quiet lcd_bl]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports -quiet lcd_clk]
set_property -dict {PACKAGE_PIN AA10 IOSTANDARD LVCMOS33} [get_ports -quiet lcd_rst_n]




create_interface TOUCH
set_property INTERFACE TOUCH [get_ports -quiet { touch_scl touch_sda touch_int touch_rst_n }]
#LCD TOUCH
set_property -dict {PACKAGE_PIN AB11 IOSTANDARD LVCMOS33} [get_ports -quiet touch_scl]
set_property -dict {PACKAGE_PIN W11 IOSTANDARD LVCMOS33} [get_ports -quiet touch_sda]
set_property -dict {PACKAGE_PIN AA11 IOSTANDARD LVCMOS33} [get_ports -quiet touch_int]
set_property -dict {PACKAGE_PIN W12 IOSTANDARD LVCMOS33} [get_ports -quiet touch_rst_n]


################################################################ lcd_new


