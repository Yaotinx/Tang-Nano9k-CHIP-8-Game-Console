module frameBuffer (
    // --- System & Control ---
    input clk,
    input ce,                   // one-cycle pulse: only act when this is high
    input clear_screen,         // Signal from CPU for instruction 00E0
    input draw_en,              // Signal from CPU for instruction DXYN

    // --- CPU Write / Draw Side ---
    input [5:0] start_x,        // X coordinate (Vx), 0 to 63 -> 6 bits
    input [4:0] start_y,        // Y coordinate (Vy), 0 to 31 -> 5 bits
    input [7:0] sprite_row_data,// 1 row of sprite data pulled from RAM
    input [3:0] row_index,      // Which row of the sprite we are currently drawing (0 to 15)
    output reg collision_flag = 0,  // Sends back 1 if a pixel was erased (for VF register)

    // --- VGA Display Side ---
    output [63:0] screen_row_data, // Spits out an entire 64-pixel row to the VGA controller
    input [4:0] read_row_y         // Which row (0 to 31) the VGA beam is currently scanning
);

    // Create a 128-bit wide window to catch wrapping bits, then fold them back
    wire [127:0] wide_sprite = {64'd0, sprite_row_data, 56'd0} >> start_x;
    wire [63:0]  sprite_placed = wide_sprite[63:0] | wide_sprite[127:64];
    wire [4:0] draw_row = (start_y + row_index) & 5'd31; // Automatically wraps 0-31

    // The actual 2D array lives safely inside here, 32 x 64 (32 bytes high and 64 bytes wide)
    reg [63:0] framebuff [31:0];

    always @(posedge clk) begin
        if (ce) begin
            //00E0, clears the frame buffer array (sets everything to 0/off)
            if (clear_screen) begin
                for (integer i = 0; i < 32; i = i + 1) begin
                    for (integer j = 0; j < 64; j = j + 1) begin
                        framebuff[i][j] <= 0;
                    end
                end
            end

            //Dxyn
            else if (draw_en) begin
                framebuff[draw_row] <= sprite_placed ^ framebuff[draw_row];
                collision_flag <= |(framebuff[draw_row] & sprite_placed);
            end
        end
    end

    assign screen_row_data = framebuff[read_row_y];
endmodule