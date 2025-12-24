# Overview
This is an implementation of the gigatron TTL computer which is a computer based on TTL chips.
The design was based on the schematic of the gigatron, but there were some modifications needed to support simulation and verilog export.

![game](pictures/bricks.png)

# Usage
Get the program Digital and install it as described here:
[Digital at github](https://github.com/hneemann/Digital)

The simulation can be started by the following steps:
* Start the program Digital.
* Open the file gigatron.dig.
* Press play button to start the simulation.
![Play Button](pictures/tools.png)
* Click on EnableCLK. The CPU is now running and takes some time until the window with the VGA output is opened.
![EnableCLK](pictures/enableclk.png)
* You can control it via the buttons of the gamepad. Click on the SELECT button and hold for some seconds. This will change the resolution. Release the SELECT button for some seconds. Repeat that until you have more black on the screen. More black lines will make it faster.
![Gamepad](pictures/gamepad.png)
* With the buttons for UP/DOWN/LEFT/RIGHT you can select an menu entry and A will start it.
The simulation is pretty slow.

![Menu](pictures/menu.png)

# Debugging
There are some break points implemented which can be controlled via Digital.
* BreakAddr: Program pointer where to stop, this triggers already when the previous instruction is still executed. ProgramBreakEnable enables the breakpoint.
* X Reg Value: Only break at program pointer when the X register has the configued value. RegXBreakEnable enables that.
* WriteBreakAddr: Break when the configured RAM address is written.
When a breakpoint is hit, the clock should be disabled by EnableCLK. Then you can single step.
* SingleStep: First EnableCLK needs to be disabled. VGA clock is controlled by SingleStep; i.e. you need to click multiple times to get CLK1 and CLK2 changes.
After single step you can enable the clock again. SingleStep must be low.

# Tracing
There is a Trace Memory which contains each address which was executed (16 bit address). It first need to be enabled via "Trace Enable" DIP switch. The output "Trace End Address" contains the last address in "Trace Memory" which was written. You can open a memory dump by clicking on the "Trace Memory". You have to go backwards from the last address to see how it got there. The values after the end address are old, because it is a ring buffer.

# Explanation of instruction set
The gigatron has an unique instruction set which is very simple, but it is complicated to understand it and write code. It has a ROM (EEPROM) and can only execute instructions from that. This cannot be changed at runtime in real hardware (the simulator can).
The code is also responsible for bitbanging the VGA lines which makes it more complicated for software developers.
The ROM emulates a 6502 cpu. The code for the emulated 6502 cpu is stored in RAM which can be changed.

# Design Changes
There were some design changes needed to get it working in the simulation and getting verilog export working. The changes are:
* Verilog export does not support multiple sources driving the same line (e.g. BUS). The components were replaced by logic gates.
* BUS is handled via AND gates and the output is selected via control lines ~DE, ~IE, ~AE and ~OE.
 Diodes were replaced by AND gates.
* The simulated VGA output requires the pixel clock (25 MHz). All clocks are derived from that.
* CLK1 is 1/4 of the VGA clock. Same for CLK2, but with a delay.
* SRAM: ~WE depends also on CLK2. RAM is written when CLK1 goes low and CLK2 is not yet high. CLK2 high may increment the X register and the RAM address would be wrong (e.g. instruction "st $59,[y,x++]").
* Instruction "ctrl y,x" causes ~WE and ~OE to be low at the same time. This is unstable and Digital cannot calculate that. ~WE and ~OE is forced to high under that condition.
verilog export is supported via gigatroncpu.dig.

# ROM Problems
It seems that 6502 BRK instruction is not correctly implemented in ROMv6. Trace has shown that instruction at 0x10ff is executed when v6502_BRK is called. This looks like a bug in the ROM code (v6). It is not know whether this has an side effect. All 6502 instructions seem to have a problem with the branch delay slot. For v6502_SED it has most likely a side effect as Y register is modified.

# Source of Files
74138ndelay.dig is a copy of Digital/src/main/dig/lib/DIL Chips/74xx/plexers/74138.dig (git https://github.com/hneemann/Digital.git 535812dacb7c34f125f8033b37db84bdb17bda4b), but delay was removed, because this cannot be converted to verilog.
