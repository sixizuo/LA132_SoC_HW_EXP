# [端口自保护] 所有 get_ports/get_nets 带 -quiet: DDR_PERIPHERALS 未 define 时 ddr3_* 端口不存在, 引脚约束自动失效 (仅 CRITICAL WARNING, 非错误)。
################################################################
#### DDR3 (MIG 7-series) —— LA132_DDR_LCD
#
#  本文件由 la132_FPGA_ddr/hw/xdc/ddr.xdc 移植而来, 改动点 :
#
#   1) 层次路径 :
#        la132_FPGA_ddr : <top_hk>/u_mcu/clk_wiz_0_inst/inst/...
#        本工程          : <godson_mcu_top>/clk_wiz_0_inst/inst/...
#        即 clk_wiz_0 直接挂在顶层 godson_mcu_top 下, 例化名 clk_wiz_0_inst
#
#   2) set_clock_groups 用 -quiet, 不做 Tcl 存在性判断 :
#        XDC 约束文件不支持 if / llength 等流程控制语句 (会被整行跳过),
#        所以改用 set_clock_groups -quiet + get_clocks -quiet,
#        若 MIG 未生成导致时钟取不到时静默跳过, 不会报 "no clocks in group"。
#        clk_pll_i 是 MIG 内部 MMCM 的反馈时钟
#        (mig_7series_v4_2_infrastructure.v 里的 CLKFBOUT),
#        若 IP 未生成或名字被 uniquify, get_clocks 会返回空表,
#        直接 set_clock_groups 会报 "no clocks in group" 错误。
#
#   3) ddr3_* 引脚位置/IOSTANDARD 与云晓 100T 实验箱完全一致, 未做改动。
################################################################

#### DDR3 ------------------------------------------------------------------
# 顶层 50MHz 晶振不是时钟专用引脚, 需允许使用 BACKBONE 布线资源
# (层次: godson_mcu_top / clk_wiz_0_inst / inst / clk_in1_clk_wiz_0)
set_property CLOCK_DEDICATED_ROUTE BACKBONE \
    [get_nets -quiet clk_wiz_0_inst/inst/clk_in1_clk_wiz_0]

# clk_out1_clk_wiz_0 (32MHz, AXI 互联域) 与 MIG 内部 MMCM 的反馈时钟
# clk_pll_i 之间走的是 axi_cdc_bridge 的握手式跨时钟通路, 声明为异步组,
# 避免 Vivado 对跨域路径做无谓的时序分析。
#
# !! 注意: XDC 约束文件只支持有限的 Tcl 子集, 不支持 if / llength 等流程控制
#    (Vivado 会报 CRITICAL WARNING [Designutils 20-1307] Command 'if' is not
#     supported in the xdc constraint file, 并整行跳过 —— 那样异步组就白写了)。
#    所以这里不做存在性判断, 改用 set_clock_groups -quiet / get_clocks -quiet
#    来抑制"时钟不存在"的报错。
#    两个时钟名与 la132_FPGA_ddr/hw/xdc/ddr.xdc 保持一致。
set_clock_groups -quiet -asynchronous \
    -group [get_clocks -quiet clk_out1_clk_wiz_0] \
    -group [get_clocks -quiet clk_pll_i]
#### DDR3 ------------------------------------------------------------------


create_interface DDR3

set_property INTERFACE DDR3 [get_ports -quiet {ddr3_addr[*] ddr3_ba[*] ddr3_cas_n ddr3_ck_n[0] ddr3_ck_p[0] ddr3_cke[0] ddr3_cs_n[0] ddr3_dm[*] ddr3_dq[*] ddr3_dqs_n[*] ddr3_dqs_p[*] ddr3_odt[0] ddr3_ras_n ddr3_reset_n ddr3_we_n}]

