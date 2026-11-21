module TimeX(
  input clk,
  input setDelayTimer,
  input [7:0] dataDelayIn,
  output reg [7:0] timerDelayValue,
  input setSoundTimer,
  input [7:0] dataSoundIn,
  output reg [7:0] timerSoundValue
);

    reg [18:0] clockCounter = 0;
    initial timerDelayValue = 8'd0;
    initial timerSoundValue = 8'd0;
   
    always @(posedge clk) begin
        // 1. Handle Delay Timer (CPU write override takes priority over tick)
        if (setDelayTimer) begin
            timerDelayValue <= dataDelayIn;
        end
        else if (clockCounter == 449999 && timerDelayValue > 0) begin
            timerDelayValue <= timerDelayValue - 1;
        end

        // 2. Handle Sound Timer (CPU write override takes priority over tick)
        if (setSoundTimer) begin
            timerSoundValue <= dataSoundIn;
        end
        else if (clockCounter == 449999 && timerSoundValue > 0) begin
            timerSoundValue <= timerSoundValue - 1;
        end

        // 3. Background 60Hz clock counter (never pauses or drifts)
        if (clockCounter == 449999) begin
            clockCounter <= 0;
        end
        else begin
            clockCounter <= clockCounter + 1;
        end
    end
endmodule