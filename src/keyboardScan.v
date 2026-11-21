module keypad_scan #(
    parameter CLK_HZ  = 29_700_000,
    parameter STEP_HZ = 4000          // row steps per second (1000 full scans/s)
)(
    input  wire        clk,
    input  wire [3:0]  col,           // from keypad, active low (use pull-ups)
    output reg  [3:0]  row = 4'b1110, // to keypad, one bit low at a time
    output wire [15:0] buttons        // bit n = 1 when CHIP-8 key n is pressed
);
    localparam DIV = CLK_HZ / STEP_HZ;

    reg [15:0] cnt = 0;
    reg [1:0]  idx = 0;               // current row being driven
    wire [1:0] nxt = idx + 2'd1;

    // synchronize the column inputs (they are asynchronous to clk)
    reg [3:0] col_s1 = 4'hF, col_s2 = 4'hF;

    // raw[r*4 + c] = 1 when the key at row r, column c is pressed
    reg [15:0] raw = 16'd0;

    always @(posedge clk) begin
        col_s1 <= col;
        col_s2 <= col_s1;

        if (cnt == DIV - 1) begin
            cnt <= 0;
            raw[idx*4 +: 4] <= ~col_s2;     // row has been low a full step, so it's settled
            idx <= nxt;
            row <= ~(4'b0001 << nxt);       // 1110, 1101, 1011, 0111
        end else begin
            cnt <= cnt + 1;
        end
    end

    // map physical position to CHIP-8 key number
    //   1 2 3 C
    //   4 5 6 D
    //   7 8 9 E
    //   A 0 B F
    assign buttons[1]  = raw[0];
    assign buttons[2]  = raw[1];
    assign buttons[3]  = raw[2];
    assign buttons[12] = raw[3];
    assign buttons[4]  = raw[4];
    assign buttons[5]  = raw[5];
    assign buttons[6]  = raw[6];
    assign buttons[13] = raw[7];
    assign buttons[7]  = raw[8];
    assign buttons[8]  = raw[9];
    assign buttons[9]  = raw[10];
    assign buttons[14] = raw[11];
    assign buttons[10] = raw[12];
    assign buttons[0]  = raw[13];
    assign buttons[11] = raw[14];
    assign buttons[15] = raw[15];
endmodule