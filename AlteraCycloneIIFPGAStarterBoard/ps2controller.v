module ps2controller(
	input wire CLOCK_50,
	input wire clk1,
	input wire clk2,
	input wire reset_n,

	// Debug
	input wire [2:0] SW,
	output reg [15:0] ps2_dbg,

	// PS/2
	input wire PS2_CLK,
	input wire PS2_DAT,

	// Output key codes
	output reg [7:0] ps2_data,
	output reg ps2_ready,

	// Ack
	input wire ps2_sending);

// PS/2
reg [3:0] ps2_bit;
reg [10:0] ps2_dat_fifo;
reg [7:0] ps2_rxbuf[3];
reg [2:0] ps2_ext_valid;
reg ps2_ext_wait;
reg [7:0] ps2_rx_cnt;
reg [7:0] ps2_errors;
reg [15:0] ps2_last_err;

reg ps2_clk_s0;
reg ps2_clk_s1;
reg ps2_dat_s0;
reg ps2_dat_s1;

wire ps2_clk_fall = ((ps2_clk_s1 == 1'b1) & (ps2_clk_s0 == 1'b0));

always @(posedge CLOCK_50)
begin
	ps2_clk_s0 <= PS2_CLK;
	ps2_clk_s1 <= ps2_clk_s0;

	ps2_dat_s0 <= PS2_DAT;
	ps2_dat_s1 <= ps2_dat_s0;

	if (!reset_n) begin
		ps2_bit <= 0;
		ps2_rxbuf[0] <= 0;
		ps2_rxbuf[1] <= 0;
		ps2_rxbuf[2] <= 0;
		ps2_dat_fifo <= 0;
		ps2_rx_cnt <= 0;
		ps2_ext_valid <= 2'b00;
		ps2_ext_wait <= 1'b0;
		ps2_errors <= 8'h00;
		ps2_last_err <= 16'h0000;
	end else begin
		if (ps2_clk_fall) begin
			ps2_dat_fifo[ps2_bit] <= ps2_dat_s1;
			if ((ps2_bit == 0) && (ps2_dat_s1 == 1)) begin
				ps2_bit <= 0;

				ps2_errors <= ps2_errors + 8'h1;
				ps2_last_err[15] <= 1'b1;
			end else begin
				if (ps2_bit < 10) begin
					ps2_bit <= ps2_bit + 4'h1;
				end else begin
					ps2_bit <= 0;
					// Check start, stop and odd parity bit:
					if ((ps2_dat_fifo[0] == 0) && (ps2_dat_s1 == 1) && (ps2_dat_fifo[9] == ~^ps2_dat_fifo[8:1])) begin
						if (!ps2_ext_wait) begin
							ps2_rxbuf[0] <= ps2_dat_fifo[8:1];
							ps2_rxbuf[1] <= 8'h00;
							ps2_rxbuf[2] <= 8'h00;
							ps2_ext_valid[0] <= 1'b0;
							ps2_ext_valid[1] <= 1'b0;
						end else begin
							ps2_ext_wait <= 1'b0;
							if (!ps2_ext_valid[0]) begin
								ps2_rxbuf[1] <= ps2_dat_fifo[8:1];
								ps2_ext_valid[0] <= 1'b1;
							end else begin
								ps2_rxbuf[2] <= ps2_dat_fifo[8:1];
								ps2_ext_valid[1] <= 1'b1;
							end
						end

						if ((ps2_dat_fifo[8:1] == 8'hE0) || (ps2_dat_fifo[8:1] == 8'hF0)) begin
							ps2_ext_wait <= 1'b1;
						end else begin
							ps2_rx_cnt <= ps2_rx_cnt + 8'h1;
						end
					end else begin
						// protocol error
						ps2_ext_wait <= 1'b0;
						ps2_errors <= ps2_errors + 8'h1;
						ps2_last_err[9:0] <= ps2_dat_fifo[9:0];
						ps2_last_err[10] <= ps2_dat_s1;
					end
				end
			end
		end
	end
end

reg [7:0] kbd_cnt;
reg [7:0] ps2_txbuf[16];
reg [3:0] txpos;
reg [3:0] rxpos;
reg ps2_sending_d;

wire ps2_sending_rise = ps2_sending & ~ps2_sending_d;

