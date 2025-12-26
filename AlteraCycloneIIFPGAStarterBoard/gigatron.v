module gigatron(
	input wire CLOCK_50,
	output wire [3:0] VGA_R,
	output wire [3:0] VGA_G,
	output wire [3:0] VGA_B,
	output wire VGA_HS,
	output wire VGA_VS,
	output wire [7:0] LEDG,
	inout reg [15:0] SRAM_DQ,
	output wire [17:0] SRAM_ADDR,
	output wire SRAM_UB_N,
	output wire SRAM_LB_N,
	output wire SRAM_WE_N,
	output wire SRAM_CE_N,
	output wire SRAM_OE_N,
	inout reg [7:0] FL_DQ,
	output reg [21:0] FL_ADDR,
	output wire FL_WE_N,
	output wire FL_RST_N,
	output wire FL_OE_N,
	output wire FL_CE_N,
	output wire [6:0] HEX0,
	output wire [6:0] HEX1,
	output wire [6:0] HEX2,
	output wire [6:0] HEX3,
	input wire [9:0] SW,
	input wire [3:0] KEY,
	output reg [9:0] LEDR);

// Reset
reg reset_n;
initial reset_n = 0;

// Clock
reg clk1, clk2;
reg [1:0] clk_counter;

initial begin
	clk_counter = 0;
	clk1 = 0;
	clk2 = 0;
	CLKCOUNTER = 0;
end

reg [26:0] CLKCOUNTER;
reg SYSCLK;

always @(posedge CLOCK_50)
begin
	CLKCOUNTER <= CLKCOUNTER + 26'h1;
	if (SW[8:5] == 0) begin
		// ~1 Hz clock
		SYSCLK <= CLKCOUNTER[23];
	end else begin
		// Configure clock speed via SW[8:5].
		if (CLKCOUNTER > SW[8:5]) begin
			SYSCLK = 0;
			CLKCOUNTER <= 0;
		end else if (CLKCOUNTER == SW[8:5]) begin
			SYSCLK = 1;
		end else begin
			SYSCLK = 0;
		end
	end
end

