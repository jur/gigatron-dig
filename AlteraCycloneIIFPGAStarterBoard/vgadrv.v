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
	input wire gigatron_vga_vs,

	// RAM write
	output reg [21:0] wr_addr,
	output reg [15:0] wr_data,
	output reg wr_enable,

	// RAM read
	output reg [21:0] rd_addr,
	input wire [15:0] rd_data,
	input wire rd_ready,
	output reg rd_enable,

	input wire busy,

	// Dedbug
	output reg [15:0] dbgvga,
	input wire [2:0] SW);

parameter LINES = 120;
parameter FIRSTLINE = 10'd25;
parameter WIDTH = 160;

reg [9:0] x;
reg [9:0] y;

reg [7:0] cnt_x;
reg [9:0] cnt_y;


reg [5:0] wdata[WIDTH];
reg wready;
reg wrun;
reg [9:0] wy;
reg [7:0] wx;
reg [7:0] wlast;

reg [5:0] rdata[WIDTH];
reg [9:0] ry;
reg [9:0] rline;
reg [7:0] rx;
reg [7:0] rlast;
reg rstarted;

reg [15:0] dbgcnt;

initial begin
	x = 0;
	y = 0;
	VGA_HS = 1;
	VGA_VS = 1;

	cnt_x = 0;
	cnt_y = 0;

	wr_addr = 22'h000000;
	wr_data = 16'h0000;
	wr_enable = 1'b0;

	rd_addr = 22'h000000;
	rd_enable = 1'b0;

	wready = 1'b0;
	wrun = 1'b0;
	wy = 10'h0;
	wx = 8'h0;
	wlast = 8'h0;

	ry = 10'h0;
	rline = 10'h0;
	rx = 8'h0;
	rstarted = 1'b0;

	dbgcnt = 16'h0;
end

`define GET_X(v) ((v) - 8'd12)

always @(posedge clk1)
begin
	if (gigatron_vga_hs == 0) begin
		if (gigatron_vga_vs == 0) begin
			if (cnt_y > 480) begin
				cnt_y <= 0;
			end
		end else if (cnt_x > 172) begin
			cnt_y <= cnt_y + 8'h1;
		end
		cnt_x <= 0;
	end else begin
		cnt_x <= cnt_x + 8'h1;
	end

	if (wrun) begin
		wready <= 1'b0;
	end

	if ((cnt_y >= FIRSTLINE) && (cnt_y < (FIRSTLINE + LINES*4))) begin
		if (cnt_x >= 12) begin
			if (cnt_x < 172) begin
				if (cnt_y[1:0] == 0) begin
					/* red */
					wdata[`GET_X(cnt_x)][1:0] <= gigatron_vga_r[3:2];
					/* green */
					wdata[`GET_X(cnt_x)][3:2] <= gigatron_vga_g[3:2];
					/* blue */
					wdata[`GET_X(cnt_x)][5:4] <= gigatron_vga_b[3:2];

					wy <= cnt_y - FIRSTLINE;
					wlast <= `GET_X(cnt_x);
					if (!wrun) begin
						wready <= 1'b1;
					end
				end
			end
		end
	end
end

// Reading SDRAM requires clock of SDRAM controller, because otherwise rd_ready might be lost.
always @(posedge clk25)
begin
	if (busy) begin
		rd_enable <= 1'b0;
		wr_enable <= 1'b0;
	end

	if (wready) begin
		wrun = 1'b1;
	end

	if (rstarted) begin
		if (rd_ready) begin
			// Reading finished.
			rdata[rx] <= rd_data[5:0];
			rdata[rx + 1] <= rd_data[11:6];
			rx <= rx + 8'h2;
			rstarted <= 1'b0;
			dbgcnt <= dbgcnt + 16'h1;
		end
	end else if (rline[9:2] == ry[9:2]) begin
		// Time for reading data:
		if (!busy && !wr_enable) begin
			if (rx < WIDTH) begin
				// Start reading:
				rd_addr[6:0] <= rx[7:1];
				rd_addr[21:7] <= rline[9:2];
				rd_enable <= 1'b1;
				rstarted <= 1'b1;
			end else begin
				// line finished
				rx <= 8'h0;
				if (rline[9:2] >= LINES) begin
					rline <= 10'd0;
				end else begin
					rline <= rline + 10'd4;
				end
			end
		end
	end else begin
		rx <= 8'h0;

		// Time for writing data:
		if (wready || wrun) begin
			if (!busy) begin
				if (wx < WIDTH) begin
					if (wx < wlast) begin
						// Write data to SDRAM:
						wr_addr[6:0] <= wx[7:1];
						wr_addr[21:7] <= wy[9:2];
						wr_data[5:0] <= wdata[wx];
						wr_data[11:6] <= wdata[wx + 1];
						wr_data[15:12] <= 0;
						wr_enable <= 1'b1;
						wx <= wx + 8'h2;
					end
				end else begin
					// finished writing
					wrun <= 1'b0;
					wx <= 8'h0;
				end
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

	/* Default color black */
	VGA_R <= 0;
	VGA_G <= 0;
	VGA_B <= 0;

	if (y < 480) begin
		if (x < 640) begin
			if ((y[9:2]) < LINES) begin
				VGA_R[3:2] <= rdata[x[9:2]][1:0];
				VGA_R[1:0] <= 2'h0;
				VGA_G[3:2] <= rdata[x[9:2]][3:2];
				VGA_G[1:0] <= 2'h0;
				VGA_B[3:2] <= rdata[x[9:2]][5:4];
				VGA_B[1:0] <= 2'h0;
			end
		end
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

	if (x >= 400 /* 640 */) begin
		if (y < 480) begin
			ry <= y + 10'h1;
		end else if (y == 525) begin
			ry <= 10'h0;
		end
		rlast <= x;
	end
end

always @(posedge clk25)
begin
	dbgvga <= 16'h0;
	case (SW[2:0])
		3'b000: begin
			dbgvga[0] <= wready;
			dbgvga[1] <= wr_enable;
			dbgvga[9] <= rd_enable;
			dbgvga[10] <= rstarted;
			dbgvga[11] <= rd_ready;
			dbgvga[15] <= busy;
		end
		3'b001: begin
			dbgvga <= dbgcnt;
		end
		3'b010: begin
			dbgvga <= ry;
		end
		3'b011: begin
			dbgvga <= rline;
		end
		3'b100: begin
			dbgvga[15:0] <= rd_addr[21:16];
		end
		3'b101: begin
			dbgvga[15:0] <= rd_addr[15:0];
		end
		3'b110: begin
			dbgvga[15:0] <= rx;
		end
		3'b111: begin
			dbgvga[15:0] <= wy;
		end
		default: dbgvga <= 16'hDEAD;

	endcase
end

endmodule
