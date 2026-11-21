module top(
  input clk,
  input resetn,

  output       tmds_clk_n,
  output       tmds_clk_p,
  output [2:0] tmds_d_n,
  output [2:0] tmds_d_p,

  output [3:0] row,
  input  [3:0] col
);

Gowin_rPLL u_pll (
  .clkin(clk),
  .clkout(clk_p5),
  .lock(pll_lock)
);

Gowin_CLKDIV u_div_5 (
    .clkout(clk_p),
    .hclkin(clk_p5),
    .resetn(pll_lock)
);

Reset_Sync u_Reset_Sync (
  .resetn(sys_resetn),
  .ext_reset(resetn & pll_lock),
  .clk(clk_p)
);

// ===== keypad =====
wire [15:0] buttons;

keypad_scan u_keys (
  .clk(clk_p),
  .col(col),
  .row(row),
  .buttons(buttons)
);
// ===== end keypad =====

// ===== CHIP-8 core =====
wire [4:0]  read_row_y;
wire [63:0] screen_row_data;

chip8_core u_core (
  .clk(clk_p),                 // runs on the pixel clock for now
  .buttons(buttons),
  .read_row_y(read_row_y),
  .screen_row_data(screen_row_data)
);
// ===== end CHIP-8 core =====

svo_hdmi svo_hdmi_inst (
	.clk(clk_p),
	.resetn(sys_resetn),

	// video clocks
	.clk_pixel(clk_p),
	.clk_5x_pixel(clk_p5),
	.locked(pll_lock),

	// framebuffer side
	.read_row_y(read_row_y),
	.screen_row_data(screen_row_data),

	// output signals
	.tmds_clk_n(tmds_clk_n),
	.tmds_clk_p(tmds_clk_p),
	.tmds_d_n(tmds_d_n),
	.tmds_d_p(tmds_d_p)
);

endmodule

module Reset_Sync (
 input clk,
 input ext_reset,
 output resetn
);

 reg [3:0] reset_cnt = 0;

 always @(posedge clk or negedge ext_reset) begin
     if (~ext_reset)
         reset_cnt <= 4'b0;
     else
         reset_cnt <= reset_cnt + !resetn;
 end

 assign resetn = &reset_cnt;

endmodule