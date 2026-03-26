module decoder(
    input  [31:0] instr,

    output reg [4:0] read_addr_a,
    output reg [4:0] read_addr_b,
    output reg [4:0] read_addr_c,
    output reg [4:0] write_addr,
    output reg       write_en,
    
    //alu control signals
    output reg [4:0] alu_op,
    output reg [63:0] imm,
    output reg        use_imm,

    //memory control
    output reg        mem_read,
    output reg        mem_write,

    //branch/jump control
    output reg        branch_abs,
    output reg        branch_rel,
    output reg        branch_nz,
    output reg        branch_gt,
    output reg        call,
    output reg        ret,

    output reg        illegal
);
    wire [4:0] opcode = instr[4:0];
    wire [4:0] rd     = instr[9:5];
    wire [4:0] rs     = instr[14:10];
    wire [4:0] rt     = instr[19:15];

    wire [11:0] L12 = instr[31:20];

    function [63:0] zext12;
        input [11:0] x;
        begin
            zext12 = {52'd0, x};
        end
    endfunction

    function [63:0] sext12;
        input [11:0] x;
        begin
            sext12 = {{52{x[11]}}, x};
        end
    endfunction

    localparam OP_AND    = 5'h00;
    localparam OP_OR     = 5'h01;
    localparam OP_XOR    = 5'h02;
    localparam OP_NOT    = 5'h03;
    localparam OP_SHFTR  = 5'h04;
    localparam OP_SHFTRI = 5'h05;
    localparam OP_SHFTL  = 5'h06;
    localparam OP_SHFTLI = 5'h07;
    localparam OP_BR     = 5'h08;
    localparam OP_BRR_R  = 5'h09;
    localparam OP_BRR_L  = 5'h0A;
    localparam OP_BRNZ   = 5'h0B;
    localparam OP_CALL   = 5'h0C;
    localparam OP_RETURN = 5'h0D;
    localparam OP_BRGT   = 5'h0E;
    localparam OP_PRIV   = 5'h0F;
    // mov rd, (rs)(L)
    localparam OP_MOV_MR = 5'h10;
    localparam OP_MOV_R  = 5'h11;
    localparam OP_MOV_I  = 5'h12;
    // mov (rd)(L), rs
    localparam OP_MOV_RM = 5'h13;
    localparam OP_ADDF   = 5'h14;
    localparam OP_SUBF   = 5'h15;
    localparam OP_MULF   = 5'h16;
    localparam OP_DIVF   = 5'h17;
    localparam OP_ADD    = 5'h18;
    localparam OP_ADDI   = 5'h19;
    localparam OP_SUB    = 5'h1A;
    localparam OP_SUBI   = 5'h1B;
    localparam OP_MUL    = 5'h1C;
    localparam OP_DIV    = 5'h1D;

    localparam ALU_ADD    = 5'h00;
    localparam ALU_SUB    = 5'h01;
    localparam ALU_AND    = 5'h02;
    localparam ALU_OR     = 5'h03;
    localparam ALU_XOR    = 5'h04;
    localparam ALU_NOT    = 5'h05;
    localparam ALU_LSHIFT = 5'h06;
    localparam ALU_RSHIFT = 5'h07;
    localparam ALU_MUL    = 5'h08;
    localparam ALU_DIV    = 5'h09;
    localparam ALU_MOV    = 5'h0A;
    localparam ALU_ADDF   = 5'h0B;
    localparam ALU_SUBF   = 5'h0C;
    localparam ALU_MULF   = 5'h0D;
    localparam ALU_DIVF   = 5'h0E;

    always @(*) begin
        read_addr_a = 5'h00;
        read_addr_b = 5'h00;
        read_addr_c = 5'h00;
        write_addr  = 5'h00;
        write_en    = 1'b0;

        alu_op      = ALU_ADD;
        imm         = 64'h0;
        use_imm     = 1'b0;

        mem_read    = 1'b0;
        mem_write   = 1'b0;

        branch_abs  = 1'b0;
        branch_rel  = 1'b0;
        branch_nz   = 1'b0;
        branch_gt   = 1'b0;
        call        = 1'b0;
        ret         = 1'b0;

        illegal     = 1'b0;

        case (opcode)
            OP_AND: begin
                read_addr_a = rs;
                read_addr_b = rt;
                write_addr  = rd;
                write_en    = 1'b1;
                alu_op      = ALU_AND;
            end

            OP_OR: begin
                read_addr_a = rs;
                read_addr_b = rt;
                write_addr  = rd;
                write_en    = 1'b1;
                alu_op      = ALU_OR;
            end

            OP_XOR: begin
                read_addr_a = rs;
                read_addr_b = rt;
                write_addr  = rd;
                write_en    = 1'b1;
                alu_op      = ALU_XOR;
            end

            OP_NOT: begin
                read_addr_a = rs;
                write_addr  = rd;
                write_en    = 1'b1;
                alu_op      = ALU_NOT;
            end

            OP_SHFTR: begin
                read_addr_a = rs;
                read_addr_b = rt;
                write_addr  = rd;
                write_en    = 1'b1;
                alu_op      = ALU_RSHIFT;
            end

            OP_SHFTRI: begin
                read_addr_a = rd;
                write_addr  = rd;
                write_en    = 1'b1;
                use_imm     = 1'b1;
                imm         = zext12(L12);
                alu_op      = ALU_RSHIFT;
            end

            OP_SHFTL: begin
                read_addr_a = rs;
                read_addr_b = rt;
                write_addr  = rd;
                write_en    = 1'b1;
                alu_op      = ALU_LSHIFT;
            end

            OP_SHFTLI: begin
                read_addr_a = rd;
                write_addr  = rd;
                write_en    = 1'b1;
                use_imm     = 1'b1;
                imm         = zext12(L12);
                alu_op      = ALU_LSHIFT;
            end

            OP_ADD: begin
                read_addr_a = rs;
                read_addr_b = rt;
                write_addr  = rd;
                write_en    = 1'b1;
                alu_op      = ALU_ADD;
            end

            OP_ADDI: begin
                read_addr_a = rd;
                write_addr  = rd;
                write_en    = 1'b1;
                use_imm     = 1'b1;
                imm         = zext12(L12);
                alu_op      = ALU_ADD;
            end

            OP_SUB: begin
                read_addr_a = rs;
                read_addr_b = rt;
                write_addr  = rd;
                write_en    = 1'b1;
                alu_op      = ALU_SUB;
            end

            OP_SUBI: begin
                read_addr_a = rd;
                write_addr  = rd;
                write_en    = 1'b1;
                use_imm     = 1'b1;
                imm         = zext12(L12);
                alu_op      = ALU_SUB;
            end

            OP_MUL: begin
                read_addr_a = rs;
                read_addr_b = rt;
                write_addr  = rd;
                write_en    = 1'b1;
                alu_op      = ALU_MUL;
            end

            OP_DIV: begin
                read_addr_a = rs;
                read_addr_b = rt;
                write_addr  = rd;
                write_en    = 1'b1;
                alu_op      = ALU_DIV;
            end

            OP_MOV_R: begin
                read_addr_b = rs;
                write_addr  = rd;
                write_en    = 1'b1;
                alu_op      = ALU_MOV;
            end

            OP_MOV_I: begin
                write_addr  = rd;
                write_en    = 1'b1;
                use_imm     = 1'b1;
                imm         = zext12(L12);
                alu_op      = ALU_MOV;
            end

            // mov rd, (rs)(L)  =>  rd <- Mem[rs + L]
            OP_MOV_MR: begin
                read_addr_a = rs;
                write_addr  = rd;
                write_en    = 1'b1;
                use_imm     = 1'b1;
                imm         = zext12(L12);
                mem_read    = 1'b1;
                alu_op      = ALU_ADD;
            end

            // mov (rd)(L), rs  =>  Mem[rd + L] <- rs
            OP_MOV_RM: begin
                read_addr_a = rd;
                read_addr_b = rs;
                use_imm     = 1'b1;
                imm         = zext12(L12);
                mem_write   = 1'b1;
                alu_op      = ALU_ADD;
            end

            OP_ADDF: begin
                read_addr_a = rs;
                read_addr_b = rt;
                write_addr  = rd;
                write_en    = 1'b1;
                alu_op      = ALU_ADDF;
            end

            OP_SUBF: begin
                read_addr_a = rs;
                read_addr_b = rt;
                write_addr  = rd;
                write_en    = 1'b1;
                alu_op      = ALU_SUBF;
            end

            OP_MULF: begin
                read_addr_a = rs;
                read_addr_b = rt;
                write_addr  = rd;
                write_en    = 1'b1;
                alu_op      = ALU_MULF;
            end

            OP_DIVF: begin
                read_addr_a = rs;
                read_addr_b = rt;
                write_addr  = rd;
                write_en    = 1'b1;
                alu_op      = ALU_DIVF;
            end

            OP_BR: begin
                read_addr_c = rd;
                branch_abs  = 1'b1;
            end

            OP_BRR_R: begin
                read_addr_c = rd;
                branch_rel  = 1'b1;
            end

            OP_BRR_L: begin
                use_imm     = 1'b1;
                imm         = sext12(L12);
                branch_rel  = 1'b1;
            end

            OP_BRNZ: begin
                read_addr_a = rs;
                read_addr_c = rd;
                branch_nz   = 1'b1;
            end

            OP_BRGT: begin
                read_addr_a = rs;
                read_addr_b = rt;
                read_addr_c = rd;
                branch_gt   = 1'b1;
            end

            OP_CALL: begin
                read_addr_c = rd;
                call        = 1'b1;
            end

            OP_RETURN: begin
                ret         = 1'b1;
            end

            OP_PRIV: begin
                illegal     = 1'b1;
            end

            default: begin
                illegal     = 1'b1;
            end
        endcase
    end
endmodule
