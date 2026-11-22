`timescale 1ns/1ps

module tb_framebuffer;

    reg         clk = 0;
    reg         ce = 0, clear_screen = 0, draw_en = 0;
    reg  [5:0]  start_x = 0;
    reg  [4:0]  start_y = 0;
    reg  [7:0]  sprite_row_data = 0;
    reg  [3:0]  row_index = 0;
    reg  [4:0]  read_row_y = 0;
    wire        collision_flag;
    wire [63:0] screen_row_data;

    frameBuffer dut (
        .clk(clk), .ce(ce), .clear_screen(clear_screen), .draw_en(draw_en),
        .start_x(start_x), .start_y(start_y), .sprite_row_data(sprite_row_data),
        .row_index(row_index), .collision_flag(collision_flag),
        .screen_row_data(screen_row_data), .read_row_y(read_row_y)
    );

    always #5 clk = ~clk;

    integer fails = 0;

    task expect64;
        input [63:0] got;
        input [63:0] want;
        input [8*32-1:0] name;
        begin
            if (got === want) $display("PASS  %0s", name);
            else begin
                $display("FAIL  %0s\n      got      %h\n      expected %h", name, got, want);
                fails = fails + 1;
            end
        end
    endtask

    task expect1;
        input got;
        input want;
        input [8*32-1:0] name;
        begin
            if (got === want) $display("PASS  %0s", name);
            else begin
                $display("FAIL  %0s  got %b expected %b", name, got, want);
                fails = fails + 1;
            end
        end
    endtask

    task clear;
        begin
            @(negedge clk); clear_screen = 1; ce = 1;
            @(negedge clk); clear_screen = 0; ce = 0;
        end
    endtask

    // draw one sprite row: pixels `bits` at (x, y + row)
    task draw_row;
        input [5:0] x;
        input [4:0] y;
        input [3:0] row;
        input [7:0] bits;
        begin
            @(negedge clk);
            start_x = x; start_y = y; row_index = row; sprite_row_data = bits;
            draw_en = 1; ce = 1;
            @(negedge clk); draw_en = 0; ce = 0;
        end
    endtask

    task look;
        input [4:0] y;
        begin read_row_y = y; #1; end
    endtask

    initial begin
        $dumpfile("fb.vcd");
        $dumpvars(0, tb_framebuffer);

        clear;
        look(0);  expect64(screen_row_data, 64'h0, "clear: row 0 empty");
        look(31); expect64(screen_row_data, 64'h0, "clear: row 31 empty");

        // plain draw at the top left: 8 pixels land in the top byte
        draw_row(6'd0, 5'd0, 4'd0, 8'hFF);
        look(0);  expect64(screen_row_data, 64'hFF00_0000_0000_0000, "draw FF at x=0");
        expect1(collision_flag, 1'b0, "no collision on empty screen");

        // same sprite again XORs it off and reports a collision
        draw_row(6'd0, 5'd0, 4'd0, 8'hFF);
        look(0);  expect64(screen_row_data, 64'h0, "second draw erases (XOR)");
        expect1(collision_flag, 1'b1, "collision when pixels erased");

        // x offset and row_index
        draw_row(6'd4, 5'd2, 4'd3, 8'h81);   // lands on row 5
        look(5);  expect64(screen_row_data, 64'h0810_0000_0000_0000, "x=4, row_index adds to y");

        // right edge: pixels past column 63 are clipped, not wrapped
        draw_row(6'd60, 5'd8, 4'd0, 8'hFF);
        look(8);  expect64(screen_row_data, 64'h0000_0000_0000_000F, "right edge clips");

        // bottom edge: y wraps back to row 0
        draw_row(6'd0, 5'd31, 4'd1, 8'hFF);   // 31 + 1 -> row 0
        look(0);  expect64(screen_row_data, 64'hFF00_0000_0000_0000, "y wraps vertically");

        // ce low: nothing happens
        @(negedge clk); start_x = 6'd0; start_y = 5'd10; row_index = 4'd0;
        sprite_row_data = 8'hFF; draw_en = 1; ce = 0;
        repeat (3) @(negedge clk);
        draw_en = 0;
        look(10); expect64(screen_row_data, 64'h0, "no ce, no draw");

        // clear wipes everything
        clear;
        look(5);  expect64(screen_row_data, 64'h0, "clear wipes row 5");
        look(8);  expect64(screen_row_data, 64'h0, "clear wipes row 8");

        if (fails == 0) $display("ALL TESTS PASSED");
        else            $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
