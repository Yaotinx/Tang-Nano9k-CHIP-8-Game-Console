module keypad (
    input clk,             // 27 MHz system clock
    input [15:0] buttons,  // Raw physical button inputs from board
    output reg [15:0] keys // Debounced and stable key output
);

    // Counter for generating a ~1ms tick at 27 MHz (27,000 cycles = 1ms)
    reg [14:0] tick_counter = 0; // 15 bits is enough to hold 27,000
    wire tick = (tick_counter == 15'd27000);

    always @(posedge clk) begin
        if (tick_counter >= 15'd27000)
            tick_counter <= 0;
        else
            tick_counter <= tick_counter + 1;
    end

    // Shift registers for each of the 16 keys to debounce them
    reg [15:0] sync_0 [15:0];
    reg [15:0] sync_1 [15:0];
    integer i;

    always @(posedge clk) begin
        if (tick) begin
            for (i = 0; i < 16; i = i + 1) begin
                // Simple 2-stage synchronizer / filter
                sync_0[i] <= buttons[i];
                sync_1[i] <= sync_0[i];
                
                // Only update the key state once stable
                keys[i] <= sync_1[i];
            end
        end
    end

endmodule