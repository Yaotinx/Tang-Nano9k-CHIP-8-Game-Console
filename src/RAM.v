//Initializes memory and the ports
module ram (
    input clk,
    input ce,               // one-cycle pulse: only read/write when high
    input WRE,
    input [7:0] data,
    input [11:0] address,
    output reg [7:0] readData
);
    reg [7:0] memory [4096];

//Only acts on a ce pulse, so the one-edge read delay is exactly one CPU step
always @(posedge clk) begin
    if (ce) begin
        if (WRE)
            memory[address] <= data;
        readData <= memory[address];
    end
end

//Loads the font sprites and the game file
initial begin
    $readmemh("rom.hex", memory, 12'h200);
    $readmemh("font.hex", memory, 12'h050);
end

endmodule