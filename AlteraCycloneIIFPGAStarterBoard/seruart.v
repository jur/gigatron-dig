module seruart #(
	parameter CLOCKFREQ = 50000000,
	parameter BAUDRATE = 115200
)(
	input wire clk,
	input wire reset_n,

	// UART TX
	input  wire [7:0] tx_data,
	input  wire tx_start,
	output reg tx_busy,

	// Ack
	input wire ser_sending,

	// UART RX
	output reg [7:0] rx_data,
	output reg rx_valid,

	// UART
	output reg tx,
	input  wire rx
);

localparam integer BAUDCOUNT = CLOCKFREQ / BAUDRATE;

// UART TX
reg [15:0] tx_counter;
reg [3:0] tx_bit_counter;

reg [9:0] tx_shiftreg;

always @(posedge clk) begin
	if (!reset_n) begin
		tx <= 1'b1;

		tx_busy <= 1'b0;
		tx_counter <= 0;
		tx_bit_counter <= 0;
	end else begin
		if (tx_start && !tx_busy) begin
			// start bit + data + stop bit
			tx_shiftreg <= {1'b1, tx_data, 1'b0};
			tx_busy <= 1'b1;
			tx_bit_counter <= 0;
			tx_counter <= 0;
		end else if (tx_busy) begin
			if (tx_counter == BAUDCOUNT-1) begin
				tx_shiftreg <= {1'b1, tx_shiftreg[9:1]};
				tx <= tx_shiftreg[0];

				if (tx_bit_counter == 9) begin
					tx <= 1'b1;
					tx_busy <= 1'b0;
				end

				tx_counter <= 0;
				tx_bit_counter <= tx_bit_counter + 4'h1;
			end else begin
				tx_counter <= tx_counter + 16'h1;
			end
		end
	end
end

// UART RX
reg rx_s0, rx_s1;
wire rx_s = rx_s1;

reg [15:0] rx_counter;
reg [3:0] rx_bit;
reg [7:0] rx_shiftreg;
reg rx_busy;
reg rx_d;
reg [3:0] esc_state;
reg ser_sending_d;

always @(posedge clk) begin
	rx_s0 <= rx;
	rx_s1 <= rx_s0;

	if (!reset_n) begin
		rx_busy <= 0;
		rx_counter <= 0;
		rx_bit <= 0;
		rx_valid <= 0;
		rx_d <= 1;
		esc_state <= 0;
		ser_sending_d <= 0;
	end else begin
		ser_sending_d <= ser_sending;
		if (ser_sending & ~ser_sending_d) begin
			rx_valid <= 0;
		end

		rx_d <= rx_s;

		if (!rx_busy) begin
			// falling edge
			if (rx_d && !rx_s) begin
				rx_busy <= 1;
				rx_counter <= (16'd3*BAUDCOUNT)/16'd2 - 16'd1;
				rx_bit <= 0;
			end
		end else begin
			if (rx_counter == 0) begin
				rx_counter <= BAUDCOUNT - 16'd1;

				if (rx_bit < 8) begin
					rx_shiftreg[rx_bit] <= rx_s;
					rx_bit <= rx_bit + 4'h1;
				end else begin
					rx_busy  <= 0;

					// Convert some escape sequences from linux terminal.
					if (esc_state == 0) begin
						if (rx_shiftreg == 8'h1B) begin
							esc_state <= 1;
						end else begin
							if (rx_shiftreg == 8'h0d) begin
								rx_data  <= 8'h0a;
							end else begin
								rx_data  <= rx_shiftreg;
							end
							rx_valid <= 1;
						end
					end

					if (esc_state == 1) begin
						if (rx_shiftreg == 8'h5B) begin
							esc_state <= 2;
						end else begin
							esc_state <= 0;
						end
					end
					if (esc_state == 2) begin
						esc_state <= 0;
						case (rx_shiftreg)
							8'h41: begin
								rx_data <= 8'hF7; // UP
								rx_valid <= 1;
							end
							8'h42: begin
								rx_data <= 8'hFB; // DOWN
								rx_valid <= 1;
							end
							8'h43: begin
								rx_data <= 8'hFE; // RIGHT
								rx_valid <= 1;
							end
							8'h44: begin
								rx_data <= 8'hFD; // LEFT
								rx_valid <= 1;
							end
							8'h48: begin
								rx_data <= 8'hBF; // HOME
								rx_valid <= 1;
							end
							8'h46: begin
								rx_data <= 8'h7F; // END
								rx_valid <= 1;
							end
							8'h35: begin
								rx_data <= 8'hEF; // PAGE UP
								rx_valid <= 1;
								esc_state <= 3;
							end
							8'h36: begin
								rx_data <= 8'hDF; // PAGE DOWN
								rx_valid <= 1;
								esc_state <= 3;
							end
							8'h33: begin
								rx_data <= 8'h7F; // DELETE
								rx_valid <= 1;
								esc_state <= 3;
							end
						endcase
					end
					if (esc_state == 3) begin
						esc_state <= 0;
					end

				end
			end else begin
				rx_counter <= rx_counter - 4'h1;
			end
		end
	end
end

endmodule
