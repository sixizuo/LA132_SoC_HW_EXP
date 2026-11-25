// Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2019.2 (win64) Build 2708876 Wed Nov  6 21:40:23 MST 2019
// Date        : Fri Sep  1 11:40:40 2023
// Host        : DESKTOP-Q1R5QHV running 64-bit major release  (build 9200)
// Command     : write_verilog -mode synth_stub F:/FPGA/LA132_stub.v
// Design      : la132_top
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a100tfgg484-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module la132_top(mode_lisa, inst_xor, boot_pc, clk, clk_count, 
  hard_resetn, soft_resetn, sleeping, can_high_freq, cpu_debug_mode, cpu_fetch_pc, nmi, ext_int, 
  prid_revision, cpunum, arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arvalid, arready, 
  rid, rdata, rresp, rlast, rvalid, rready, awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, 
  awvalid, awready, wid, wdata, wstrb, wlast, wvalid, wready, bid, bresp, bvalid, bready, inst_sram_en, 
  inst_sram_strb, inst_sram_wr, inst_sram_fetch, inst_sram_addr, inst_sram_wdata, 
  inst_sram_rdata, data_sram_en, data_sram_strb, data_sram_wr, data_sram_fetch, 
  data_sram_addr, data_sram_wdata, data_sram_rdata, inst_sram_ack, inst_sram_rrdy, 
  inst_sram_resp, data_sram_ack, data_sram_rrdy, data_sram_resp, ljtag_prrst, ljtag_lock, 
  trstn, tck, tms, tdi, tdo, dcc_ram_tagv_req_bus, dcc_ram_data_req_bus, dcc_ram_lrud_req_bus, 
  dcc_ram_tagv_resp_bus, dcc_ram_data_resp_bus, dcc_ram_lrud_resp_bus, 
  icc_ram_tagv_req_bus, icc_ram_data_req_bus, icc_ram_lrud_req_bus, 
  icc_ram_tagv_resp_bus, icc_ram_data_resp_bus, icc_ram_lrud_resp_bus, wb_pc, wb_rf_dest, 
  wb_rf_wen, wb_rf_value, ibus0_valid, ibus0_base, ibus0_mask, ibus1_valid, ibus1_base, 
  ibus1_mask, ibus2_valid, ibus2_base, ibus2_mask, ibus3_valid, ibus3_base, ibus3_mask, 
  dbus0_valid, dbus0_base, dbus0_mask, dbus1_valid, dbus1_base, dbus1_mask, dbus2_valid, 
  dbus2_base, dbus2_mask, dbus3_valid, dbus3_base, dbus3_mask, test_mode)
