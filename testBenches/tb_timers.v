`timescale 1ns/1ps

module tb_timers;

    // CPU clock is 29.7 MHz, so one 60 Hz tick should be 495000 clocks
    localparam CLK_HZ     = 29_700_000;
    localparam TICK_CLKS  = CLK_HZ / 60;

    reg        clk = 0;
    reg        setDelayTimer = 0, setSoundTimer = 0;
    reg  [7:0] dataDelayIn = 0,  dataSoundIn = 0;
    wire [7:0] timerDelayValue, timerSoundValue;

    TimeX dut (
        .clk(clk),
        .setDelayTimer(setDelayTimer), .dataDelayIn(dataDelayIn), .timerDelayValue(timerDelayValue),
        .setSoundTimer(setSoundTimer), .dataSoundIn(dataSoundIn), .timerSoundValue(timerSoundValue)
    );

    always #5 clk = ~clk;

    integer fails = 0;
    integer cycles = 0;
    always @(posedge clk) cycles <= cycles + 1;

    task expect8;
        input [7:0] got;
        input [7:0] want;
        input [8*32-1:0] name;
        begin
            if (got === want) $display("PASS  %0s", name);
            else begin
                $display("FAIL  %0s  got %0d  expected %0d", name, got, want);
                fails = fails + 1;
            end
        end
    endtask

    integer t_a, t_b;

    initial begin
        $dumpfile("timers.vcd");
        $dumpvars(0, tb_timers);

        repeat (4) @(posedge clk);

        // 1. CPU write lands on the next clock edge (delay and sound are independent)
        @(negedge clk); dataDelayIn = 8'd2; setDelayTimer = 1;
                        dataSoundIn = 8'd9; setSoundTimer = 1;
        @(negedge clk); setDelayTimer = 0; setSoundTimer = 0;
        expect8(timerDelayValue, 8'd2, "delay timer loads");
        expect8(timerSoundValue, 8'd9, "sound timer loads");

        // 2. Measure the gap between two decrements: must be one 60 Hz period
        @(timerDelayValue);              // first decrement (2 -> 1)
        t_a = cycles;
        @(timerDelayValue);              // second decrement (1 -> 0)
        t_b = cycles;
        if (t_b - t_a == TICK_CLKS) $display("PASS  tick period is %0d clocks (60 Hz)", TICK_CLKS);
        else begin
            $display("FAIL  tick period is %0d clocks, expected %0d  (that is %0d Hz at 29.7 MHz)",
                     t_b - t_a, TICK_CLKS, CLK_HZ / (t_b - t_a));
            fails = fails + 1;
        end
        expect8(timerDelayValue, 8'd0, "delay reaches 0");

        // 3. Timer stops at 0 instead of wrapping
        repeat (TICK_CLKS + 100) @(posedge clk);
        expect8(timerDelayValue, 8'd0, "delay stays at 0");

        // 4. A write beats a tick that happens on the same clock
        @(negedge clk); dataDelayIn = 8'd50; setDelayTimer = 1;
        @(negedge clk); setDelayTimer = 0;
        expect8(timerDelayValue, 8'd50, "write overrides tick");

        if (fails == 0) $display("ALL TESTS PASSED");
        else            $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
