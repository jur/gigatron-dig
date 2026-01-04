module keycontroller(
	input wire CLOCK_50,
	input wire clk1,
	input wire clk2,
	input wire reset_n,

	// Buttons
	input wire [3:0] KEY,
	input wire [1:0] SW,

	// Output key codes
	output reg [7:0] key_data);

always @(posedge CLOCK_50)
begin
	key_data[7:0] <= 8'hff;

	case (SW[1:0])
		2'b00: begin
			key_data[3:2] <= KEY[3:2];
		end

		2'b01: begin
			key_data[1:0] <= KEY[3:2];
		end

		2'b10: begin
			key_data[5:4] <= KEY[3:2];
		end

		2'b11: begin
			key_data[7:6] <= KEY[3:2];
		end
	endcase

	key_data[7] <= KEY[1];
end

endmodule
