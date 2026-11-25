#---------------------------------------------------------------------
#  btn_int[0] (U6) / btn_int[1] (V5) 位于 BANK 34 -> 1.5V 域
#  (板上装了 DDR3, bank 34/35 的 VCCO = 1.500V)。
#  故 IOSTANDARD 由 LVCMOS33 改为 LVCMOS15，详见 la132.xdc 头部说明。
#  在 DDR 版工程 la132_FPGA_ddr 里这两个脚叫 sys_key[2] / sys_key[3]，
#  同样是 LVCMOS15 (见 hw/xdc/SOCHK.xdc)。
#---------------------------------------------------------------------
create_interface INTC
set_property INTERFACE INTC [get_ports { btn_int[1] btn_int[0] }]

set_property -dict {PACKAGE_PIN U6 IOSTANDARD LVCMOS15} [get_ports {btn_int[0]}]
set_property -dict {PACKAGE_PIN V5 IOSTANDARD LVCMOS15} [get_ports {btn_int[1]}]





