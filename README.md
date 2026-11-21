# Tang-Nano9k-CHIP-8-Game-Console

A CHIP-8 game console written in Verilog on a Sipeed Tang Nano 9K FPGA (Gowin GW1NR-9). It has its own CPU core, a 4x4 keypad scanner, and HDMI output, and it runs Pong, Snake and Tetris on a TV.

## Features

- CHIP-8 CPU in Verilog: 4 KB RAM, multi-state fetch/decode/execute FSM, delay and sound timers
- 64x32 framebuffer shown at 800x480 over HDMI (29.7 MHz pixel clock)
- Clock-enable speed limiter: CPU runs at 4 kHz in the 29.7 MHz clock domain
- 4x4 membrane keypad scanner (row/column scan at 1 kHz) mapped to the CHIP-8 hex keypad
- Boots from the FPGA's on-chip flash, no PC needed
- Instruction groups verified with Icarus Verilog testbenches

## Hardware

- Sipeed Tang Nano 9K
- 4x4 membrane keypad (8 wires) on header pins 25 to 30, 33 and 34
- HDMI cable to a TV (DVI-style output, no audio)

## Architecture

~~~
keypad -> keyboardScan.v -> buttons[15:0]
                                 |
                                 v
                 Main.v (chip8_core: CPU + RAM + timers)
                                 |
                                 v
                          framebuffer (64x32)
                                 |
                                 v
                   chip8_vout -> HDMI/TMDS encoder -> TV
~~~

Source files: `Main.v` (module `chip8_core`), `CPU.v`, `RAM.v`, `Graphics.v` (framebuffer), `Key.v`, `Timers.v`, `keyboardScan.v`, `chip8_vout.v`, `top.v`, and the HDMI files in `src/hdmi`. A proper block diagram is coming.

## Controls

CHIP-8 keys map to the keypad by position, using the standard layout:

~~~
1 2 3 C
4 5 6 D
7 8 9 E
A 0 B F
~~~

- Pong: 1 and 4 (left paddle), C and D (right paddle)
- Snake (Mato8): 2 up, 8 down, 4 left, 6 right
- Tetris: 5 rotate, 4 and 6 move, 7 drop

## Building

1. Open the project in Gowin EDA V1.9.11.03
2. Set the language to SystemVerilog 2017 (Project > Configuration > Synthesize)
3. Put the ROM you want in `rom.hex` (one byte per line, loaded at 0x200)
4. Synthesize, Place & Route, then program with Gowin Programmer (SRAM mode to test, embedded flash to keep)

## What I wrote and what I used

- Written by me: the CHIP-8 CPU, RAM, framebuffer, timers, clock-enable logic, keypad scanner, and the CHIP-8 video module
- Adapted from open source: the HDMI/TMDS video pipeline, which is the SVO library (originally by Clifford Wolf, ISC license) as used in Sipeed's Tang Nano 9K HDMI example: https://github.com/sipeed/TangNano-9K-example. I integrated it and retuned the PLL and video mode to 800x480. The license headers are kept in those files.

## ROMs

`rom.hex` holds whichever game I last loaded, and `rom_box.hex` is a small test sprite program I wrote. The games come from public CHIP-8 collections, and I have not verified every license:

- Pong: classic CHIP-8 game collection
- Mato8 (Snake): nortti, via the chip8Archive
- Tetris: Fran Dachille

## Status and roadmap

- Working: Pong, Snake and Tetris on hardware with the keypad
- Next: Timendus test ROMs, sprite wrap/clip quirk, sound output, demo video

## License

MIT for my code. Third-party code keeps its own license.
