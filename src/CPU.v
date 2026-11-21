// CHIP-8 CPU core: fetches 2-byte opcodes from RAM, decodes the top hex digit,
// and executes. Each instruction takes 5 clock edges (4 fetch + 1 decode/execute).
module cpu (
    input clk,
    input ce,                    // one-cycle pulse: CPU only steps when high

    // --- RAM PORTS ---
    output reg [11:0] address,   // address sent to the RAM (low 12 bits of an address)
    output reg [7:0]  data,      // byte to write into RAM (unused until store instructions exist)
    output reg        WRE = 0,   // RAM write enable; held low because we only read for now
    input      [7:0]  readData,   // byte coming back from the RAM (one edge after address)

    // --- TIMER PORTS ---
    input [7:0] timeDelayValueIn, //Reads delay timer
    output reg [7:0] timeDelayDataOut, //Takes new value for delay Timer
    output reg setDelayTimer = 0, //Control for delay timer
    output reg setSoundTimer = 0, //Control for sound timer
    output reg [7:0] timeSoundDataOut, //Takes new value for sound timer

    // --- KEY PORT ---
    input [15:0] keys, //Tells us which keys were pressed

    // --- GRAPHICS PORTS ---
    output reg clear_screen = 0,    // Goes high when executing 00E0, Control signal
    output reg draw_en = 0,         // Goes high when executing DXYN (write/XOR pulse), Control signal
    output reg [5:0] start_x,       // X coordinate (pulled from register Vx)
    output reg [4:0] start_y,       // Y coordinate (pulled from register Vy)
    output reg[3:0] row_index = 0,     // Which row of the sprite we are on (0 to N-1)
    input collision_flag        // Reads back 1 if a pixel was erased (to update VF)
);

    // ---------------- CPU state ----------------
    reg [15:0] indexRegister;            // I: points at data in RAM (sprites, saved registers)
    reg [15:0] pcRegister;               // PC: address of the next instruction
    reg [7:0]  generalRegister [16];     // V0 to VF: 16 registers, 8 bits each (VF doubles as the flag)
    reg [15:0] stack [16];               // return addresses for subroutine calls (not used yet)
    reg [3:0]  stackPointer = 15;             // which stack slot is on top (4 bits counts 16 slots)
    reg [3:0] store_count;  //Helps in loading and reading memory
    initial pcRegister = 16'h200;        // programs start at 0x200
    initial indexRegister = 16'h0;   

    // ---------------- Fetch helpers ----------------
    reg [7:0]  holdByte;                 // holds the high byte while the low byte arrives
    reg [15:0] opcode;                   // the full 16-bit instruction

    // Always equals VX + VY, 9 bits wide so bit 8 is the carry. It is a wire (assign)
    // so it is already correct when the 8XY4 branch reads it on the same edge.
    wire [8:0] sum;
    assign sum = generalRegister[opcode[11:8]] + generalRegister[opcode[7:4]];

    // Always equals VX - VY and VY-VX depending on instruction call, wrapped to 8 bits (used by 8XY5/8XY7)
    wire [7:0] difference5;
    assign difference5 = generalRegister[opcode[11:8]] - generalRegister[opcode[7:4]];
    wire [7:0] difference7;
    assign difference7 = generalRegister[opcode[7:4]] - generalRegister[opcode[11:8]];

    // ---------------- Overall State machine ----------------
    parameter [4:0] SendHigh = 0, SendLow = 1, SaveHigh = 2, SaveJoin = 3, StartDecode = 4, StoreTens = 5, StoreUnits = 6, StoreMulti = 7, LoadMulti = 8, LoadWait =9, WaitForKey = 10, DrawWait =11, DrawDrain = 12, DrawFinish =13;
    reg [3:0] state = 0;   // starts in SendHigh

    // Instruction families, named by the top hex digit of the opcode (opcode[15:12])
    parameter [3:0] System = 0, Jump = 1, SubRoutine = 2, EqualValue = 3,
        NotEqualVal = 4, EqualRegister = 5, LoadVal = 6, AddVal = 7, Math = 8,
        NotEqualReg = 9, SetI = 10, JumpAdd = 11, Random = 12, Draw = 13,
        KeyBoardCheck = 14, Timer = 15;
     
     // Extracts the lower 4 bits of register Vx as the key index (0-15) for keyboard instructions
     wire [3:0] keyNumber;
     assign keyNumber = generalRegister[opcode[11:8]][3:0];

     // Values used for the Random instruction
    reg [7:0] randomByte;                //Random byte to be ANDED with           
    initial randomByte = 8'd7;

    //Generates a random value
     always @(posedge clk) begin
         randomByte <={ randomByte[6:0], randomByte[7] ^ randomByte[5] ^ randomByte[4] ^ randomByte[3] };
       end

     //Grabs the button where key is pressed
     reg[3:0] pressed_key;
     always @(*) begin
        pressed_key = 0;
        for(integer i =0; i < 16; i = i +1) begin
            if(keys[i])
                pressed_key = i[3:0];
         end
        end

    reg coll_accum =0;
    reg draw_en_d =0;
   //Start of the FSM
    always @(posedge clk) begin
      if (ce) begin
        draw_en_d <= draw_en;
        if(draw_en_d)
            coll_accum <= coll_accum | collision_flag;
        case (state)
            // ===== FETCH =====
            // Edge 1: put the PC on the RAM's address wires and bump the PC.
            SendHigh: begin
                address <= pcRegister[11:0];   // slice: the RAM only takes 12 bits
                pcRegister <= pcRegister + 1;
                state <= SendLow;
                WRE <= 0;
                setDelayTimer <= 0;
                setSoundTimer <= 0;
                clear_screen <= 0;
                draw_en <= 0;
            end

            // Edge 2: send PC+1 for the low byte; the RAM is loading the high byte now.
            SendLow: begin
                address <= pcRegister[11:0];
                pcRegister <= pcRegister + 1;  // PC ends at the next instruction (+2 total)
                state <= SaveHigh;
            end

            // Edge 3: the high byte is on readData now, so save it before it is overwritten.
            SaveHigh: begin
                holdByte <= readData;
                state <= SaveJoin;
            end

            // Edge 4: the low byte is on readData, so join high and low into the opcode.
            SaveJoin: begin
                opcode <= {holdByte, readData};  // high byte on top (CHIP-8 stores it first)
                state <= StartDecode;
            end

            // ===== DECODE + EXECUTE =====
            // Edge 5: branch on the top digit; simple instructions finish in this one state.
            StartDecode: begin
                case (opcode[15:12])

                    //0000
                    System: begin
                      case(opcode[7:0])

                             //00E0, Clear
                             224: begin
                                clear_screen <= 1;
                                state <= SendHigh;
                              end

                             //RET, returns from subroutine (pop the stack)
                             238: begin
                                    pcRegister <= stack[stackPointer+1];
                                    stackPointer <= stackPointer + 1;
                                    state <= SendHigh;
                                end
                                
                            default: state <= SendHigh;
                        endcase
                       state <= SendHigh;
                    end

                    // 1NNN: jump. The PC becomes NNN (throws away the fetched PC).
                    Jump: begin
                        pcRegister <= opcode[11:0];
                        state <= SendHigh;
                    end

                    //2NNN
                    SubRoutine: begin
                        stack[stackPointer] <= pcRegister;
                        stackPointer <= stackPointer - 1;
                        pcRegister <= opcode[11:0];
                        state <= SendHigh;
                    end  

                    // Skips: the PC already points at the next instruction, so +2 hops over it.
                    // 3XNN: skip if VX == NN
                    EqualValue: begin
                        if (generalRegister[opcode[11:8]] == opcode[7:0])
                            pcRegister <= pcRegister + 2;
                        state <= SendHigh;      // outside the if, so it runs either way
                    end

                    // 4XNN: skip if VX != NN
                    NotEqualVal: begin
                        if (generalRegister[opcode[11:8]] != opcode[7:0])
                            pcRegister <= pcRegister + 2;
                        state <= SendHigh;
                    end

                    // 5XY0: skip if VX == VY
                    EqualRegister: begin
                        if (generalRegister[opcode[11:8]] == generalRegister[opcode[7:4]])
                            pcRegister <= pcRegister + 2;
                        state <= SendHigh;
                    end

                    // 6XNN: VX = NN
                    LoadVal: begin
                        generalRegister[opcode[11:8]] <= opcode[7:0];
                        state <= SendHigh;
                    end

                    // 7XNN: VX = VX + NN (8-bit wrap, VF is not touched)
                    AddVal: begin
                        generalRegister[opcode[11:8]] <= generalRegister[opcode[11:8]] + opcode[7:0];
                        state <= SendHigh;
                    end

                    // 8XY_: register-to-register ops. The last digit picks which one.
                    Math: begin
                        case (opcode[3:0])

                            // 8XY0: VX = VY
                            0: begin
                                generalRegister[opcode[11:8]] <= generalRegister[opcode[7:4]];
                                state <= SendHigh;
                            end

                            // 8XY1: VX = VX OR VY (bitwise)
                            1: begin
                                generalRegister[opcode[11:8]] <= generalRegister[opcode[11:8]] | generalRegister[opcode[7:4]];
                                state <= SendHigh;
                            end

                            // 8XY2: VX = VX AND VY (bitwise)
                            2: begin
                                generalRegister[opcode[11:8]] <= generalRegister[opcode[11:8]] & generalRegister[opcode[7:4]];
                                state <= SendHigh;
                            end

                            // 8XY3: VX = VX XOR VY (bitwise)
                            3: begin
                                generalRegister[opcode[11:8]] <= generalRegister[opcode[11:8]] ^ generalRegister[opcode[7:4]];
                                state <= SendHigh;
                            end

                            // 8XY4: VX = VX + VY, VF = carry.
                            // VF is written LAST so that when X is F, the flag wins over the sum.
                            // (Assumed from memory of how most interpreters behave; confirm against the Timendus flags test.)
                            4: begin
                                if (sum > 8'd255) begin
                                    generalRegister[opcode[11:8]] <= sum[7:0];
                                    generalRegister[15] <= 1;
                                end
                                else begin
                                    generalRegister[opcode[11:8]] <= sum[7:0];
                                    generalRegister[15] <= 0;
                                end
                                state <= SendHigh;
                            end

                            // 8XY5: VX = VX - VY, VF = 1 if no borrow (VX >= VY). VF written last, same reason.
                            5: begin
                                if (generalRegister[opcode[11:8]] >= generalRegister[opcode[7:4]]) begin
                                    generalRegister[opcode[11:8]] <= difference5;
                                    generalRegister[15] <= 1;
                                end
                                else begin
                                    generalRegister[opcode[11:8]] <= difference5;
                                    generalRegister[15] <= 0;
                                end
                                state <= SendHigh;
                            end

                            // 8XY6: shift VX right by 1 (VX in place, Y ignored), VF = the bit that fell off.
                            // VF written last, same reason.
                            6: begin
                                if ((generalRegister[opcode[11:8]] & 1'd1) == 1'd1) begin
                                    generalRegister[opcode[11:8]] <= generalRegister[opcode[11:8]] >> 1;
                                    generalRegister[15] <= 1;
                                end
                                else begin
                                    generalRegister[opcode[11:8]] <= generalRegister[opcode[11:8]] >> 1;
                                    generalRegister[15] <= 0;
                                end
                                state <= SendHigh;
                            end

                            // 8XY7: VX = Vy - Vx, VF = 1 if no borrow (VX <= VY). VF written last, same reason.
                            7: begin
                                if (generalRegister[opcode[11:8]] <= generalRegister[opcode[7:4]]) begin
                                    generalRegister[opcode[11:8]] <= difference7;
                                    generalRegister[15] <= 1;
                                end
                                else begin
                                    generalRegister[opcode[11:8]] <= difference7;
                                    generalRegister[15] <= 0;
                                end
                                state <= SendHigh;
                            end

                            //8XYE: shift VX left by 1, VF = bit that falls off and is written last
                            14: begin
                                if ((generalRegister[opcode[11:8]] & 8'd128) == 8'd128) begin
                                    generalRegister[opcode[11:8]] <= generalRegister[opcode[11:8]] << 1;
                                    generalRegister[15] <= 1;
                                end
                                else begin
                                    generalRegister[opcode[11:8]] <= generalRegister[opcode[11:8]] << 1;
                                    generalRegister[15] <= 0;
                                end
                                state <= SendHigh;
                            end
                    
                            // Math instructions not built yet: skip and fetch the next one.
                            default: state <= SendHigh;
                        endcase
                    end
                    
                     // 9XY0: skip if VX != VY
                    NotEqualReg: begin
                        if (generalRegister[opcode[11:8]] != generalRegister[opcode[7:4]])
                            pcRegister <= pcRegister + 2;
                        state <= SendHigh;
                    end

                     // ANNN: I = NNN (the top 4 bits of I are zero-padded)
                    SetI: begin
                        indexRegister <= opcode[11:0];
                        state <= SendHigh;
                    end

                    // BNNN: jump to NNN + V0
                    JumpAdd: begin
                        pcRegister <= generalRegister[0] + opcode[11:0];
                        state <= SendHigh;
                    end
                    
                     //Cxkk, ANDS a random byte with kk then stores it in Vx
                     Random: begin
                            generalRegister[opcode[11:8]] <= randomByte & opcode[7:0];
                            state <= SendHigh;
                        end

                    //Dxyn
                    Draw: begin
                        start_x <= generalRegister[opcode[11:8]][5:0];
                        start_y <= generalRegister[opcode[7:4]][4:0];
                        store_count <= 0;
                        coll_accum <= 0;
                        address <= indexRegister;
                        if(opcode[3:0] == 0) begin
                            state <= SendHigh;
                        end
                        else begin
                            state <= DrawWait;
                        end
                    end

                    //E instructions for keyboard
                    KeyBoardCheck: begin
                    case (opcode[7:0])
                      // EX9E: skip the next instruction if key VX is pressed
                        158: begin
                            if (keys[keyNumber] == 1'b1)
                              pcRegister <= pcRegister + 2;
                              state <= SendHigh;
                            end

                        // EXA1: skip the next instruction if key VX is NOT pressed
                        161: begin
                            if (keys[keyNumber] == 1'b0)
                              pcRegister <= pcRegister + 2;
                              state <= SendHigh;
                            end

                        default: state <= SendHigh;
                        endcase
                    end

                    //F instructions
                    Timer: begin
                        case(opcode[7:0])
                           //Fx07, sets Vx to delay timer value
                           7: begin
                            generalRegister[opcode[11:8]] <= timeDelayValueIn;
                            state <= SendHigh;
                            end

                            //Fx0A, stores value of key in Vx by waiting for a key press
                            10: begin
                            if(keys != 0) begin
                                generalRegister[opcode[11:8]] <= pressed_key;
                                state <= SendHigh;
                            end
                            else begin
                                state <= WaitForKey;
                                end
                            end
    
                            //Fx15,  sets delay timer to Vx
                            21: begin
                                setDelayTimer <= 1;
                                timeDelayDataOut <= generalRegister[opcode[11:8]];
                                state <= SendHigh;
                                end
                            
                            //Fx18,  sets sound timer to Vx
                            24: begin
                                setSoundTimer <=1;
                                timeSoundDataOut <= generalRegister[opcode[11:8]];
                                state <= SendHigh;
                            end

                           //Fx1E, Sets I = I + Vx
                           30: begin
                                indexRegister <= indexRegister + generalRegister[opcode[11:8]];
                                state <= SendHigh;
                                end     

                            //Fx29, Value of I is set to location at value Vx
                            41: begin
                                indexRegister <= 16'h050 + (generalRegister[opcode[11:8]] * 5);
                                state <= SendHigh;
                                end
                            
                            //Fx33, Stores Vx (100s,10s,1s) in memory locations I, I+1, I+2
                            51: begin
                                address <= indexRegister;
                                data <= ((generalRegister[opcode[11:8]] / 100) % 10);
                                WRE <= 1;
                                state <= StoreTens;
                                end

                             //Fx55 stores generalRegister, V0-Vx into memory in indexRegister
                             85: begin
                                 WRE <= 1;
                                store_count <= 0;
                                address <= indexRegister;
                                data <= generalRegister[0];
                                 if (opcode[11:8] == 0) 
                                    state <= SendHigh; 
                                else 
                                    state <= StoreMulti;
                                end
                            
                              //Fx65, reads registesr V0-Vx from memory starting at address I
                              101: begin
                                WRE <= 0;
                                address <= indexRegister;
                                store_count <= 0;
                                state <= LoadWait;
                                end
                            default: state <= SendHigh;
                         endcase    
                        end
                    // Any family not built yet: skip it so the CPU never hangs here.
                    default: state <= SendHigh;
                endcase
            end

            //State for storing instruction Fx33 the ten's value into indexRegister = 1
            StoreTens: begin
                address <= indexRegister + 1;
                data <= ((generalRegister[opcode[11:8]] / 10) % 10);
                WRE <= 1;
                state <= StoreUnits;
            end
            
            //State for storing instruction Fx33 the one's value into indexRegister + 2
            StoreUnits:   begin
                address <= indexRegister + 2;
                data <= (generalRegister[opcode[11:8]] % 10);
                WRE <= 1;
                state <= SendHigh;
            end
   
            //State for storing registers into memory for instruction Fx55
            StoreMulti: begin
                store_count <= store_count + 1;
                address <= indexRegister + store_count + 1;
                data <= generalRegister[store_count + 1];
                WRE <= 1;
                if (store_count == (opcode[11:8] - 1))
                    state <= SendHigh;
                else
                    state <= StoreMulti; 
            end
              
            //Extra state for the LoadMemory (Fx65) to account for readData being late by 1 clock cycle
            LoadWait: begin
                address <= indexRegister + 1;
                state <= LoadMulti;
            end

            //State for loading data from memory into registers for instruction Fx65
            LoadMulti: begin
            generalRegister[store_count] <= readData;
            store_count <= store_count + 1;
            address <= indexRegister + store_count + 2;
            WRE <= 0;
            if (store_count == opcode[11:8])
                state <= SendHigh;
            else    
                state <= LoadMulti;
            end

            //State for waiting after Fx0A if no key is pressed
            WaitForKey: begin
              if(keys !=0) begin       
                generalRegister[opcode[11:8]] <= pressed_key;
                 state <= SendHigh;
            end
              else begin
                state <= WaitForKey;
               end
            end

            // State 1: Wait for the first sprite row byte to arrive from RAM
        DrawWait: begin
             draw_en     <= 1;
            row_index   <= store_count;
            address     <= indexRegister + store_count + 1;
            store_count <= store_count + 1;
            if (store_count == opcode[3:0] - 1)
                state <= DrawDrain;
        end

        // State 2: Stream remaining rows of the sprite
        DrawDrain: begin
            draw_en <= 0;
            state <= DrawFinish;
        end

        // State 3: Turn off draw enable, write collision result to VF, and resume fetch
        DrawFinish: begin
            generalRegister[15] <= coll_accum | collision_flag;
            state <= SendHigh;
        end
endcase
    end
    end
endmodule