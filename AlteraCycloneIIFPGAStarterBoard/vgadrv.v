module vgadrv(
	input wire clk25,
	output reg [3:0] VGA_R,
	output reg [3:0] VGA_G,
	output reg [3:0] VGA_B,
	output reg VGA_HS,
	output reg VGA_VS,

	input wire clk1,
	input wire clk2,

	input wire [3:0] gigatron_vga_r,
	input wire [3:0] gigatron_vga_g,
	input wire [3:0] gigatron_vga_b,
	input wire gigatron_vga_hs,
	input wire gigatron_vga_vs);

parameter LINES = 12;
parameter FIRSTLINE = 25;

reg [9:0] x;
reg [9:0] y;

reg [7:0] cnt_x;
reg [9:0] cnt_y;
reg [1:0] red[160][LINES];
reg [1:0] green[160][LINES];
reg [1:0] blue[160][LINES];

initial begin
	x = 0;
	y = 0;
	VGA_HS = 1;
	VGA_VS = 1;

	cnt_x = 0;
	cnt_y = 0;
end

always @(posedge clk1)
begin
	if (gigatron_vga_hs == 0) begin
		if (gigatron_vga_vs == 0) begin
			cnt_y <= 0;
		end else if (cnt_x > 172) begin
			cnt_y <= cnt_y + 8'h1;
		end
		cnt_x <= 0;
	end else begin
		cnt_x <= cnt_x + 8'h1;
	end

	if ((cnt_y >= FIRSTLINE) && (cnt_y < (FIRSTLINE + LINES*4))) begin
		if ((cnt_x >= 12) && (cnt_x < 172)) begin
			if (cnt_y[1:0] == 0) begin
				red[cnt_x - 12][(cnt_y - FIRSTLINE)/4] <= gigatron_vga_r[3:2];
				green[cnt_x - 12][(cnt_y - FIRSTLINE)/4] <= gigatron_vga_g[3:2];
				blue[cnt_x - 12][(cnt_y - FIRSTLINE)/4] <= gigatron_vga_b[3:2];
			end
		end
	end
end

always @(posedge clk25)
begin
	if (x < 800) begin
		x <= x + 10'h1;
	end else begin
		x <= 0;
		if (y < 525) begin
			y <= y + 10'h1;
		end else begin
			y <= 0;
		end
	end

	if ((y < 480) && (x < 640)) begin
		if ((y[9:2]) < LINES) begin
			VGA_R[3:2] <= red[x[9:2]][y[9:2]];
			VGA_R[1:0] <= 2'h0;
			VGA_G[3:2] <= green[x[9:2]][y[9:2]];
			VGA_G[1:0] <= 2'h0;
			VGA_B[3:2] <= blue[x[9:2]][y[9:2]];
			VGA_B[1:0] <= 2'h0;
		end else begin
			VGA_R <= 4'hf;
			VGA_G <= 4'hf;
			VGA_B <= 4'hf;
		end
	end else begin
		VGA_R <= 0;
		VGA_G <= 0;
		VGA_B <= 0;
	end

	if ((x >= 656) && (x < 752)) begin
		VGA_HS <= 0;
	end else begin
		VGA_HS <= 1;
	end

	if ((y >= 490) && (y < 492)) begin
		VGA_VS <= 0;
	end else begin
		VGA_VS <= 1;
	end
end

endmodule
