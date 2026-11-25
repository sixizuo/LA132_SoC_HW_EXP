`ifndef _APB_ADDR_SVH
`define _APB_ADDR_SVH

`define APB_ADDR_TABLE \
	{ {32'h00000000, 32'h00000000},\
	{32'h33000000, 32'h00ffffff},\
	{32'h32000000, 32'h00ffffff},\
	{32'h30100000, 32'h0000ffff},\
	{32'h300f0000, 32'h0000ffff},\
	{32'h300e0000, 32'h0000ffff},\
	{32'h300d0000, 32'h0000ffff},\
	{32'h300c0000, 32'h0000ffff},\
	{32'h300b0000, 32'h0000ffff},\
	{32'h300a0000, 32'h0000ffff},\
	{32'h30090000, 32'h0000ffff},\
	{32'h30080000, 32'h0000ffff},\
	{32'h30070000, 32'h0000ffff},\
	{32'h30060000, 32'h0000ffff},\
	{32'h30050000, 32'h0000ffff},\
	{32'h30040000, 32'h0000ffff},\
	{32'h30030000, 32'h0000ffff},\
	{32'h30020000, 32'h0000ffff},\
	{32'h30010000, 32'h0000ffff},\
	{32'h30000000, 32'h0000ffff}}

`define APB_SLAVE_NUM 32

`define APB_ASSIGN_M2S(periph_prefix, signal_prefix, apb_id, width) \
  assign ``periph_prefix``_``signal_prefix`` = periph_``signal_prefix``[``apb_id`` * ``width`` +: ``width``];


`define APB_ASSIGN_S2M(periph_prefix, signal_prefix, apb_id, width) \
  assign periph_``signal_prefix``[``apb_id`` * ``width`` +: ``width``] = ``periph_prefix``_``signal_prefix``;




`define APB_PERIPH_DECLARATION(prefix, a_width, d_width, apb_id) \
	wire ``prefix``_psel; \
	wire ``prefix``_penable; \
	wire ``prefix``_pwrite; \
	wire [``a_width`` - 1 : 0] ``prefix``_paddr; \
	wire [3:0] ``prefix``_pstrb;\
	wire [``d_width`` - 1 : 0] ``prefix``_pwdata; \
	wire [``d_width`` - 1 : 0] ``prefix``_prdata; \
	wire ``prefix``_pack; \
	`APB_ASSIGN_M2S(``prefix``, psel,    ``apb_id``, 1) \
	`APB_ASSIGN_M2S(``prefix``, penable, ``apb_id``, 1) \
	`APB_ASSIGN_M2S(``prefix``, pwrite,  ``apb_id``, 1) \
	`APB_ASSIGN_M2S(``prefix``, paddr,   ``apb_id``, 32) \
	`APB_ASSIGN_M2S(``prefix``, pstrb,   ``apb_id``, 4) \
	`APB_ASSIGN_M2S(``prefix``, pwdata,  ``apb_id``, 32) \
	/* read signal*/                                     \
	`APB_ASSIGN_S2M(``prefix``, prdata,  ``apb_id``, 32) \
	`APB_ASSIGN_S2M(``prefix``, pack,    ``apb_id``, 1) 

`endif