module segment7(
	HEXLED,
	VALUE,
	CLK);

output reg [6:0] HEXLED;
input [3:0] VALUE;
input CLK;

always @(posedge CLK)
begin
	case (VALUE)
		4'h0: HEXLED <= 7'b1000000;
		4'h1: HEXLED <= 7'b1111001;
		4'h2: HEXLED <= 7'b0100100;
		4'h3: HEXLED <= 7'b0110000;
		4'h4: HEXLED <= 7'b0011001;
		4'h5: HEXLED <= 7'b0010010;
		4'h6: HEXLED <= 7'b0000010;
		4'h7: HEXLED <= 7'b1111000;
		4'h8: HEXLED <= 7'b0000000;
		4'h9: HEXLED <= 7'b0011000;
		4'ha: HEXLED <= 7'b0001000;
		4'hb: HEXLED <= 7'b0000011;
		4'hc: HEXLED <= 7'b1000110;
		4'hd: HEXLED <= 7'b0100001;
		4'he: HEXLED <= 7'b0000110;
		4'hf: HEXLED <= 7'b0001110;
	endcase
end

endmodule