set_property -dict {PACKAGE_PIN AA4 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_addr[0]}]
set_property -dict {PACKAGE_PIN AB2 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_addr[1]}]
set_property -dict {PACKAGE_PIN AA5 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_addr[2]}]
set_property -dict {PACKAGE_PIN AB5 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_addr[3]}]
set_property -dict {PACKAGE_PIN AB1 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_addr[4]}]
set_property -dict {PACKAGE_PIN U3 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_addr[5]}]
set_property -dict {PACKAGE_PIN W1 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_addr[6]}]
set_property -dict {PACKAGE_PIN T1 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_addr[7]}]
set_property -dict {PACKAGE_PIN V2 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_addr[8]}]
set_property -dict {PACKAGE_PIN U2 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_addr[9]}]
set_property -dict {PACKAGE_PIN Y1 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_addr[10]}]
set_property -dict {PACKAGE_PIN W2 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_addr[11]}]
set_property -dict {PACKAGE_PIN Y2 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_addr[12]}]
set_property -dict {PACKAGE_PIN U1 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_addr[13]}]
set_property -dict {PACKAGE_PIN V3 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_addr[14]}]
set_property -dict {PACKAGE_PIN AA3 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_ba[0]}]
set_property -dict {PACKAGE_PIN Y3 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_ba[1]}]
set_property -dict {PACKAGE_PIN Y4 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_ba[2]}]
set_property -dict {PACKAGE_PIN W4 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet ddr3_cas_n]
set_property -dict {PACKAGE_PIN R2 IOSTANDARD DIFF_SSTL15 SLEW FAST} [get_ports -quiet {ddr3_ck_n[0]}]
set_property -dict {PACKAGE_PIN R3 IOSTANDARD DIFF_SSTL15 SLEW FAST} [get_ports -quiet {ddr3_ck_p[0]}]
set_property -dict {PACKAGE_PIN T5 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_cke[0]}]
set_property -dict {PACKAGE_PIN AB3 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_cs_n[0]}]
set_property -dict {PACKAGE_PIN D2 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dm[0]}]
set_property -dict {PACKAGE_PIN G2 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dm[1]}]
set_property -dict {PACKAGE_PIN C2 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[0]}]
set_property -dict {PACKAGE_PIN G1 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[1]}]
set_property -dict {PACKAGE_PIN A1 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[2]}]
set_property -dict {PACKAGE_PIN F3 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[3]}]
set_property -dict {PACKAGE_PIN B2 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[4]}]
set_property -dict {PACKAGE_PIN F1 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[5]}]
set_property -dict {PACKAGE_PIN B1 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[6]}]
set_property -dict {PACKAGE_PIN E2 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[7]}]
set_property -dict {PACKAGE_PIN H3 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[8]}]
set_property -dict {PACKAGE_PIN G3 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[9]}]
set_property -dict {PACKAGE_PIN H2 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[10]}]
set_property -dict {PACKAGE_PIN H5 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[11]}]
set_property -dict {PACKAGE_PIN J1 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[12]}]
set_property -dict {PACKAGE_PIN J5 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[13]}]
set_property -dict {PACKAGE_PIN K1 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[14]}]
set_property -dict {PACKAGE_PIN H4 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[15]}]
set_property -dict {PACKAGE_PIN L4 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[16]}]
set_property -dict {PACKAGE_PIN M3 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[17]}]
set_property -dict {PACKAGE_PIN L3 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[18]}]
set_property -dict {PACKAGE_PIN J6 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[19]}]
set_property -dict {PACKAGE_PIN K3 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[20]}]
set_property -dict {PACKAGE_PIN K6 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[21]}]
set_property -dict {PACKAGE_PIN J4 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[22]}]
set_property -dict {PACKAGE_PIN L5 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[23]}]
set_property -dict {PACKAGE_PIN P1 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[24]}]
set_property -dict {PACKAGE_PIN N4 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[25]}]
set_property -dict {PACKAGE_PIN R1 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[26]}]
set_property -dict {PACKAGE_PIN N2 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[27]}]
set_property -dict {PACKAGE_PIN M6 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[28]}]
set_property -dict {PACKAGE_PIN N5 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[29]}]
set_property -dict {PACKAGE_PIN P6 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[30]}]
set_property -dict {PACKAGE_PIN P2 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dq[31]}]

set_property -dict {PACKAGE_PIN M2 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dm[2]}]
set_property -dict {PACKAGE_PIN M5 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dm[3]}]

set_property -dict {PACKAGE_PIN D1 IOSTANDARD DIFF_SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dqs_n[0]}]
set_property -dict {PACKAGE_PIN J2 IOSTANDARD DIFF_SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dqs_n[1]}]
set_property -dict {PACKAGE_PIN E1 IOSTANDARD DIFF_SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dqs_p[0]}]
set_property -dict {PACKAGE_PIN K2 IOSTANDARD DIFF_SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dqs_p[1]}]

set_property -dict {PACKAGE_PIN M1 IOSTANDARD DIFF_SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dqs_p[2]}]
set_property -dict {PACKAGE_PIN L1 IOSTANDARD DIFF_SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dqs_n[2]}]
set_property -dict {PACKAGE_PIN P5 IOSTANDARD DIFF_SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dqs_p[3]}]
set_property -dict {PACKAGE_PIN P4 IOSTANDARD DIFF_SSTL15 SLEW FAST} [get_ports -quiet {ddr3_dqs_n[3]}]

set_property -dict {PACKAGE_PIN U5 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet {ddr3_odt[0]}]
set_property -dict {PACKAGE_PIN V4 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet ddr3_ras_n]
set_property -dict {PACKAGE_PIN W6 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet ddr3_reset_n]
set_property -dict {PACKAGE_PIN AA1 IOSTANDARD SSTL15 SLEW FAST} [get_ports -quiet ddr3_we_n]

# ---- 备用: 若顶层被 top_hk 再次例化(u_mcu), 用下面这条替换上面第 1 条 ----
# set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets u_mcu/clk_wiz_0_inst/inst/clk_in1_clk_wiz_0]
