`timescale 1ns/1ps

module tb_keypad;

    // small numbers so the sim is fast: DIV = 40/4 = 10 clocks per row step
    localparam CLK_HZ  = 40;
    localparam STEP_HZ = 4;
    localparam DIV     = CLK_HZ / STEP_HZ;

    reg         clk = 0;
    reg  [15:0] pressed = 16'd0;   // bit r*4+c = key at row r, col c is held down
    wire [3:0]  row;
    wire [3:0]  col;
    wire [15:0] buttons;

    keypad_scan #(.CLK_HZ(CLK_HZ), .STEP_HZ(STEP_HZ)) dut (
        .clk(clk), .col(col), .row(row), .buttons(buttons)
    );

    always #5 clk = ~clk;

    // fake keypad: a column reads low only if a pressed key sits in
    // the row that is currently being driven low
    reg [3:0] colv;
    integer r, c;
    always @* begin
        colv = 4'hF;
        for (r = 0; r < 4; r = r + 1)
            for (c = 0; c < 4; c = c + 1)
                if (pressed[r*4+c] && row[r] == 1'b0)
                    colv[c] = 1'b0;
    end
    assign col = colv;

    integer fails = 0;

    // hold the keys, wait for 2 full sweeps, compare
    task check;
        input [15:0]      p;
        input [15:0]      expected;
        input [8*24-1:0]  name;
        begin
            pressed = p;
            repeat (8*DIV) @(posedge clk);
            if (buttons === expected)
                $display("PASS  %0s", name);
            else begin
                $display("FAIL  %0s  got %b  expected %b", name, buttons, expected);
                fails = fails + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("keypad.vcd");
        $dumpvars(0, tb_keypad);

        //     pressed (raw bit)   expected (buttons bit)
        check(16'h0000,            16'h0000, "no key");
        check(16'h0020,            16'h0020, "printed 5 -> 5");
        check(16'h1000,            16'h0400, "printed * -> A");
        check(16'h0008,            16'h1000, "printed A -> C");
        check(16'h2000,            16'h0001, "printed 0 -> 0");
        check(16'h8000,            16'h8000, "printed D -> F");
        check(16'h0420,            16'h0220, "two keys: 5 and 9");
        check(16'h0000,            16'h0000, "released");

        if (fails == 0) $display("ALL TESTS PASSED");
        else            $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
