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
	output reg [9:0] LEDR,

	// SDRAM
	inout wire [15:0] DRAM_DQ,
	output wire [11:0] DRAM_ADDR,
	output wire DRAM_LDQM,
	output wire DRAM_UDQM,
	output wire DRAM_WE_N,
	output wire DRAM_CAS_N,
	output wire DRAM_RAS_N,
	output wire DRAM_CS_N,
	output wire DRAM_BA_0,
	output wire DRAM_BA_1,
	output wire DRAM_CLK,
	output wire DRAM_CKE,

	// PS/2
	input wire PS2_CLK,
	input wire PS2_DAT);

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
			rom_counter <= rom_counter + 2'h1;
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
wire SER_PULSE;
wire SER_LATCH;
reg SER_DATA;

reg [7:0] gamepad_data;
reg ps2_sending;
reg [2:0] gamepad_bit;

reg ser_latch_s0;
reg ser_latch_s1;
reg ser_pulse_s0;
reg ser_pulse_s1;

wire ser_latch_rise = ser_latch_s0 & ~ser_latch_s1;
wire ser_pulse_rise = ser_pulse_s0 & ~ser_pulse_s1;

always @(posedge CLOCK_50)
begin
	SER_DATA <= gamepad_data[gamepad_bit];

	if (!reset_n) begin
		ser_latch_s0 <= 1'b0;
		ser_latch_s1 <= 1'b0;
		ser_pulse_s0 <= 1'b0;
		ser_pulse_s1 <= 1'b0;
		gamepad_data = 8'hFF;
		ps2_sending = 1'b0;
		gamepad_bit = 3'h0;
	end else begin
		if (ser_latch_rise) begin
			gamepad_bit <= 3'h0;
			if (ps2_ready) begin
				gamepad_data <= ps2_data;
				ps2_sending <= 1'b1;
			end else begin
				gamepad_data <= key_data;
			end
		end else if (ser_pulse_rise) begin
			if (gamepad_bit == 4'h0) begin
				ps2_sending <= 1'b0;
			end

			gamepad_bit <= gamepad_bit - 3'h1;
		end

		ser_latch_s0 <= SER_LATCH;
		ser_latch_s1 <= ser_latch_s0;
		ser_pulse_s0 <= SER_PULSE;
		ser_pulse_s1 <= ser_pulse_s0;
	end
end

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

// Key Controller
wire [7:0] key_data;

keycontroller keyctrl(
	CLOCK_50,
	clk1,
	clk2,
	reset_n,

	// Buttons
	KEY,
	SW[1:0],

	// Output key codes
	key_data);

// PS2 Controller
wire [7:0] ps2_data;
wire ps2_ready;
wire [15:0] ps2_dbg;

ps2controller ps2ctrl(
	CLOCK_50,
	clk1,
	clk2,
	reset_n,

	// Debug
	SW[2:0],
	ps2_dbg,

	// PS/2
	PS2_CLK,
	PS2_DAT,

	// Output key codes
	ps2_data,
	ps2_ready,

	// Ack
	ps2_sending);

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

reg [7:0] InputReg;

always @(posedge clk2)
begin
	if (!IE_N) begin
		InputReg <= Input;
	end
end

reg [15:0] dbgval;
wire [15:0] dbgvga;

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
	case (SW[4:0])
		5'b00000: begin
			dbgval <= romaddr;
		end
		5'b00001: dbgval <= insn;
		5'b00010: begin
			dbgval[15:8] <= RegIR;
			dbgval[7:0] <= RegDR;
		end
		5'b00011: begin
			dbgval[15:8] <= 0;
			dbgval[7:0] <= RegAccu;
		end
		5'b00100: begin
			dbgval[15:8] <= 0;
			dbgval[7:0] <= RegX;
		end
		5'b00101: begin
			dbgval[15:8] <= 0;
			dbgval[7:0] <= RegY;
		end
		5'b00110: begin
			dbgval[15:8] <= 0;
			dbgval[7:0] <= RegOUT;
		end
		5'b00111: begin
			dbgval[15:8] <= 0;
			dbgval[7:0] <= BUSValue;
		end
		5'b01000: begin
			dbgval[15:8] = 0;
			dbgval[7:0] = ALUValue;
		end
		5'b01001: begin
			dbgval[15:8] <= gamepad_data;
			dbgval[7:0] <= InputReg;
		end
		5'b01010: begin
			if (SRAM_ADDR < 18'h10000) begin
				dbgval <= SRAM_ADDR[15:0];
			end else begin
				dbgval <= 16'hdead;
			end
		end
		5'b01011: begin
			dbgval <= SRAM_DQ;
		end
		5'b01100: begin
			dbgval <= EXOUT;
		end
		5'b01101: begin
			dbgval[0] <= SRAM_OE_N;
			dbgval[1] <= gigatron_sram_oe_n;
			dbgval[7:2] <= 0;
			dbgval[8] <= SRAM_WE_N;
			dbgval[9] <= gigatron_sram_we_n;
			dbgval[15:10] <= 0;
		end
		5'b01110: begin
			dbgval[0] <= reset_n;
			dbgval[1] <= clk1;
			dbgval[2] <= clk2;
			dbgval[7:3] <= 0;
			dbgval[15:8] <= clk_counter;
		end
		5'b01111: begin
			dbgval[3:0] <= rom_counter;
			dbgval[7:4] <= insn_rdy;
		end
		5'b10000: begin
			dbgval <= dbgvga;
		end
		5'b10001: begin
			dbgval <= dbgvga;
		end
		5'b10010: begin
			dbgval <= dbgvga;
		end
		5'b10011: begin
			dbgval <= dbgvga;
		end
		5'b10100: begin
			dbgval <= dbgvga;
		end
		5'b10101: begin
			dbgval <= dbgvga;
		end
		5'b10110: begin
			dbgval <= dbgvga;
		end
		5'b10111: begin
			dbgval <= dbgvga;
		end

		5'b11000: begin
			dbgval[15:0] <= ps2_dbg;
		end
		5'b11001: begin
			dbgval[15:0] <= ps2_dbg;
		end

		5'b11010: begin
			dbgval[15:0] <= ps2_dbg;
		end

		5'b11011: begin
			dbgval[15:0] <= ps2_dbg;
		end

		5'b11100: begin
			dbgval[15:0] <= ps2_dbg;
		end

		5'b11101: begin
			dbgval[15:0] <= ps2_dbg;
		end

		5'b11110: begin
			dbgval[15:0] <= ps2_dbg;
		end

		5'b11111: begin
			dbgval[15:0] <= ps2_dbg;
		end

		default: dbgval <= 16'hDEAD;

	endcase
end

// CPU (imported from Digital)
wire [3:0] gigatron_vga_r;
wire [3:0] gigatron_vga_g;
wire [3:0] gigatron_vga_b;
wire gigatron_vga_hs;
wire gigatron_vga_vs;

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
	gigatron_vga_r,
	gigatron_vga_g,
	gigatron_vga_b,
	gigatron_vga_hs,
	gigatron_vga_vs,

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

// SDRAM
wire [1:0] bank_addr;

assign DRAM_BA_1 = bank_addr[1];
assign DRAM_BA_0 = bank_addr[0];

wire [21:0] wr_addr;
wire [15:0] wr_data;
wire wr_enable;

wire [21:0] rd_addr;
wire [15:0] rd_data;
wire rd_ready;
wire rd_enable;

wire busy;
wire clk;

assign clk = CLOCK_50;
assign DRAM_CLK = CLOCK_50;

sdram_controller sdram(
	 /* HOST INTERFACE */
    .wr_addr(wr_addr),
    .wr_data(wr_data),
    .wr_enable(wr_enable),

    .rd_addr(rd_addr),
    .rd_data(rd_data),
    .rd_ready(rd_ready),
    .rd_enable(rd_enable),

    .busy(busy),
	 .rst_n(reset_n),
	 .clk(clk),

    /* SDRAM SIDE */
    .addr(DRAM_ADDR),
	 .bank_addr(bank_addr),
	 .data(DRAM_DQ),
	 .clock_enable(DRAM_CKE),
	 .cs_n(DRAM_CS_N),
	 .ras_n(DRAM_RAS_N),
	 .cas_n(DRAM_CAS_N),
	 .we_n(DRAM_WE_N),
    .data_mask_low(DRAM_LDQM),
	 .data_mask_high(DRAM_UDQM));

vgadrv vga(
	CLOCK_50,
	VGA_R,
	VGA_G,
	VGA_B,
	VGA_HS,
	VGA_VS,

	clk1,
	clk2,

	gigatron_vga_r,
	gigatron_vga_g,
	gigatron_vga_b,
	gigatron_vga_hs,
	gigatron_vga_vs,

	// RAM write
	wr_addr,
	wr_data,
	wr_enable,

	// RAM read
	rd_addr,
	rd_data,
	rd_ready,
	rd_enable,

	busy,

	// Debug
	dbgvga,
	SW[2:0]);

endmodule
