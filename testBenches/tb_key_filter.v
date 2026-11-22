`timescale 1ns/1ps

// Tests Key.v (module "keypad"): the 1 ms tick filter between
// keypad_scan and the CPU.
module tb_key_filter;

    reg         clk = 0;
    reg  [15:0] buttons = 16'd0;
    wire [15:0] keys;

    keypad dut (.clk(clk), .buttons(buttons), .keys(keys));

    always #5 clk = ~clk;

    localparam TICK = 27001;     // clocks between filter ticks in Key.v

    integer fails = 0;

    task expect16;
        input [15:0] got;
        input [15:0] want;
        input [8*32-1:0] name;
        begin
            if (got === want) $display("PASS  %0s", name);
            else begin
                $display("FAIL  %0s  got %b  expected %b", name, got, want);
                fails = fails + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("keyfilter.vcd");
        $dumpvars(0, tb_key_filter);

        // let the filter flush out its startup values
        repeat (5*TICK) @(posedge clk);
        expect16(keys, 16'h0000, "idle: no keys");

        // a held key shows up after a few ticks
        buttons = 16'h0020;
        repeat (4*TICK) @(posedge clk);
        expect16(keys, 16'h0020, "held key 5 appears");

        // two keys together
        buttons = 16'h0420;
        repeat (4*TICK) @(posedge clk);
        expect16(keys, 16'h0420, "keys 5 and 10 together");

        // release
        buttons = 16'h0000;
        repeat (4*TICK) @(posedge clk);
        expect16(keys, 16'h0000, "release clears keys");

        // a very short glitch (well under one tick) must not get through
        // (starts right after a tick, ends well before the next)
        @(posedge dut.tick);
        repeat (50) @(posedge clk);
        buttons = 16'h0008;
        repeat (50) @(posedge clk);
        buttons = 16'h0000;
        repeat (4*TICK) @(posedge clk);
        expect16(keys, 16'h0000, "short glitch is filtered");

        if (fails == 0) $display("ALL TESTS PASSED");
        else            $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
