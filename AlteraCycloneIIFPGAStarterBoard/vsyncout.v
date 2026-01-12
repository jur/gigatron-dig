module vsyncout(
	input wire CLOCK_50,
	input wire reset_n,

	input wire gigatron_vga_hs,
	input wire gigatron_vga_vs,

	output reg [7:0] txdata,
	output reg txready,

	output reg [3:0] dbghscount);

reg gigatron_vga_hs_d;
reg gigatron_vga_vs_d;

reg [3:0] hscount;
reg [7:0] inbyte;
reg [2:0] bitcnt;

initial begin
	txdata = 8'h00;
	txready = 1'b0;
	gigatron_vga_hs_d = 1'b1;
	gigatron_vga_vs_d = 1'b1;
	hscount = 4'h0;
	inbyte = 8'h00;
	bitcnt = 3'h0;
	dbghscount = 4'h00;
end

always @(posedge CLOCK_50)
begin
	if (!reset_n) begin
		txdata <= 8'h00;
		txready <= 1'b0;
		gigatron_vga_hs_d <= 1'b1;
		gigatron_vga_vs_d <= 1'b1;
		hscount <= 4'h0;
		inbyte <= 8'h00;
		bitcnt <= 3'h0;
		dbghscount <= 4'h00;
	end else begin
		gigatron_vga_hs_d <= gigatron_vga_hs;
		gigatron_vga_vs_d <= gigatron_vga_vs;

		if (gigatron_vga_vs_d & ~gigatron_vga_vs) begin
			// VSYNC start
			hscount <= 3'h0;
			txready <= 1'b0;
		end else if (gigatron_vga_vs == 0) begin
			// during VSYNC
			if (gigatron_vga_hs_d & ~gigatron_vga_hs) begin
				// count HSYNC
				hscount <= hscount + 4'h1;
			end
		end

		if (~gigatron_vga_vs_d & gigatron_vga_vs) begin
			// VSYNC end

			dbghscount = hscount;

			case (hscount)
				4'h7: begin
					inbyte <= {1'b0, inbyte[7:1]};
					bitcnt <= bitcnt + 3'h1;
				end
				4'h9: begin
					inbyte <= {1'b1, inbyte[7:1]};
					bitcnt <= bitcnt + 3'h1;
				end
				default: begin
					bitcnt <= 3'h0;
				end
			endcase

			if (bitcnt == 3'h7) begin
				// Byte complete
				case (hscount)
					4'h7: begin
						txdata <= {1'b0, inbyte[7:1]};
						txready <= 1'b1;
					end
					4'h9: begin
						txdata <= {1'b1, inbyte[7:1]};
						txready <= 1'b1;
					end
				endcase
			end
		end
	end
end

endmodule