// TX Buffer handling 
always @(posedge CLOCK_50)
begin
	if (!reset_n) begin
		kbd_cnt <= 8'h00;
		txpos <= 0;
		rxpos <= 0;
		ps2_sending_d <= 1'b0;
	end else begin
		// Fill TX buffer:
		if (kbd_cnt != ps2_decode_cnt) begin
			if (keycode != 8'hFF) begin
				ps2_txbuf[txpos] <= keycode;
				ps2_ready <= 1'b1;
				txpos <= txpos + 4'h1;
			end
			kbd_cnt <= ps2_decode_cnt;
		end

		// Get keycodes from TX buffer:
		if (rxpos == txpos) begin
			// TX buffer empty
			ps2_data <= 8'hFF;
			ps2_ready <= 1'b0;
		end else begin
			ps2_data <= ps2_txbuf[rxpos];
			ps2_ready <= 1'b1;

			if (ps2_sending_rise) begin
				// Get next
				rxpos <= rxpos + 4'h1;
			end
		end

		ps2_sending_d <= ps2_sending;
	end
end

// PS/2 Keyboard decoder
reg [7:0] keycode;
reg [1:0] ps2_shift;
reg [1:0] ps2_alt;
reg [7:0] ps2_decode_cnt;

always @(posedge CLOCK_50)
begin
	if (!reset_n) begin
		ps2_shift <= 2'b00;
		ps2_alt <= 2'b00;
		ps2_decode_cnt <= 8'h00;
	end else begin
		ps2_decode_cnt <= ps2_rx_cnt;
		keycode[7:0] <= 8'hff;

		case (ps2_rxbuf[0])
			8'h5A: keycode <= 8'h0a; // ENTER
			8'h29: keycode <= 8'h20; // SPACE
			8'h0E: keycode <= 8'h5E; // ^
			8'h55: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h60; // `
				end else begin
					keycode <= 8'h3D; // =
				end
			end

			8'h5B: begin
				if (ps2_alt[1] != 0) begin
					keycode <= 8'h7E; // ~
				end else begin
					if (ps2_shift != 0) begin
						keycode <= 8'h2A; // *
					end else begin
						keycode <= 8'h2B; // +
					end
				end
			end
			8'h41: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h3B; // ;
				end else begin
					keycode <= 8'h2C; // ,
				end
			end
			8'h4A: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h5F; // _
				end else begin
					keycode <= 8'h2D; // -
				end
			end
			8'h49: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h3A; // :
				end else begin
					keycode <= 8'h2E; // .
				end
			end

			8'h45: begin
				if (ps2_alt[1] != 0) begin
					keycode <= 8'h7D; // }
				end else begin
					if (ps2_shift != 0) begin
						keycode <= 8'h3D; // =
					end else begin
						keycode <= 8'h30; // 0
					end
				end
			end

			8'h16: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h21; // !
				end else begin
					keycode <= 8'h31; // 1
				end
			end

			8'h1E: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h22; // "
				end else begin
					keycode <= 8'h32; // 2
				end
			end

			8'h26: keycode <= 8'h33; // 3
			8'h25: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h24; // $
				end else begin
					keycode <= 8'h34; // 4
				end
			end

			8'h2E: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h25; // %
				end else begin
					keycode <= 8'h35; // 5
				end
			end

			8'h36: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h26; // &
				end else begin
					keycode <= 8'h36; // 6
				end
			end

			8'h3D: begin
				if (ps2_alt[1] != 0) begin
					keycode <= 8'h7B; // {
				end else begin
					if (ps2_shift != 0) begin
						keycode <= 8'h37; // 7
					end else begin
						keycode <= 8'h2F; // /
					end
				end
			end

			8'h3E: begin
				if (ps2_alt[1] != 0) begin
					keycode <= 8'h5B; // [
				end else begin
					if (ps2_shift != 0) begin
						keycode <= 8'h28; // (
					end else begin
						keycode <= 8'h38; // 8
					end
				end
			end

			8'h46: begin
				if (ps2_alt[1] != 0) begin
					keycode <= 8'h5D; // ]
				end else begin
					if (ps2_shift != 0) begin
						keycode <= 8'h29; // )
					end else begin
						keycode <= 8'h39; // 9
					end
				end
			end

			8'h4C: keycode <= 8'h3B; // ;
			8'h61: begin
				if (ps2_alt[1] != 0) begin
					keycode <= 8'h7C; // |
				end else begin
					if (ps2_shift != 0) begin
						keycode <= 8'h3E; // >
					end else begin
						keycode <= 8'h3C; // <
					end
				end
			end
			8'h4E: begin
				if (ps2_alt[1] != 0) begin
					keycode <= 8'h5C; // \\
				end else begin
					if (ps2_shift != 0) begin
						keycode <= 8'h3F; // ?
					end
				end
			end

			8'h54: keycode <= 8'h5B; // [
			8'h5D: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h27; // '
				end else begin
					keycode <= 8'h23; // #
				end
			end
			8'h52: keycode <= 8'h5E; // ^

			8'h1C: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h41; // A
				end else begin
					keycode <= 8'h61; // A
				end
			end
			8'h32: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h42; // B
				end else begin
					keycode <= 8'h62; // B
				end
			end
			8'h21: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h43; // C
				end else begin
					keycode <= 8'h63; // C
				end
			end
			8'h23: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h44; // D
				end else begin
					keycode <= 8'h64; // D
				end
			end
			8'h24: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h45; // E
				end else begin
					keycode <= 8'h65; // E
				end
			end
			8'h2B: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h46; // F
				end else begin
					keycode <= 8'h66; // F
				end
			end
			8'h34: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h47; // G
				end else begin
					keycode <= 8'h67; // G
				end
			end
			8'h33: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h48; // H
				end else begin
					keycode <= 8'h68; // H
				end
			end
			8'h43: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h49; // I
				end else begin
					keycode <= 8'h69; // I
				end
			end
			8'h3B: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h4A; // J
				end else begin
					keycode <= 8'h6A; // J
				end
			end
			8'h42: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h4B; // K
				end else begin
					keycode <= 8'h6B; // K
				end
			end
			8'h4B: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h4C; // L
				end else begin
					keycode <= 8'h6C; // L
				end
			end
			8'h3A: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h4D; // M
				end else begin
					keycode <= 8'h6D; // M
				end
			end
			8'h31: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h4E; // N
				end else begin
					keycode <= 8'h6E; // N
				end
			end
			8'h44: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h4F; // O
				end else begin
					keycode <= 8'h6F; // O
				end
			end
			8'h4D: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h50; // P
				end else begin
					keycode <= 8'h70; // P
				end
			end
			8'h15: begin
				if (ps2_alt[1] != 0) begin
					keycode <= 8'h40; // @
				end else begin
					if (ps2_shift != 0) begin
						keycode <= 8'h51; // Q
					end else begin
						keycode <= 8'h71; // Q
					end
				end
			end
			8'h2D: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h52; // R
				end else begin
					keycode <= 8'h72; // R
				end
			end
			8'h1B: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h53; // S
				end else begin
					keycode <= 8'h73; // S
				end
			end
			8'h2C: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h54; // T
				end else begin
					keycode <= 8'h74; // T
				end
			end
			8'h3C: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h55; // U
				end else begin
					keycode <= 8'h75; // U
				end
			end
			8'h2A: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h56; // V
				end else begin
					keycode <= 8'h76; // V
				end
			end
			8'h1D: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h57; // W
				end else begin
					keycode <= 8'h77; // W
				end
			end
			8'h22: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h58; // X
				end else begin
					keycode <= 8'h78; // X
				end
			end
			8'h1A: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h59; // Y
				end else begin
					keycode <= 8'h79; // Y
				end
			end
			8'h35: begin
				if (ps2_shift != 0) begin
					keycode <= 8'h5A; // Z
				end else begin
					keycode <= 8'h7A; // Z
				end
			end

			8'h66: keycode <= 8'h7F; // BACKSPACE

			8'h59: begin // R SHIFT
				ps2_shift[0] <= 1'b1;
			end

			8'h12: begin // L SHIFT
				ps2_shift[1] <= 1'b1;
			end

			8'h11: begin // L ALT
				ps2_alt[0] <= 1'b1;
			end

			8'hE0: begin
					if (ps2_ext_valid[0]) begin
						case(ps2_rxbuf[1])
							8'h75: keycode <= 8'hF7; // up
							8'h72: keycode <= 8'hFB; // down
							8'h6B: keycode <= 8'hFD; // left
							8'h74: keycode <= 8'hFE; // right
							8'h71: keycode <= 8'h7F; // DEL

							8'h11: begin // R ALT
								ps2_alt[1] <= 1'b1;
							end


							8'hF0: begin
								if (ps2_ext_valid[1]) begin
									case(ps2_rxbuf[2])
										8'h11: begin // R ALT
											ps2_alt[1] <= 1'b0;
										end
									endcase
								end
							end
						endcase
					end
			end

			8'hF0: begin
					// Key released
					if (ps2_ext_valid[0]) begin
						case(ps2_rxbuf[1])
							8'h59: begin // R SHIFT
								ps2_shift[0] <= 1'b0;
							end

							8'h12: begin // L SHIFT
								ps2_shift[1] <= 1'b0;
							end

							8'h11: begin // L ALT
								ps2_alt[0] <= 1'b0;
							end
						endcase
					end
			end
		endcase
	end
end

always @(posedge CLOCK_50)
begin
	if (!reset_n) begin
		ps2_dbg <= 16'hdead;
	end else begin
		ps2_dbg <= 16'hdead;
		case(SW)
			3'b000: begin
				ps2_dbg[15:8] <= kbd_cnt;
				ps2_dbg[7:0] <= ps2_decode_cnt;
			end

			3'b001: begin
				ps2_dbg[15:8] <= ps2_rxbuf[2];
				ps2_dbg[7:0] <= ps2_errors;
			end

			3'b010: begin
				ps2_dbg[15:8] <= ps2_rxbuf[1];
				ps2_dbg[7:0] <= ps2_rxbuf[0];
			end

			3'b011: begin
				ps2_dbg[15:8] <= txpos;
				ps2_dbg[7:0] <= rxpos;
			end

			3'b100: begin
				ps2_dbg[15:8] <= ps2_bit;
				ps2_dbg[7:0] <= keycode;
			end

			3'b101: begin
				ps2_dbg[15:8] <= ps2_txbuf[1];
				ps2_dbg[7:0] <= ps2_txbuf[0];
			end

			3'b110: begin
				ps2_dbg[0] <= ps2_ready;
				ps2_dbg[1] <= ps2_sending;
				ps2_dbg[3:2] <= 0;
				ps2_dbg[7:4] <= rxpos;
				ps2_dbg[15:8] <= ps2_data;
			end

			3'b111: begin
				ps2_dbg <= ps2_last_err;
			end
		endcase
	end
end

endmodule