/* synthesis syn_black_box black_box_pad_pin="mode_lisa,inst_xor[31:0],boot_pc[31:0],clk,clk_count,hard_resetn,soft_resetn,sleeping,can_high_freq,cpu_debug_mode,cpu_fetch_pc[31:0],nmi,ext_int[5:0],prid_revision[3:0],cpunum[9:0],arid[3:0],araddr[31:0],arlen[3:0],arsize[2:0],arburst[1:0],arlock[1:0],arcache[3:0],arprot[2:0],arvalid,arready,rid[3:0],rdata[31:0],rresp[1:0],rlast,rvalid,rready,awid[3:0],awaddr[31:0],awlen[3:0],awsize[2:0],awburst[1:0],awlock[1:0],awcache[3:0],awprot[2:0],awvalid,awready,wid[3:0],wdata[31:0],wstrb[3:0],wlast,wvalid,wready,bid[3:0],bresp[1:0],bvalid,bready,inst_sram_en,inst_sram_strb[3:0],inst_sram_wr,inst_sram_fetch,inst_sram_addr[31:0],inst_sram_wdata[31:0],inst_sram_rdata[31:0],data_sram_en,data_sram_strb[3:0],data_sram_wr,data_sram_fetch,data_sram_addr[31:0],data_sram_wdata[31:0],data_sram_rdata[31:0],inst_sram_ack,inst_sram_rrdy,inst_sram_resp,data_sram_ack,data_sram_rrdy,data_sram_resp,ljtag_prrst,ljtag_lock,trstn,tck,tms,tdi,tdo,dcc_ram_tagv_req_bus[0:0],dcc_ram_data_req_bus[0:0],dcc_ram_lrud_req_bus[0:0],dcc_ram_tagv_resp_bus[0:0],dcc_ram_data_resp_bus[0:0],dcc_ram_lrud_resp_bus[0:0],icc_ram_tagv_req_bus[0:0],icc_ram_data_req_bus[0:0],icc_ram_lrud_req_bus[0:0],icc_ram_tagv_resp_bus[0:0],icc_ram_data_resp_bus[0:0],icc_ram_lrud_resp_bus[0:0],wb_pc[31:0],wb_rf_dest[4:0],wb_rf_wen,wb_rf_value[31:0],ibus0_valid,ibus0_base[31:0],ibus0_mask[31:0],ibus1_valid,ibus1_base[31:0],ibus1_mask[31:0],ibus2_valid,ibus2_base[31:0],ibus2_mask[31:0],ibus3_valid,ibus3_base[31:0],ibus3_mask[31:0],dbus0_valid,dbus0_base[31:0],dbus0_mask[31:0],dbus1_valid,dbus1_base[31:0],dbus1_mask[31:0],dbus2_valid,dbus2_base[31:0],dbus2_mask[31:0],dbus3_valid,dbus3_base[31:0],dbus3_mask[31:0],test_mode" */;
  input mode_lisa;
  input [31:0]inst_xor;
  input [31:0]boot_pc;
  input clk;
  input clk_count;
  input hard_resetn;
  input soft_resetn;
  output sleeping;
  output can_high_freq;
  output cpu_debug_mode;
  output [31:0]cpu_fetch_pc;
  input nmi;
  input [5:0]ext_int;
  input [3:0]prid_revision;
  input [9:0]cpunum;
  output [3:0]arid;
  output [31:0]araddr;
  output [3:0]arlen;
  output [2:0]arsize;
  output [1:0]arburst;
  output [1:0]arlock;
  output [3:0]arcache;
  output [2:0]arprot;
  output arvalid;
  input arready;
  input [3:0]rid;
  input [31:0]rdata;
  input [1:0]rresp;
  input rlast;
  input rvalid;
  output rready;
  output [3:0]awid;
  output [31:0]awaddr;
  output [3:0]awlen;
  output [2:0]awsize;
  output [1:0]awburst;
  output [1:0]awlock;
  output [3:0]awcache;
  output [2:0]awprot;
  output awvalid;
  input awready;
  output [3:0]wid;
  output [31:0]wdata;
  output [3:0]wstrb;
  output wlast;
  output wvalid;
  input wready;
  input [3:0]bid;
  input [1:0]bresp;
  input bvalid;
  output bready;
  output inst_sram_en;
  output [3:0]inst_sram_strb;
  output inst_sram_wr;
  output inst_sram_fetch;
  output [31:0]inst_sram_addr;
  output [31:0]inst_sram_wdata;
  input [31:0]inst_sram_rdata;
  output data_sram_en;
  output [3:0]data_sram_strb;
  output data_sram_wr;
  output data_sram_fetch;
  output [31:0]data_sram_addr;
  output [31:0]data_sram_wdata;
  input [31:0]data_sram_rdata;
  input inst_sram_ack;
  input inst_sram_rrdy;
  input inst_sram_resp;
  input data_sram_ack;
  input data_sram_rrdy;
  input data_sram_resp;
  output ljtag_prrst;
  input ljtag_lock;
  input trstn;
  input tck;
  input tms;
  input tdi;
  output tdo;
  output [0:0]dcc_ram_tagv_req_bus;
  output [0:0]dcc_ram_data_req_bus;
  output [0:0]dcc_ram_lrud_req_bus;
  input [0:0]dcc_ram_tagv_resp_bus;
  input [0:0]dcc_ram_data_resp_bus;
  input [0:0]dcc_ram_lrud_resp_bus;
  output [0:0]icc_ram_tagv_req_bus;
  output [0:0]icc_ram_data_req_bus;
  output [0:0]icc_ram_lrud_req_bus;
  input [0:0]icc_ram_tagv_resp_bus;
  input [0:0]icc_ram_data_resp_bus;
  input [0:0]icc_ram_lrud_resp_bus;
  output [31:0]wb_pc;
  output [4:0]wb_rf_dest;
  output wb_rf_wen;
  output [31:0]wb_rf_value;
  input ibus0_valid;
  input [31:0]ibus0_base;
  input [31:0]ibus0_mask;
  input ibus1_valid;
  input [31:0]ibus1_base;
  input [31:0]ibus1_mask;
  input ibus2_valid;
  input [31:0]ibus2_base;
  input [31:0]ibus2_mask;
  input ibus3_valid;
  input [31:0]ibus3_base;
  input [31:0]ibus3_mask;
  input dbus0_valid;
  input [31:0]dbus0_base;
  input [31:0]dbus0_mask;
  input dbus1_valid;
  input [31:0]dbus1_base;
  input [31:0]dbus1_mask;
  input dbus2_valid;
  input [31:0]dbus2_base;
  input [31:0]dbus2_mask;
  input dbus3_valid;
  input [31:0]dbus3_base;
  input [31:0]dbus3_mask;
  input test_mode;
endmodule