always @(posedge SYSCLK)
begin
	// Switch SW[9] starts/stops the clock (cpu).
	if (SW[9]) begin
		if ((clk_counter != 3) || (insn_rdy == 1)) begin
			clk_counter <= clk_counter + 2'b01;
		end
	end
	if (reset_n == 1'b0) begin
		if (clk_counter == 3) begin
			reset_n <= 1;
		end else begin
			reset_n <= 0;
		end
	end else begin
		case (clk_counter)
			2'b00:
				begin
					clk1 <= 1'b1;
					clk2 <= 1'b0;
					sram_we_clk_n <= 1'b0;
				end
			2'b01:
				begin
					clk1 <= 1'b0;
					clk2 <= 1'b0;
					sram_we_clk_n <= 1'b0;
				end
			2'b10:
				begin
					clk1 <= 1'b0;
					clk2 <= 1'b1;
					sram_we_clk_n <= 1'b1;
				end
			2'b11:
				begin
					clk1 <= 1'b0;
					clk2 <= 1'b0;
					sram_we_clk_n <= 1'b1;
				end
		endcase
	end
end

// ROM
//reg [15:0] romdata[65536];
//reg [15:0] romdata[64];
//initial begin
//	$readmemh("ROMv6.hex", romdata);
//end

//assign insn = romdata[romaddr];

// Flash ROM
// This expects that ROMv6.rom from https://github.com/kervinck/gigatron-rom.git is in Flash ROM.
// When CII_Starter_USB_API.pof or CII_Starter_USB_API.sof is running on the FPGA, the program
// CII_Starter_Kit_Control_Panel.exe can update the flash. The USB Blaster driver needs to be installed first.
reg insn_rdy;
reg [1:0] rom_counter;

assign FL_CE_N = 0; // chip select
assign FL_WE_N = 1; // do not write
assign FL_OE_N = 0; // read
assign FL_RST_N = reset_n; // reset

wire [15:0] romaddr;
reg [15:0] insn;
initial begin
	insn = 16'h0;
	insn_rdy = 0;
	FL_ADDR = 22'h0;
	rom_counter = 0;
end

// The flash has only 8 data lines, but gigatron expects that the ROM has 16.
// Therefore the ROM data is read in several cycles (rom_counter).
// gigatroncpu expects a valid insn at clk1 which is clk_counter=0.
// The cycle before (i.e. clk_counter=3) is delayed until ROM data is ready, this is signaled via insn_rdy.
// The VGA timing will be bad, because of that delay.
always @(posedge SYSCLK)
begin
	if (clk_counter == 3) begin
		if (insn_rdy == 0) begin
			rom_counter <= rom_counter + 1;
			case (rom_counter)
				0:
					begin
						FL_ADDR[17] = 0;
						FL_ADDR[16:1] <= romaddr;
						FL_ADDR[0] <= 0;
						insn <= 0;
					end
				1:
					begin
						insn[7:0] <= FL_DQ[7:0];
						FL_ADDR[0] <= 1;
					end
				2:
					begin
						insn[15:8] <= FL_DQ[7:0];
						//romdata[romaddr] <= insn;
						insn_rdy <= 1;
					end
			endcase
		end
	end else if (clk_counter == 1) begin
		// ROM data must be valid until clk1 is low. Then we can reset the values:
		insn <= 16'h0;
		FL_ADDR <= 22'h0;
		insn_rdy <= 0;
		rom_counter <= 0;
	end
end

// Famiclone controller lines
reg SER_DATA = 0;
wire SER_PULSE;
wire SER_LATCH;

initial SER_DATA = 0;

// SRAM
reg [7:0] gigatron_sram_read_data;
wire [7:0] gigatron_sram_write_data;
wire gigatron_sram_oe_n;
wire gigatron_sram_we_n;
reg sram_we_clk_n;

wire sram_we_n;
assign sram_we_n = sram_we_clk_n | gigatron_sram_we_n;

assign SRAM_CE_N = 0; // chip select
assign SRAM_LB_N = 0; // use lower byte
assign SRAM_UB_N = 0; // high byte not used.
assign SRAM_OE_N = gigatron_sram_oe_n | ~sram_we_n;
assign SRAM_WE_N = sram_we_n | ~gigatron_sram_oe_n;

initial begin
	sram_we_clk_n = 1'b1;
end

always @(*)
begin
	if (!SRAM_OE_N) begin
		gigatron_sram_read_data = SRAM_DQ[7:0];
	end else begin
		gigatron_sram_read_data = 8'bzzzzzzzz;
	end
	if (!SRAM_WE_N) begin
		SRAM_DQ[7:0] = gigatron_sram_write_data;
	end else begin
		SRAM_DQ[7:0] = 8'bzzzzzzzz;
	end
	SRAM_DQ[15:8] = 8'bzzzzzzzz;
end

// EXOUT
wire [7:0] EXOUT;
assign LEDG = EXOUT;

// Debug Output
wire [7:0] RegIR; // Instruction Register Value
wire [7:0] RegDR; // Data Register Value
wire [7:0] RegAccu; // Accumulator Register Value
wire [7:0] RegX; // X Register Value
wire [7:0] RegY; // Y Register Value
wire [7:0] RegOUT; // OUT Register Value
wire [7:0] BUSValue; // Value on internal BUS.
wire [7:0] ALUValue; // Current value calculated by ALU.
wire [7:0] Input; // Input data read from gamepad (for debugging).
wire IE_N; // Control line for reading data from gamepad (for debugging).

reg [15:0] dbgval;
initial begin
	dbgval = 16'hDEAD;
end

// 7 segment LEDs display debug infromation, selected via switches (SW[3:0])
segment7 seg0(.HEXLED(HEX0), .VALUE(dbgval[3:0]), .CLK(CLOCK_50));
segment7 seg1(.HEXLED(HEX1), .VALUE(dbgval[7:4]), .CLK(CLOCK_50));
segment7 seg2(.HEXLED(HEX2), .VALUE(dbgval[11:8]), .CLK(CLOCK_50));
segment7 seg3(.HEXLED(HEX3), .VALUE(dbgval[15:12]), .CLK(CLOCK_50));

always @(posedge CLOCK_50)
begin
	LEDR <= SW;
	case (SW[3:0])
		4'b0000: dbgval <= romaddr;
		4'b0001: dbgval <= insn;
		4'b0010: begin
			dbgval[15:8] <= RegIR;
			dbgval[7:0] <= RegDR;
		end
		4'b0011: begin
			dbgval[15:8] <= 0;
			dbgval[7:0] <= RegAccu;
		end
		4'b0100: begin
			dbgval[15:8] <= 0;
			dbgval[7:0] <= RegX;
		end
		4'b0101: begin
			dbgval[15:8] <= 0;
			dbgval[7:0] <= RegY;
		end
		4'b0110: begin
			dbgval[15:8] <= 0;
			dbgval[7:0] <= RegOUT;
		end
		4'b0111: begin
			dbgval[15:8] <= 0;
			dbgval[7:0] <= BUSValue;
		end
		4'b1000: begin
			dbgval[15:8] = 0;
			dbgval[7:0] = ALUValue;
		end
		4'b1001: begin
			dbgval[15:7] <= 0;
			dbgval[8] <= IE_N;
			dbgval[7:0] <= Input;
		end
		4'b1010: begin
			if (SRAM_ADDR < 18'h10000) begin
				dbgval <= SRAM_ADDR[15:0];
			end else begin
				dbgval <= 16'hdead;
			end
		end
		4'b1011: begin
			dbgval <= SRAM_DQ;
		end
		4'b1100: begin
			dbgval <= EXOUT;
		end
		4'b1101: begin
			dbgval[0] <= SRAM_OE_N;
			dbgval[1] <= gigatron_sram_oe_n;
			dbgval[7:2] <= 0;
			dbgval[8] <= SRAM_WE_N;
			dbgval[9] <= gigatron_sram_we_n;
			dbgval[15:10] <= 0;
		end
		4'b1110: begin
			dbgval[0] <= reset_n;
			dbgval[1] <= clk1;
			dbgval[2] <= clk2;
			dbgval[7:3] <= 0;
			dbgval[15:8] <= clk_counter;
		end
		4'b1111: begin
			dbgval[3:0] <= rom_counter;
			dbgval[7:4] <= insn_rdy;
		end
		default: dbgval <= 16'hDEAD;

	endcase
end

// CPU (imported from Digital)
gigatroncpu cpu(
	// Clock
	clk1,
	clk2,
	
	// Reset
	reset_n,
	
	// ROM
	insn,
	
	// SRAM
	gigatron_sram_read_data,
	
	// Controller
	SER_DATA,
	
	// ROM
	romaddr,
	
	// Output
	EXOUT,
	
	// SRAM
	SRAM_ADDR,
	gigatron_sram_write_data,
	gigatron_sram_oe_n,
	gigatron_sram_we_n,
	
	// VGA
	VGA_R,
	VGA_G,
	VGA_B,
	VGA_HS,
	VGA_VS,
	
	// Controller
	SER_PULSE,
	SER_LATCH,
	
	// Debug
	RegIR,
	RegDR,
	RegAccu,
	RegX,
	RegY,
	RegOUT,
	BUSValue,
	ALUValue,
	Input,
	IE_N
);

endmodule
