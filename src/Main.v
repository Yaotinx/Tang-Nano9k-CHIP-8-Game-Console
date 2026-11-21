module chip8_core(
  input clk,
  input [15:0] buttons,         //raw keypad pins
  input [4:0] read_row_y,       // which row the display wants
  output [63:0] screen_row_data //row's pixels
);
  // ---- Speed limiter: one-cycle clock enable pulse ----
  localparam CLK_HZ = 29_700_000;           // pixel clock
  localparam CE_HZ  = 4000;                 // CPU steps per second, tune later
  localparam CE_DIV = CLK_HZ / CE_HZ;       // 7425 clocks between pulses

  reg [15:0] ce_count = 0;
  reg        ce = 0;

  always @(posedge clk) begin
    if (ce_count == CE_DIV - 1) begin
      ce_count <= 0;
      ce       <= 1;                        // high for exactly one clock
    end else begin
      ce_count <= ce_count + 1;
      ce       <= 0;
    end
  end

  // CPU <-> RAM
  wire [11:0] address;
  wire [7:0] data;
  wire WRE;
  wire [7:0] readData;

  // CPU <-> Time
  wire set_delay;
  wire set_sound;
  wire [7:0] delay_data;
  wire [7:0] sound_data;
  wire [7:0] delay_value;
  wire [7:0] sound_value;

  // CPU <-> Keypad
  wire [15:0] keys;

  // CPU <-> framebuffer
  wire clear_screen;
  wire draw_en;
  wire [5:0] start_x;
  wire [4:0] start_y;
  wire [3:0] row_index;
  wire collision_flag;

  cpu mod_cpu (
    .clk(clk),
    .ce(ce),
    .address(address),
    .data(data),
    .WRE(WRE),
    .readData(readData),
    .timeDelayValueIn(delay_value),
    .timeDelayDataOut(delay_data),
    .setDelayTimer(set_delay),
    .setSoundTimer(set_sound),
    .timeSoundDataOut(sound_data),
    .keys(keys),
    .clear_screen(clear_screen),
    .draw_en(draw_en),
    .start_x(start_x),
    .start_y(start_y),
    .row_index(row_index),
    .collision_flag(collision_flag)
  );

  ram mod_ram(
    .clk(clk),
    .ce(ce),
    .WRE(WRE),
    .data(data),
    .address(address),
    .readData(readData)
  );

  keypad u_keypad (
    .clk(clk),
    .buttons(buttons),
    .keys(keys)
  );

  frameBuffer u_fb (
    .clk(clk),
    .ce(ce),
    .clear_screen(clear_screen),
    .draw_en(draw_en),
    .start_x(start_x),
    .start_y(start_y),
    .row_index(row_index),
    .collision_flag(collision_flag),
    .screen_row_data(screen_row_data),
    .read_row_y(read_row_y),
    .sprite_row_data(readData)
  );

  TimeX mod_time(
    .clk(clk),
    .setDelayTimer(set_delay),
    .dataDelayIn(delay_data),
    .timerDelayValue(delay_value),
    .setSoundTimer(set_sound),
    .dataSoundIn(sound_data),
    .timerSoundValue(sound_value)
  );

endmodule