//=====================================================================
//  one_int_gen.v  ——  单路中断产生与锁存（实验一使用）
//---------------------------------------------------------------------
//  与 hw/peripheral/apb_intc/one_int_gen.v 的区别（重要，实验报告要写）：
//    原 8 路版本的边沿模式漏掉第一个边沿。原因是 int_lt 的置位条件
//    引用了 count，而 count 与 int_lt 在同一个时钟沿更新：边沿到达的那
//    一拍 count 仍是 0，下一拍 int_delay 已经追上 int_in，比较条件不再
//    成立，于是 int_lt 永远置不起来；只有第二次边沿才能靠残留的 count
//    置位。实测表现为“按第一次没反应，按第二次才进中断”。
//    本实验把边沿锁存改为同拍判定，去掉 count，单次边沿即可锁存，
//    其余（使能、极性、软件置位/清除、电平直通）与原版完全一致。
//---------------------------------------------------------------------
module one_int_gen (
	input  wire clk     ,
	input  wire rst     ,

	input  wire int_en  ,
	input  wire int_pol ,
	input  wire int_edge,
	input  wire int_in  ,
	input  wire int_clr ,
	input  wire int_set ,
	output wire int_out
);

	reg int_delay;
	reg int_lt;
	reg int_force;

	wire inv_int;
	wire level_int;

	// 电平变化检测：与上一拍不同，且变化后的电平等于有效极性
	wire edge_hit = (int_in != int_delay) && (int_in == int_pol);

	always @(posedge clk) begin
		if (rst) begin
			int_delay <= 1'b0;
		end else begin
			int_delay <= int_in;
		end
	end

	// 软件强制位：SET 置位，CLR 清除，优先级 SET > CLR
	always @(posedge clk) begin
		if (rst) begin
			int_force <= 1'b0;
		end else if (int_set) begin
			int_force <= 1'b1;
		end else if (int_clr) begin
			int_force <= 1'b0;
		end
	end

	// 边沿锁存：同拍置位，只有 CLR 能撤
	//   1) CLR 优先级最高，避免边沿与清除同拍时锁存位残留、反复进中断；
	//   2) int_edge=0（电平模式）时锁存位保持清零，防止电平模式下积累的
	//      历史边沿在切到边沿模式后冒出来（原版没有这一条，属于隐患）。
	always @(posedge clk) begin
		if (rst) begin
			int_lt <= 1'b0;
		end else if (int_clr) begin
			int_lt <= 1'b0;
		end else if (!int_edge) begin
			int_lt <= 1'b0;
		end else if (edge_hit) begin
			int_lt <= 1'b1;
		end
	end

	assign inv_int   = !(int_pol ^ int_in);
	assign level_int = int_edge ? int_lt : inv_int;
	assign int_out   = (int_en & level_int) | int_force;

endmodule
