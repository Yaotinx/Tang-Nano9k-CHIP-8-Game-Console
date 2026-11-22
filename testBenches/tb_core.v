`timescale 1ns/1ps

// Whole-core test: checks the clock enable, then runs a small program
// through the real CPU, RAM, timers and framebuffer.
module tb_core;

    reg         clk = 0;
    reg  [15:0] buttons = 16'd0;
    reg  [4:0]  read_row_y = 0;
    wire [63:0] screen_row_data;

    chip8_core dut (.clk(clk), .buttons(buttons),
                    .read_row_y(read_row_y), .screen_row_data(screen_row_data));

    always #5 clk = ~clk;

    integer fails = 0;
    integer cycles = 0;
    always @(posedge clk) cycles <= cycles + 1;

    task expect_eq;
        input [63:0] got;
        input [63:0] want;
        input [8*32-1:0] name;
        begin
            if (got === want) $display("PASS  %0s", name);
            else begin
                $display("FAIL  %0s  got %h  expected %h", name, got, want);
                fails = fails + 1;
            end
        end
    endtask

    // write one 16-bit instruction into RAM at address a
    task put;
        input [11:0] a;
        input [15:0] w;
        begin
            dut.mod_ram.memory[a]     = w[15:8];
            dut.mod_ram.memory[a + 1] = w[7:0];
        end
    endtask

    integer t0, t1, t2;

    initial begin
        $dumpfile("core.vcd");
        $dumpvars(0, tb_core);

        // ---- test program (loaded after RAM's own initial block ran) ----
        #1;
        put(12'h200, 16'h00E0);  // clear screen
        put(12'h202, 16'h6005);  // V0 = 5
        put(12'h204, 16'h6103);  // V1 = 3
        put(12'h206, 16'h8014);  // V0 += V1        -> 8, VF = 0
        put(12'h208, 16'h62FF);  // V2 = FF
        put(12'h20A, 16'h7202);  // V2 += 2         -> 01
        put(12'h20C, 16'h8105);  // V1 -= V0        -> FB, VF = 0 (borrow)
        put(12'h20E, 16'hA300);  // I = 0x300
        put(12'h210, 16'h637B);  // V3 = 123
        put(12'h212, 16'hF333);  // BCD of V3 -> mem[300..302] = 1,2,3
        put(12'h214, 16'hF265);  // load V0..V2 from mem[300..]
        put(12'h216, 16'h6500);  // V5 = 0
        put(12'h218, 16'h6400);  // V4 = 0
        put(12'h21A, 16'hF529);  // I = font sprite for digit V5
        put(12'h21C, 16'hD455);  // draw 5 rows at (V4, V5)
        put(12'h21E, 16'h66FF);  // V6 = FF
        put(12'h220, 16'h6702);  // V7 = 02
        put(12'h222, 16'h8674);  // V6 += V7        -> 01, VF = 1 (carry)
        put(12'h224, 16'h1224);  // loop here forever

        // ---- 1. clock enable: one clock wide, every 7425 clocks ----
        @(posedge dut.ce); t0 = cycles;
        @(negedge dut.ce);  t1 = cycles;
        if (t1 - t0 == 1) $display("PASS  ce is high for exactly one clock");
        else begin $display("FAIL  ce pulse width is %0d clocks", t1 - t0); fails = fails + 1; end
        @(posedge dut.ce); t2 = cycles;
        if (t2 - t0 == 7425) $display("PASS  ce period is 7425 clocks (4000 Hz)");
        else begin $display("FAIL  ce period is %0d clocks, expected 7425", t2 - t0); fails = fails + 1; end

        // ---- 2. run the program until it reaches the loop ----
        fork
            begin : run
                wait (dut.mod_cpu.pcRegister == 16'h226);
                repeat (10) @(posedge dut.ce);
                disable watchdog;
            end
            begin : watchdog
                repeat (400) @(posedge dut.ce);
                $display("FAIL  program never reached the end loop (pc = %h)", dut.mod_cpu.pcRegister);
                fails = fails + 1;
                disable run;
            end
        join

        expect_eq(dut.mod_cpu.generalRegister[0], 8'h01, "V0 = 1   (loaded by F265)");
        expect_eq(dut.mod_cpu.generalRegister[1], 8'h02, "V1 = 2   (loaded by F265)");
        expect_eq(dut.mod_cpu.generalRegister[2], 8'h03, "V2 = 3   (loaded by F265)");
        expect_eq(dut.mod_cpu.generalRegister[3], 8'h7B, "V3 = 7B  (6XNN)");
        expect_eq(dut.mod_cpu.generalRegister[6], 8'h01, "V6 = 1   (FF + 2 wraps)");
        expect_eq(dut.mod_cpu.generalRegister[15], 8'h01, "VF = 1  (8XY4 carry)");
        expect_eq(dut.mod_ram.memory[12'h300], 8'h01, "BCD hundreds");
        expect_eq(dut.mod_ram.memory[12'h301], 8'h02, "BCD tens");
        expect_eq(dut.mod_ram.memory[12'h302], 8'h03, "BCD ones");
        expect_eq(dut.mod_cpu.indexRegister,   16'h0050, "I = 0x050 (F029)");

        // font sprite for 0 is F0 90 90 90 F0, drawn at the top left
        read_row_y = 0; #1; expect_eq(screen_row_data, 64'hF000_0000_0000_0000, "digit 0 row 0");
        read_row_y = 1; #1; expect_eq(screen_row_data, 64'h9000_0000_0000_0000, "digit 0 row 1");
        read_row_y = 2; #1; expect_eq(screen_row_data, 64'h9000_0000_0000_0000, "digit 0 row 2");
        read_row_y = 3; #1; expect_eq(screen_row_data, 64'h9000_0000_0000_0000, "digit 0 row 3");
        read_row_y = 4; #1; expect_eq(screen_row_data, 64'hF000_0000_0000_0000, "digit 0 row 4");
        read_row_y = 5; #1; expect_eq(screen_row_data, 64'h0, "row 5 untouched");

        if (fails == 0) $display("ALL TESTS PASSED");
        else            $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
