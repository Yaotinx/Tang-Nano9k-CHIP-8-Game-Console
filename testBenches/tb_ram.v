`timescale 1ns/1ps

module tb_ram;

    reg        clk = 0;
    reg        ce = 0, WRE = 0;
    reg  [7:0] data = 0;
    reg  [11:0] address = 0;
    wire [7:0] readData;

    ram dut (.clk(clk), .ce(ce), .WRE(WRE), .data(data), .address(address), .readData(readData));

    always #5 clk = ~clk;

    integer fails = 0;

    task expect8;
        input [7:0] got;
        input [7:0] want;
        input [8*32-1:0] name;
        begin
            if (got === want) $display("PASS  %0s", name);
            else begin
                $display("FAIL  %0s  got %h  expected %h", name, got, want);
                fails = fails + 1;
            end
        end
    endtask

    // one CPU step: ce high for exactly one clock
    task step;
        begin
            @(negedge clk); ce = 1;
            @(negedge clk); ce = 0;
        end
    endtask

    initial begin
        $dumpfile("ram.vcd");
        $dumpvars(0, tb_ram);

        // 1. font was loaded at 0x050 (first byte of the 0 sprite is F0)
        address = 12'h050; WRE = 0; step;
        expect8(readData, 8'hF0, "font byte at 0x050");

        // 2. write then read back
        address = 12'h300; data = 8'hA5; WRE = 1; step;
        WRE = 0; address = 12'h300; step;
        expect8(readData, 8'hA5, "write then read");

        // 3. without ce, nothing changes: a write is ignored, readData holds
        address = 12'h301; data = 8'h11; WRE = 1;
        repeat (4) @(posedge clk);
        WRE = 0; address = 12'h300;
        repeat (4) @(posedge clk);
        expect8(readData, 8'hA5, "readData holds without ce");
        address = 12'h301; step;
        if (readData === 8'h11) begin
            $display("FAIL  write without ce was accepted"); fails = fails + 1;
        end else $display("PASS  write without ce ignored");

        // 4. read latency is exactly one step: address set, then ce, then data valid
        address = 12'h300; step;
        expect8(readData, 8'hA5, "one-step read latency");

        if (fails == 0) $display("ALL TESTS PASSED");
        else            $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
