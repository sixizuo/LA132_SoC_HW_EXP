#=====================================================================
#  本文件所有 [get_ports ...] 均带 -quiet (端口存在性自保护):
#    本文件端口  <=>  config_sel.vh 的 PWM_PERIPHERALS(pwm1/2) / Step_motor_PERIPHERALS(gpio12~15)
#  define 了对应模块 -> 端口存在, 约束生效;
#  未 define         -> 端口不存在, set_property 空集合仅报 CRITICAL
#    WARNING [Common 17-55] (非错误), 约束自动失效, 综合/实现不受影响。
#  说明: XDC 不支持 if/llength 等流程控制 (Designutils 20-1307 会整行
#    跳过), 故不能用条件分支, 只能用 -quiet 自保护。
#  !! 注意: J7/J8 扩展板共用引脚, 多个扩展模块同时 define 会引脚冲突,
#     config_sel.vh 中扩展板只能开一个。
#=====================================================================
################################################################ PWM

#create_interface PWM
#set_property INTERFACE PWM [get_ports {pwm1 pwm2}]
# {J7-PWM} DC_MOTOR
set_property -dict {PACKAGE_PIN F21 IOSTANDARD LVCMOS33} [get_ports -quiet pwm1]
set_property -dict {PACKAGE_PIN D21 IOSTANDARD LVCMOS33} [get_ports -quiet pwm2]

# {J7-step_motor}
# {step_motor[0] step_motor[1] step_motor[2] step_motor[3]} {gpio12 gpio13 gpio14 gpio15}
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33} [get_ports -quiet gpio12]
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports -quiet gpio13]
set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33} [get_ports -quiet gpio14]
set_property -dict {PACKAGE_PIN G22 IOSTANDARD LVCMOS33} [get_ports -quiet gpio15]

################################################################ PWM


