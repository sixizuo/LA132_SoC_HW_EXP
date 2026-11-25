
#=====================================================================
#  !! BANK 34 / 35 是 1.5V 域 (实验箱上已装配 DDR3) !!
#---------------------------------------------------------------------
#  DDR3 的 SSTL15 / DIFF_SSTL15 要求 bank 34/35 的 VCCO = 1.500V，
#  因此同一 bank 内的其他 IO 也必须是 1.5V 标准 (LVCMOS15)，否则
#  place_design 会报：
#     ERROR: [DRC BIVC-1] Bank IO standard Vcc: Conflicting Vcc voltages
#       in bank 34 ... ddr3_ck_p[0] (DIFF_SSTL15, requiring VCCO=1.500)
#       and clk50m (LVCMOS33, requiring VCCO=3.300)
#
#  本文件里以下端口已由 LVCMOS33 改为 LVCMOS15（引脚位置不变），
#  与已实际出过 bit 的 DDR 版工程
#   la132_FPGA_ddr/hw/xdc/SOCHK.xdc 完全一致 —— 那边把同一批引脚配成
#   LVCMOS15 (clk50m_i R4 / sys_key[0..3] Y6 AA6 U6 V5)，只是端口名不同。
#
#     clk50m (R4)   rstn (Y6)   reset_clear (AA6)
#     btn_int[0] (U6) / btn_int[1] (V5)      -> 见 INTC.xdc
#     gpio0~7 (Y9 W9 AB8 AA8 V9 V8 T6 R6)    -> 见 gpio.xdc
#     gpio24~31 (L6 K4 F4 G4 AB7 AB6 T3 V7)  -> 见 gpio.xdc
#
#  >> 若实验箱 bank 34/35 实际是 3.3V（即未装配 DDR3），必须把这 21 个
#     端口改回 LVCMOS33 并且不要启用 hw/constraints/ddr.xdc，否则既会
#     报 DRC BIVC-1，3.3V 电平也会损伤 IO。
#=====================================================================

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

#---------------------------------------------------------------------
#  FLASH（配置存储器）相关位流属性
#---------------------------------------------------------------------
#  1) CFGBVS / CONFIG_VOLTAGE：不写会报 DRC CFGBVS-1 警告，bank 0 上
#     用户 IO 的电平检查也会失去依据。
#     本板配置域 VCCO_0 = 3.3V，CFGBVS 接 VCCO。
#     >> 若板上 CFGBVS 实际接 GND（1.8V 配置域），把下面两行改成
#        CFGBVS GND + CONFIG_VOLTAGE 1.8，否则 DONE/INIT_B 电平判断错误。
set_property CFGBVS VCCO       [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

#  2) SPI 启动位宽：不写 = x1（默认，最保险，任何 SPI FLASH 都能启动，
#     代价是 2.5MB 位流要读 6~8 秒）。
#     x4 启动需要 FLASH 的 QE 位已置位，且烧写镜像必须用 -interface SPIx4
#     生成，两者不一致会“烧进去了但上电不启动”。
#     旧工程 la132_FPGA_ddr 是用 x4 的，若确认那颗 FLASH 支持 QE，可取消注释：
#set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

#  3) 启动时钟：默认 3MHz，x1 时可提到 33MHz 缩短启动时间（可选）。
#set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]

create_clock -period 20.000 [get_ports clk50m]
set_property -dict {PACKAGE_PIN R4 IOSTANDARD LVCMOS15} [get_ports clk50m]
set_property -dict {PACKAGE_PIN Y6 IOSTANDARD LVCMOS15} [get_ports rstn]
set_property -dict {PACKAGE_PIN AA6 IOSTANDARD LVCMOS15} [get_ports reset_clear]

set_property -dict {PACKAGE_PIN U22 IOSTANDARD LVCMOS33} [get_ports pps_led];#led0

create_interface LJTAG
set_property INTERFACE LJTAG [get_ports { ljtag_tck ljtag_tdi ljtag_tdo ljtag_tms ljtag_trst }]
set_property -dict {PACKAGE_PIN U20 IOSTANDARD LVCMOS33} [get_ports ljtag_trst]
set_property -dict {PACKAGE_PIN V19 IOSTANDARD LVCMOS33} [get_ports ljtag_tms]
set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVCMOS33} [get_ports ljtag_tdo]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33} [get_ports ljtag_tdi]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33} [get_ports ljtag_tck]
set_property PULLTYPE PULLDOWN [get_ports ljtag_tdo]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets ljtag_tck_IBUF]
# set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets ljtag_tck_IBUF_BUFG]

################################################################
################################################################
################################################################










