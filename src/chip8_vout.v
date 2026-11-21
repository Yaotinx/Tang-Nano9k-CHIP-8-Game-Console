/*
 *  SVO - Simple Video Out FPGA Core
 *
 *  Copyright (C) 2014  Clifford Wolf <clifford@clifford.at>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 *  Modified for a CHIP-8 console: replaces svo_tcard (test card).
 */

`timescale 1ns / 1ps
`include "svo_defines.vh"

// Step 2b: draws the CHIP-8 framebuffer (64x32 cells, big pixels).
// Works in 640x480 (10x scale) and 800x480 (12x scale).
// It asks the framebuffer for one row at a time (read_row_y) and picks the
// bit for the current column out of the row it gets back (screen_row_data).
module chip8_vout #( `SVO_DEFAULT_PARAMS ) (
	input clk, resetn,

	// framebuffer side
	output [4:0] read_row_y,          // which CHIP-8 row we want
	input  [63:0] screen_row_data,    // that row, bit 63 = leftmost pixel

	// output stream
	//   tuser[0] ... start of frame
	output reg out_axis_tvalid,
	input out_axis_tready,
	output reg [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output reg [0:0] out_axis_tuser
);
	`SVO_DECLS

	// ---- Layout (all worked out from the screen size) ----
	localparam SCALE  = (SVO_HOR_PIXELS >= 768) ? 12 : 10; // screen pixels per CHIP-8 pixel
	localparam PIC_W  = 64 * SCALE;
	localparam PIC_H  = 32 * SCALE;
	localparam LEFT   = (SVO_HOR_PIXELS - PIC_W) / 2;      // first picture column
	localparam RIGHT  = LEFT + PIC_W;                      // one past the last column
	localparam TOP    = (SVO_VER_PIXELS - PIC_H) / 2;      // first picture line
	localparam BOTTOM = TOP + PIC_H;                       // one past the last line

	// Position of the pixel being sent, in raster order
	reg [`SVO_XYBITS-1:0] hcursor;
	reg [`SVO_XYBITS-1:0] vcursor;

	// Which CHIP-8 cell we are in, and how far into it (in screen pixels)
	reg [3:0] xoff, yoff;     // 0 to SCALE-1
	reg [6:0] xcell;          // 0 to 63 (7 bits so it never wraps inside the picture)
	reg [5:0] ycell;          // 0 to 31

	wire in_x   = (hcursor >= LEFT) && (hcursor < RIGHT);
	wire in_y   = (vcursor >= TOP)  && (vcursor < BOTTOM);
	wire in_pic = in_x && in_y;

	// Ask the framebuffer for the row we are drawing.
	assign read_row_y = ycell[4:0];

	// Pick this column's bit out of the row. Column 0 is bit 63, column 63 is
	// bit 0, so the bit number is 63 - xcell. For a 6-bit number that is the
	// same as flipping all its bits (~).
	wire cell_on = screen_row_data[~xcell[5:0]];

	always @(posedge clk) begin
		if (!resetn) begin
			hcursor <= 0;
			vcursor <= 0;
			xoff <= 0;
			yoff <= 0;
			xcell <= 0;
			ycell <= 0;
			out_axis_tvalid <= 0;
			out_axis_tdata <= 0;
			out_axis_tuser <= 0;
		end else
		if (!out_axis_tvalid || out_axis_tready) begin
			out_axis_tvalid <= 1;

			if (in_pic && cell_on)
				out_axis_tdata <= ~0;   // white
			else
				out_axis_tdata <= 0;    // black

			out_axis_tuser[0] <= !hcursor && !vcursor;

			if (hcursor == SVO_HOR_PIXELS-1) begin
				// end of a line: go back to the left edge
				hcursor <= 0;
				xoff <= 0;
				xcell <= 0;
				if (vcursor == SVO_VER_PIXELS-1) begin
					// end of the frame
					vcursor <= 0;
					yoff <= 0;
					ycell <= 0;
				end else begin
					vcursor <= vcursor + 1;
					if (in_y) begin
						if (yoff == SCALE-1) begin
							yoff <= 0;
							ycell <= ycell + 1;
						end else begin
							yoff <= yoff + 1;
						end
					end
				end
			end else begin
				hcursor <= hcursor + 1;
				if (in_x) begin
					if (xoff == SCALE-1) begin
						xoff <= 0;
						xcell <= xcell + 1;
					end else begin
						xoff <= xoff + 1;
					end
				end
			end
		end
	end
endmodule