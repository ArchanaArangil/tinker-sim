`timescale 1ns/1ps

module decoder_tb;
    reg  [31:0] instr;

    wire [4:0]  read_addr_a;
    wire [4:0]  read_addr_b;
    wire [4:0]  read_addr_c;
    wire [4:0]  write_addr;
    wire        write_en;
    wire [4:0]  alu_op;
    wire [63:0] imm;
    wire        use_imm;
    wire        mem_read;
    wire        mem_write;
    wire        branch_abs;
    wire        branch_rel;
    wire        branch_nz;
    wire        branch_gt;
    wire        call;
    wire        ret;
    wire        illegal;

    integer errors;

    localparam OP_BRR_L  = 5'h0A;
    localparam OP_BRGT   = 5'h0E;
    localparam OP_PRIV   = 5'h0F;
    localparam OP_MOV_MR = 5'h10;
    localparam OP_MOV_I  = 5'h12;
    localparam OP_MOV_RM = 5'h13;
    localparam OP_ADD    = 5'h18;
    localparam OP_ADDI   = 5'h19;
    localparam OP_CALL   = 5'h0C;
    localparam OP_RETURN = 5'h0D;

    localparam ALU_ADD   = 5'h00;
    localparam ALU_MOV   = 5'h0A;

    decoder dut (
        .instr(instr),
        .read_addr_a(read_addr_a),
        .read_addr_b(read_addr_b),
        .read_addr_c(read_addr_c),
        .write_addr(write_addr),
        .write_en(write_en),
        .alu_op(alu_op),
        .imm(imm),
        .use_imm(use_imm),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .branch_abs(branch_abs),
        .branch_rel(branch_rel),
        .branch_nz(branch_nz),
        .branch_gt(branch_gt),
        .call(call),
        .ret(ret),
        .illegal(illegal)
    );

    function [31:0] encode_r;
        input [4:0] opcode;
        input [4:0] rd;
        input [4:0] rs;
        input [4:0] rt;
        begin
            encode_r = { opcode, rd, rs, rt, 12'h000 };
        end
    endfunction

    function [31:0] encode_i;
        input [4:0] opcode;
        input [4:0] rd;
        input [4:0] rs;
        input [4:0] rt;
        input [11:0] imm12;
        begin
            encode_i = { opcode, rd, rs, rt, imm12 };
        end
    endfunction

    task check_decode;
        input [255:0] test_name;
        input [4:0] exp_read_addr_a;
        input [4:0] exp_read_addr_b;
        input [4:0] exp_read_addr_c;
        input [4:0] exp_write_addr;
        input       exp_write_en;
        input [4:0] exp_alu_op;
        input [63:0] exp_imm;
        input       exp_use_imm;
        input       exp_mem_read;
        input       exp_mem_write;
        input       exp_branch_abs;
        input       exp_branch_rel;
        input       exp_branch_nz;
        input       exp_branch_gt;
        input       exp_call;
        input       exp_ret;
        input       exp_illegal;
        begin
            #1;
            if (read_addr_a !== exp_read_addr_a ||
                read_addr_b !== exp_read_addr_b ||
                read_addr_c !== exp_read_addr_c ||
                write_addr  !== exp_write_addr  ||
                write_en    !== exp_write_en    ||
                alu_op      !== exp_alu_op      ||
                imm         !== exp_imm         ||
                use_imm     !== exp_use_imm     ||
                mem_read    !== exp_mem_read    ||
                mem_write   !== exp_mem_write   ||
                branch_abs  !== exp_branch_abs  ||
                branch_rel  !== exp_branch_rel  ||
                branch_nz   !== exp_branch_nz   ||
                branch_gt   !== exp_branch_gt   ||
                call        !== exp_call        ||
                ret         !== exp_ret         ||
                illegal     !== exp_illegal) begin
                errors = errors + 1;
                $display("FAIL %-20s instr=%h ra=%0d/%0d rb=%0d/%0d rc=%0d/%0d wa=%0d/%0d we=%b/%b alu=%h/%h imm=%h/%h use_imm=%b/%b mem_r=%b/%b mem_w=%b/%b br_abs=%b/%b br_rel=%b/%b br_nz=%b/%b br_gt=%b/%b call=%b/%b ret=%b/%b ill=%b/%b",
                         test_name, instr,
                         read_addr_a, exp_read_addr_a,
                         read_addr_b, exp_read_addr_b,
                         read_addr_c, exp_read_addr_c,
                         write_addr, exp_write_addr,
                         write_en, exp_write_en,
                         alu_op, exp_alu_op,
                         imm, exp_imm,
                         use_imm, exp_use_imm,
                         mem_read, exp_mem_read,
                         mem_write, exp_mem_write,
                         branch_abs, exp_branch_abs,
                         branch_rel, exp_branch_rel,
                         branch_nz, exp_branch_nz,
                         branch_gt, exp_branch_gt,
                         call, exp_call,
                         ret, exp_ret,
                         illegal, exp_illegal);
            end else begin
                $display("PASS %-20s instr=%h", test_name, instr);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/decoder_tb.vcd");
        $dumpvars(0, decoder_tb);

        errors = 0;
        instr = 32'h0;

        instr = encode_r(OP_ADD, 5'd4, 5'd1, 5'd2);
        check_decode("add",
                     5'd1, 5'd2, 5'd0, 5'd4, 1'b1, ALU_ADD, 64'd0, 1'b0,
                     1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

        instr = encode_i(OP_ADDI, 5'd7, 5'd0, 5'd0, 12'h123);
        check_decode("addi",
                     5'd7, 5'd0, 5'd0, 5'd7, 1'b1, ALU_ADD, 64'h123, 1'b1,
                     1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

        instr = encode_i(OP_MOV_I, 5'd9, 5'd0, 5'd0, 12'hABC);
        check_decode("mov_i",
                     5'd0, 5'd0, 5'd0, 5'd9, 1'b1, ALU_MOV, 64'hABC, 1'b1,
                     1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

        instr = encode_i(OP_MOV_MR, 5'd8, 5'd3, 5'd0, 12'h020);
        check_decode("mov_mr",
                     5'd3, 5'd0, 5'd0, 5'd8, 1'b1, ALU_ADD, 64'h20, 1'b1,
                     1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

        instr = encode_i(OP_MOV_RM, 5'd6, 5'd11, 5'd0, 12'h040);
        check_decode("mov_rm",
                     5'd6, 5'd11, 5'd0, 5'd0, 1'b0, ALU_ADD, 64'h40, 1'b1,
                     1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

        instr = encode_i(OP_BRR_L, 5'd0, 5'd0, 5'd0, 12'hFF8);
        check_decode("brr_l -8",
                     5'd0, 5'd0, 5'd0, 5'd0, 1'b0, ALU_ADD, 64'hFFFF_FFFF_FFFF_FFF8, 1'b1,
                     1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

        instr = encode_r(OP_BRGT, 5'd10, 5'd12, 5'd13);
        check_decode("brgt",
                     5'd12, 5'd13, 5'd10, 5'd0, 1'b0, ALU_ADD, 64'd0, 1'b0,
                     1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);

        instr = encode_r(OP_CALL, 5'd14, 5'd0, 5'd0);
        check_decode("call",
                     5'd0, 5'd31, 5'd14, 5'd0, 1'b0, ALU_ADD, 64'd0, 1'b0,
                     1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);

        instr = encode_r(OP_RETURN, 5'd0, 5'd0, 5'd0);
        check_decode("return",
                     5'd0, 5'd31, 5'd0, 5'd0, 1'b0, ALU_ADD, 64'd0, 1'b0,
                     1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);

        instr = encode_r(OP_PRIV, 5'd0, 5'd0, 5'd0);
        check_decode("priv",
                     5'd0, 5'd0, 5'd0, 5'd0, 1'b0, ALU_ADD, 64'd0, 1'b0,
                     1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);

        instr = encode_r(5'h1F, 5'd0, 5'd0, 5'd0);
        check_decode("illegal default",
                     5'd0, 5'd0, 5'd0, 5'd0, 1'b0, ALU_ADD, 64'd0, 1'b0,
                     1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);

        if (errors == 0)
            $display("All decoder tests passed.");
        else
            $display("Decoder tests finished with %0d failure(s).", errors);

        $finish;
    end
endmodule
