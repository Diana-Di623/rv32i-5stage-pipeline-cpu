`timescale 1ns / 1ps

module rv32ip(
    input  wire        clock,
    input  wire        reset,

    output wire [31:0] imemaddr,
    input  wire [31:0] imemdataout,
    output wire        imemclk,

    output wire [31:0] dmemaddr,
    input  wire [31:0] dmemdataout,
    output wire [31:0] dmemdatain,
    output wire        dmemrdclk,
    output wire        dmemwrclk,
    output wire [2:0]  dmemop,
    output wire        dmemwe,

    output wire [31:0] dbgdata
    );

localparam [3:0] ALU_ADD   = 4'd0;
localparam [3:0] ALU_SUB   = 4'd1;
localparam [3:0] ALU_SLL   = 4'd2;
localparam [3:0] ALU_SLT   = 4'd3;
localparam [3:0] ALU_SLTU  = 4'd4;
localparam [3:0] ALU_XOR   = 4'd5;
localparam [3:0] ALU_SRL   = 4'd6;
localparam [3:0] ALU_SRA   = 4'd7;
localparam [3:0] ALU_OR    = 4'd8;
localparam [3:0] ALU_AND   = 4'd9;
localparam [3:0] ALU_PASSB = 4'd10;

localparam [1:0] BSRC_REG  = 2'd0;
localparam [1:0] BSRC_IMM  = 2'd1;
localparam [1:0] BSRC_FOUR = 2'd2;

localparam [3:0] BR_NONE = 4'd0;
localparam [3:0] BR_JAL  = 4'd1;
localparam [3:0] BR_JALR = 4'd2;
localparam [3:0] BR_BEQ  = 4'd3;
localparam [3:0] BR_BNE  = 4'd4;
localparam [3:0] BR_BLT  = 4'd5;
localparam [3:0] BR_BGE  = 4'd6;
localparam [3:0] BR_BLTU = 4'd7;
localparam [3:0] BR_BGEU = 4'd8;

reg [31:0] PC;
wire [31:0] instr;

assign imemaddr  = PC;
assign imemclk   = clock;
assign instr     = imemdataout;
assign dbgdata   = PC;
assign dmemrdclk = clock;
assign dmemwrclk = ~clock;

reg [31:0] ID_PC;
reg [31:0] ID_Instr;

wire [6:0] ID_opcode = ID_Instr[6:0];
wire [4:0] ID_rs1    = ID_Instr[19:15];
wire [4:0] ID_rs2    = ID_Instr[24:20];
wire [4:0] ID_rd     = ID_Instr[11:7];
wire [2:0] ID_funct3 = ID_Instr[14:12];
wire [6:0] ID_funct7 = ID_Instr[31:25];

wire [31:0] ID_rs1data;
wire [31:0] ID_rs2data;

reg  [31:0] ID_imm;
reg         ID_RegWrite;
reg         ID_MemWrite;
reg         ID_MemToReg;
reg  [2:0]  ID_MemOP;
reg         ID_ALUSrcA_PC;
reg  [1:0]  ID_ALUSrcB;
reg  [3:0]  ID_ALUOp;
reg  [3:0]  ID_Branch;
reg         ID_UseRs1;
reg         ID_UseRs2;

reg  [31:0] WB_ALUResult;
reg  [31:0] WB_MemData;
reg  [4:0]  WB_rd;
reg         WB_RegWrite;
reg         WB_MemToReg;
wire [31:0] WB_WriteData;

assign WB_WriteData = WB_MemToReg ? WB_MemData : WB_ALUResult;

rv32ip_regfile myregfile(
    .clock(clock),
    .reset(reset),
    .ra(ID_rs1),
    .rb(ID_rs2),
    .rw(WB_rd),
    .wdata(WB_WriteData),
    .we(WB_RegWrite),
    .rdata_a(ID_rs1data),
    .rdata_b(ID_rs2data)
    );

always @(*) begin
    ID_imm        = 32'b0;
    ID_RegWrite   = 1'b0;
    ID_MemWrite   = 1'b0;
    ID_MemToReg   = 1'b0;
    ID_MemOP      = 3'b010;
    ID_ALUSrcA_PC = 1'b0;
    ID_ALUSrcB    = BSRC_REG;
    ID_ALUOp      = ALU_ADD;
    ID_Branch     = BR_NONE;
    ID_UseRs1     = 1'b0;
    ID_UseRs2     = 1'b0;

    case (ID_opcode)
        7'b0110111: begin
            ID_imm      = {ID_Instr[31:12], 12'b0};
            ID_RegWrite = 1'b1;
            ID_ALUSrcB  = BSRC_IMM;
            ID_ALUOp    = ALU_PASSB;
        end

        7'b0010111: begin
            ID_imm        = {ID_Instr[31:12], 12'b0};
            ID_RegWrite   = 1'b1;
            ID_ALUSrcA_PC = 1'b1;
            ID_ALUSrcB    = BSRC_IMM;
            ID_ALUOp      = ALU_ADD;
        end

        7'b1101111: begin
            ID_imm = {{12{ID_Instr[31]}}, ID_Instr[19:12],
                      ID_Instr[20], ID_Instr[30:21], 1'b0};
            ID_RegWrite   = 1'b1;
            ID_ALUSrcA_PC = 1'b1;
            ID_ALUSrcB    = BSRC_FOUR;
            ID_ALUOp      = ALU_ADD;
            ID_Branch     = BR_JAL;
        end

        7'b1100111: begin
            if (ID_funct3 == 3'b000) begin
                ID_imm        = {{20{ID_Instr[31]}}, ID_Instr[31:20]};
                ID_RegWrite   = 1'b1;
                ID_ALUSrcA_PC = 1'b1;
                ID_ALUSrcB    = BSRC_FOUR;
                ID_ALUOp      = ALU_ADD;
                ID_Branch     = BR_JALR;
                ID_UseRs1     = 1'b1;
            end
        end

        7'b1100011: begin
            ID_imm = {{20{ID_Instr[31]}}, ID_Instr[7],
                      ID_Instr[30:25], ID_Instr[11:8], 1'b0};
            ID_UseRs1 = 1'b1;
            ID_UseRs2 = 1'b1;
            case (ID_funct3)
                3'b000: ID_Branch = BR_BEQ;
                3'b001: ID_Branch = BR_BNE;
                3'b100: ID_Branch = BR_BLT;
                3'b101: ID_Branch = BR_BGE;
                3'b110: ID_Branch = BR_BLTU;
                3'b111: ID_Branch = BR_BGEU;
                default: ID_Branch = BR_NONE;
            endcase
        end

        7'b0000011: begin
            ID_imm      = {{20{ID_Instr[31]}}, ID_Instr[31:20]};
            ID_RegWrite = 1'b1;
            ID_MemToReg = 1'b1;
            ID_MemOP    = ID_funct3;
            ID_ALUSrcB  = BSRC_IMM;
            ID_ALUOp    = ALU_ADD;
            ID_UseRs1   = 1'b1;
        end

        7'b0100011: begin
            ID_imm = {{20{ID_Instr[31]}}, ID_Instr[31:25],
                      ID_Instr[11:7]};
            ID_MemWrite = 1'b1;
            ID_MemOP    = ID_funct3;
            ID_ALUSrcB  = BSRC_IMM;
            ID_ALUOp    = ALU_ADD;
            ID_UseRs1   = 1'b1;
            ID_UseRs2   = 1'b1;
        end

        7'b0010011: begin
            ID_imm      = {{20{ID_Instr[31]}}, ID_Instr[31:20]};
            ID_RegWrite = 1'b1;
            ID_ALUSrcB  = BSRC_IMM;
            ID_UseRs1   = 1'b1;
            case (ID_funct3)
                3'b000: ID_ALUOp = ALU_ADD;
                3'b010: ID_ALUOp = ALU_SLT;
                3'b011: ID_ALUOp = ALU_SLTU;
                3'b100: ID_ALUOp = ALU_XOR;
                3'b110: ID_ALUOp = ALU_OR;
                3'b111: ID_ALUOp = ALU_AND;
                3'b001: begin
                    if (ID_funct7 == 7'b0000000)
                        ID_ALUOp = ALU_SLL;
                    else
                        ID_RegWrite = 1'b0;
                end
                3'b101: begin
                    if (ID_funct7 == 7'b0000000)
                        ID_ALUOp = ALU_SRL;
                    else if (ID_funct7 == 7'b0100000)
                        ID_ALUOp = ALU_SRA;
                    else
                        ID_RegWrite = 1'b0;
                end
                default: ID_RegWrite = 1'b0;
            endcase
        end

        7'b0110011: begin
            ID_RegWrite = 1'b1;
            ID_ALUSrcB  = BSRC_REG;
            ID_UseRs1   = 1'b1;
            ID_UseRs2   = 1'b1;
            case (ID_funct3)
                3'b000: begin
                    if (ID_funct7 == 7'b0000000)
                        ID_ALUOp = ALU_ADD;
                    else if (ID_funct7 == 7'b0100000)
                        ID_ALUOp = ALU_SUB;
                    else
                        ID_RegWrite = 1'b0;
                end
                3'b001: ID_ALUOp = ALU_SLL;
                3'b010: ID_ALUOp = ALU_SLT;
                3'b011: ID_ALUOp = ALU_SLTU;
                3'b100: ID_ALUOp = ALU_XOR;
                3'b101: begin
                    if (ID_funct7 == 7'b0000000)
                        ID_ALUOp = ALU_SRL;
                    else if (ID_funct7 == 7'b0100000)
                        ID_ALUOp = ALU_SRA;
                    else
                        ID_RegWrite = 1'b0;
                end
                3'b110: ID_ALUOp = ALU_OR;
                3'b111: ID_ALUOp = ALU_AND;
                default: ID_RegWrite = 1'b0;
            endcase
        end

        default: begin
        end
    endcase
end

reg [31:0] EX_PC;
reg [31:0] EX_imm;
reg [31:0] EX_rs1data;
reg [31:0] EX_rs2data;
reg [4:0]  EX_rs1;
reg [4:0]  EX_rs2;
reg [4:0]  EX_rd;
reg        EX_RegWrite;
reg        EX_MemWrite;
reg        EX_MemToReg;
reg [2:0]  EX_MemOP;
reg        EX_ALUSrcA_PC;
reg [1:0]  EX_ALUSrcB;
reg [3:0]  EX_ALUOp;
reg [3:0]  EX_Branch;
reg        EX_UseRs1;
reg        EX_UseRs2;

reg [31:0] MEM_ALUResult;
reg [31:0] MEM_StoreData;
reg [4:0]  MEM_rd;
reg        MEM_RegWrite;
reg        MEM_MemWrite;
reg        MEM_MemToReg;
reg [2:0]  MEM_MemOP;

reg [31:0] EX_ForwardA;
reg [31:0] EX_ForwardB;

always @(*) begin
    EX_ForwardA = EX_rs1data;
    EX_ForwardB = EX_rs2data;

    if (WB_RegWrite && (WB_rd != 5'b0)) begin
        if (WB_rd == EX_rs1)
            EX_ForwardA = WB_WriteData;
        if (WB_rd == EX_rs2)
            EX_ForwardB = WB_WriteData;
    end

    if (MEM_RegWrite && !MEM_MemToReg && (MEM_rd != 5'b0)) begin
        if (MEM_rd == EX_rs1)
            EX_ForwardA = MEM_ALUResult;
        if (MEM_rd == EX_rs2)
            EX_ForwardB = MEM_ALUResult;
    end
end

wire load_use_hazard;
assign load_use_hazard = MEM_RegWrite && MEM_MemToReg &&
                         (MEM_rd != 5'b0) &&
                         ((EX_UseRs1 && (MEM_rd == EX_rs1)) ||
                          (EX_UseRs2 && (MEM_rd == EX_rs2)));

reg [31:0] EX_ALUInputA;
reg [31:0] EX_ALUInputB;
reg [31:0] EX_ALUResult;

always @(*) begin
    EX_ALUInputA = EX_ALUSrcA_PC ? EX_PC : EX_ForwardA;
    case (EX_ALUSrcB)
        BSRC_REG:  EX_ALUInputB = EX_ForwardB;
        BSRC_IMM:  EX_ALUInputB = EX_imm;
        BSRC_FOUR: EX_ALUInputB = 32'd4;
        default:   EX_ALUInputB = 32'b0;
    endcase

    case (EX_ALUOp)
        ALU_ADD:   EX_ALUResult = EX_ALUInputA + EX_ALUInputB;
        ALU_SUB:   EX_ALUResult = EX_ALUInputA - EX_ALUInputB;
        ALU_SLL:   EX_ALUResult = EX_ALUInputA << EX_ALUInputB[4:0];
        ALU_SLT:   EX_ALUResult = {31'b0,
                                   ($signed(EX_ALUInputA) < $signed(EX_ALUInputB))};
        ALU_SLTU:  EX_ALUResult = {31'b0, (EX_ALUInputA < EX_ALUInputB)};
        ALU_XOR:   EX_ALUResult = EX_ALUInputA ^ EX_ALUInputB;
        ALU_SRL:   EX_ALUResult = EX_ALUInputA >> EX_ALUInputB[4:0];
        ALU_SRA:   EX_ALUResult = $signed(EX_ALUInputA) >>> EX_ALUInputB[4:0];
        ALU_OR:    EX_ALUResult = EX_ALUInputA | EX_ALUInputB;
        ALU_AND:   EX_ALUResult = EX_ALUInputA & EX_ALUInputB;
        ALU_PASSB: EX_ALUResult = EX_ALUInputB;
        default:   EX_ALUResult = 32'b0;
    endcase
end

reg        EX_Redirect;
reg [31:0] EX_Target;

always @(*) begin
    EX_Redirect = 1'b0;
    EX_Target   = EX_PC + EX_imm;

    case (EX_Branch)
        BR_JAL: begin
            EX_Redirect = 1'b1;
            EX_Target   = EX_PC + EX_imm;
        end
        BR_JALR: begin
            EX_Redirect = 1'b1;
            EX_Target   = (EX_ForwardA + EX_imm) & 32'hfffffffe;
        end
        BR_BEQ: begin
            EX_Redirect = (EX_ForwardA == EX_ForwardB);
            EX_Target   = EX_PC + EX_imm;
        end
        BR_BNE: begin
            EX_Redirect = (EX_ForwardA != EX_ForwardB);
            EX_Target   = EX_PC + EX_imm;
        end
        BR_BLT: begin
            EX_Redirect = ($signed(EX_ForwardA) < $signed(EX_ForwardB));
            EX_Target   = EX_PC + EX_imm;
        end
        BR_BGE: begin
            EX_Redirect = ($signed(EX_ForwardA) >= $signed(EX_ForwardB));
            EX_Target   = EX_PC + EX_imm;
        end
        BR_BLTU: begin
            EX_Redirect = (EX_ForwardA < EX_ForwardB);
            EX_Target   = EX_PC + EX_imm;
        end
        BR_BGEU: begin
            EX_Redirect = (EX_ForwardA >= EX_ForwardB);
            EX_Target   = EX_PC + EX_imm;
        end
        default: begin
            EX_Redirect = 1'b0;
            EX_Target   = EX_PC + EX_imm;
        end
    endcase

    if (load_use_hazard)
        EX_Redirect = 1'b0;
end

assign dmemaddr   = MEM_ALUResult;
assign dmemdatain = MEM_StoreData;
assign dmemop     = MEM_MemOP;
assign dmemwe     = MEM_MemWrite && !reset;

always @(negedge clock or posedge reset) begin
    if (reset) begin
        PC <= 32'b0;

        ID_PC    <= 32'b0;
        ID_Instr <= 32'b0;

        EX_PC         <= 32'b0;
        EX_imm        <= 32'b0;
        EX_rs1data    <= 32'b0;
        EX_rs2data    <= 32'b0;
        EX_rs1        <= 5'b0;
        EX_rs2        <= 5'b0;
        EX_rd         <= 5'b0;
        EX_RegWrite   <= 1'b0;
        EX_MemWrite   <= 1'b0;
        EX_MemToReg   <= 1'b0;
        EX_MemOP      <= 3'b010;
        EX_ALUSrcA_PC <= 1'b0;
        EX_ALUSrcB    <= BSRC_REG;
        EX_ALUOp      <= ALU_ADD;
        EX_Branch     <= BR_NONE;
        EX_UseRs1     <= 1'b0;
        EX_UseRs2     <= 1'b0;

        MEM_ALUResult <= 32'b0;
        MEM_StoreData <= 32'b0;
        MEM_rd        <= 5'b0;
        MEM_RegWrite  <= 1'b0;
        MEM_MemWrite  <= 1'b0;
        MEM_MemToReg  <= 1'b0;
        MEM_MemOP     <= 3'b010;

        WB_ALUResult <= 32'b0;
        WB_MemData   <= 32'b0;
        WB_rd        <= 5'b0;
        WB_RegWrite  <= 1'b0;
        WB_MemToReg  <= 1'b0;
    end
    else begin
        WB_ALUResult <= MEM_ALUResult;
        WB_MemData   <= dmemdataout;
        WB_rd        <= MEM_rd;
        WB_RegWrite  <= MEM_RegWrite;
        WB_MemToReg  <= MEM_MemToReg;

        if (load_use_hazard) begin
            MEM_ALUResult <= 32'b0;
            MEM_StoreData <= 32'b0;
            MEM_rd        <= 5'b0;
            MEM_RegWrite  <= 1'b0;
            MEM_MemWrite  <= 1'b0;
            MEM_MemToReg  <= 1'b0;
            MEM_MemOP     <= 3'b010;
        end
        else begin
            MEM_ALUResult <= EX_ALUResult;
            MEM_StoreData <= EX_ForwardB;
            MEM_rd        <= EX_rd;
            MEM_RegWrite  <= EX_RegWrite;
            MEM_MemWrite  <= EX_MemWrite;
            MEM_MemToReg  <= EX_MemToReg;
            MEM_MemOP     <= EX_MemOP;
        end

        if (load_use_hazard) begin
            PC       <= PC;
            ID_PC    <= ID_PC;
            ID_Instr <= ID_Instr;

            EX_PC         <= EX_PC;
            EX_imm        <= EX_imm;
            EX_rs1data    <= EX_ForwardA;
            EX_rs2data    <= EX_ForwardB;
            EX_rs1        <= EX_rs1;
            EX_rs2        <= EX_rs2;
            EX_rd         <= EX_rd;
            EX_RegWrite   <= EX_RegWrite;
            EX_MemWrite   <= EX_MemWrite;
            EX_MemToReg   <= EX_MemToReg;
            EX_MemOP      <= EX_MemOP;
            EX_ALUSrcA_PC <= EX_ALUSrcA_PC;
            EX_ALUSrcB    <= EX_ALUSrcB;
            EX_ALUOp      <= EX_ALUOp;
            EX_Branch     <= EX_Branch;
            EX_UseRs1     <= EX_UseRs1;
            EX_UseRs2     <= EX_UseRs2;
        end
        else if (EX_Redirect) begin
            PC       <= EX_Target;
            ID_PC    <= 32'b0;
            ID_Instr <= 32'b0;

            EX_PC         <= 32'b0;
            EX_imm        <= 32'b0;
            EX_rs1data    <= 32'b0;
            EX_rs2data    <= 32'b0;
            EX_rs1        <= 5'b0;
            EX_rs2        <= 5'b0;
            EX_rd         <= 5'b0;
            EX_RegWrite   <= 1'b0;
            EX_MemWrite   <= 1'b0;
            EX_MemToReg   <= 1'b0;
            EX_MemOP      <= 3'b010;
            EX_ALUSrcA_PC <= 1'b0;
            EX_ALUSrcB    <= BSRC_REG;
            EX_ALUOp      <= ALU_ADD;
            EX_Branch     <= BR_NONE;
            EX_UseRs1     <= 1'b0;
            EX_UseRs2     <= 1'b0;
        end
        else begin
            PC       <= PC + 32'd4;
            ID_PC    <= PC;
            ID_Instr <= instr;

            EX_PC         <= ID_PC;
            EX_imm        <= ID_imm;
            EX_rs1data    <= ID_rs1data;
            EX_rs2data    <= ID_rs2data;
            EX_rs1        <= ID_rs1;
            EX_rs2        <= ID_rs2;
            EX_rd         <= ID_rd;
            EX_RegWrite   <= ID_RegWrite;
            EX_MemWrite   <= ID_MemWrite;
            EX_MemToReg   <= ID_MemToReg;
            EX_MemOP      <= ID_MemOP;
            EX_ALUSrcA_PC <= ID_ALUSrcA_PC;
            EX_ALUSrcB    <= ID_ALUSrcB;
            EX_ALUOp      <= ID_ALUOp;
            EX_Branch     <= ID_Branch;
            EX_UseRs1     <= ID_UseRs1;
            EX_UseRs2     <= ID_UseRs2;
        end
    end
end

endmodule


module rv32ip_regfile(
    input  wire        clock,
    input  wire        reset,
    input  wire [4:0]  ra,
    input  wire [4:0]  rb,
    input  wire [4:0]  rw,
    input  wire [31:0] wdata,
    input  wire        we,
    output wire [31:0] rdata_a,
    output wire [31:0] rdata_b
    );

reg [31:0] regs [31:0];

assign rdata_a = (ra == 5'b0) ? 32'b0 : regs[ra];
assign rdata_b = (rb == 5'b0) ? 32'b0 : regs[rb];

always @(posedge clock or posedge reset) begin
    if (reset) begin
        regs[0] <= 32'b0;
    end
    else begin
        regs[0] <= 32'b0;
        if (we && (rw != 5'b0))
            regs[rw] <= wdata;
    end
end

endmodule
