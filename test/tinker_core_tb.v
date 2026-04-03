`timescale 1ns/1ps

module tinker_core_tb;
    reg clk;
    reg reset;

    integer errors;

    localparam START_PC = 64'h0000_0000_0000_2000;
    localparam DATA_BASE = 64'h0000_0000_0000_0080;

    localparam OP_NOT    = 5'h03;
    localparam OP_SHFTRI = 5'h05;
    localparam OP_SHFTLI = 5'h07;
    localparam OP_BR     = 5'h08;
    localparam OP_BRR_R  = 5'h09;
    localparam OP_BRR_L  = 5'h0A;
    localparam OP_BRNZ   = 5'h0B;
    localparam OP_CALL   = 5'h0C;
    localparam OP_RETURN = 5'h0D;
    localparam OP_BRGT   = 5'h0E;
    localparam OP_MOV_MR = 5'h10;
    localparam OP_MOV_R  = 5'h11;
    localparam OP_MOV_I  = 5'h12;
    localparam OP_MOV_RM = 5'h13;
    localparam OP_MULF   = 5'h16;
    localparam OP_DIVF   = 5'h17;
    localparam OP_ADD    = 5'h18;
    localparam OP_ADDI   = 5'h19;
    localparam OP_SUBI   = 5'h1B;

    tinker_core dut (
        .clk(clk),
        .reset(reset)
    );

    always #5 clk = ~clk;

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

    task write_instr;
        input [63:0] addr;
        input [31:0] instr;
        integer idx;
        begin
            idx = addr[31:0];
            dut.memory.bytes[idx + 0] = instr[7:0];
            dut.memory.bytes[idx + 1] = instr[15:8];
            dut.memory.bytes[idx + 2] = instr[23:16];
            dut.memory.bytes[idx + 3] = instr[31:24];
        end
    endtask

    task write_data64;
        input [63:0] addr;
        input [63:0] value;
        integer idx;
        begin
            idx = addr[31:0];
            dut.memory.bytes[idx + 0] = value[7:0];
            dut.memory.bytes[idx + 1] = value[15:8];
            dut.memory.bytes[idx + 2] = value[23:16];
            dut.memory.bytes[idx + 3] = value[31:24];
            dut.memory.bytes[idx + 4] = value[39:32];
            dut.memory.bytes[idx + 5] = value[47:40];
            dut.memory.bytes[idx + 6] = value[55:48];
            dut.memory.bytes[idx + 7] = value[63:56];
        end
    endtask

    task clear_memory;
        integer i;
        begin
            for (i = 0; i < 512; i = i + 1)
                dut.memory.bytes[i] = 8'h00;

            for (i = START_PC; i < START_PC + 64'd256; i = i + 1)
                dut.memory.bytes[i] = 8'h00;
        end
    endtask

    task seed_reg;
        input [4:0] reg_idx;
        input [63:0] value;
        begin
            dut.reg_file.registers[reg_idx] = value;
        end
    endtask

    task check_reg;
        input [255:0] test_name;
        input [4:0] reg_idx;
        input [63:0] expected;
        reg [63:0] got;
        begin
            got = dut.reg_file.registers[reg_idx];
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL %-24s r%0d expected=%h got=%h", test_name, reg_idx, expected, got);
            end else begin
                $display("PASS %-24s r%0d=%h", test_name, reg_idx, got);
            end
        end
    endtask

    task check_mem64;
        input [255:0] test_name;
        input [63:0] addr;
        input [63:0] expected;
        reg [63:0] got;
        integer idx;
        begin
            idx = addr[31:0];
            got = { dut.memory.bytes[idx + 7], dut.memory.bytes[idx + 6],
                    dut.memory.bytes[idx + 5], dut.memory.bytes[idx + 4],
                    dut.memory.bytes[idx + 3], dut.memory.bytes[idx + 2],
                    dut.memory.bytes[idx + 1], dut.memory.bytes[idx + 0] };
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL %-24s addr=%h expected=%h got=%h", test_name, addr, expected, got);
            end else begin
                $display("PASS %-24s addr=%h value=%h", test_name, addr, got);
            end
        end
    endtask

    task check_pc;
        input [255:0] test_name;
        input [63:0] expected;
        begin
            if (dut.pc !== expected) begin
                errors = errors + 1;
                $display("FAIL %-24s pc expected=%h got=%h", test_name, expected, dut.pc);
            end else begin
                $display("PASS %-24s pc=%h", test_name, dut.pc);
            end
        end
    endtask

    task step_cycles;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1)
                @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        errors = 0;

        $dumpfile("sim/tinker_core_tb.vcd");
        $dumpvars(0, tinker_core_tb);

        clear_memory();

        write_instr(START_PC + 64'd0,   encode_i(OP_MOV_I,  5'd1,  5'd0,  5'd0, 12'd5));
        write_instr(START_PC + 64'd4,   encode_i(OP_MOV_I,  5'd2,  5'd0,  5'd0, 12'd3));
        write_instr(START_PC + 64'd8,   encode_r(OP_ADD,    5'd3,  5'd1,  5'd2));
        write_instr(START_PC + 64'd12,  encode_i(OP_ADDI,   5'd3,  5'd0,  5'd0, 12'd4));
        write_instr(START_PC + 64'd16,  encode_i(OP_SUBI,   5'd3,  5'd0,  5'd0, 12'd2));
        write_instr(START_PC + 64'd20,  encode_i(OP_SHFTLI, 5'd3,  5'd0,  5'd0, 12'd2));
        write_instr(START_PC + 64'd24,  encode_i(OP_SHFTRI, 5'd3,  5'd0,  5'd0, 12'd3));
        write_instr(START_PC + 64'd28,  encode_i(OP_MOV_I,  5'd4,  5'd0,  5'd0, 12'h080));
        write_instr(START_PC + 64'd32,  encode_i(OP_MOV_RM, 5'd4,  5'd3,  5'd0, 12'd8));
        write_instr(START_PC + 64'd36,  encode_i(OP_MOV_MR, 5'd5,  5'd4,  5'd0, 12'd8));
        write_instr(START_PC + 64'd40,  encode_r(OP_BRNZ,   5'd20, 5'd0,  5'd0));
        write_instr(START_PC + 64'd44,  encode_i(OP_MOV_I,  5'd6,  5'd0,  5'd0, 12'd1));
        write_instr(START_PC + 64'd48,  encode_r(OP_BRNZ,   5'd20, 5'd5,  5'd0));
        write_instr(START_PC + 64'd52,  encode_i(OP_MOV_I,  5'd7,  5'd0,  5'd0, 12'hBAD));
        write_instr(START_PC + 64'd56,  encode_i(OP_MOV_I,  5'd7,  5'd0,  5'd0, 12'hBAD));
        write_instr(START_PC + 64'd60,  encode_r(OP_BRGT,   5'd21, 5'd2,  5'd3));
        write_instr(START_PC + 64'd64,  encode_i(OP_MOV_I,  5'd8,  5'd0,  5'd0, 12'd1));
        write_instr(START_PC + 64'd68,  encode_r(OP_BRGT,   5'd22, 5'd3,  5'd2));
        write_instr(START_PC + 64'd72,  encode_i(OP_MOV_I,  5'd8,  5'd0,  5'd0, 12'hBAD));
        write_instr(START_PC + 64'd76,  encode_i(OP_MOV_I,  5'd8,  5'd0,  5'd0, 12'hBAD));
        write_instr(START_PC + 64'd80,  encode_i(OP_BRR_L,  5'd0,  5'd0,  5'd0, 12'd8));
        write_instr(START_PC + 64'd84,  encode_i(OP_MOV_I,  5'd9,  5'd0,  5'd0, 12'hBAD));
        write_instr(START_PC + 64'd88,  encode_r(OP_BRR_R,  5'd23, 5'd0,  5'd0));
        write_instr(START_PC + 64'd92,  encode_i(OP_MOV_I,  5'd9,  5'd0,  5'd0, 12'hBAD));
        write_instr(START_PC + 64'd96,  encode_i(OP_MOV_I,  5'd9,  5'd0,  5'd0, 12'hBAD));
        write_instr(START_PC + 64'd100, encode_r(OP_BR,     5'd24, 5'd0,  5'd0));
        write_instr(START_PC + 64'd104, encode_i(OP_MOV_I,  5'd9,  5'd0,  5'd0, 12'hBAD));
        write_instr(START_PC + 64'd108, encode_i(OP_MOV_I,  5'd9,  5'd0,  5'd0, 12'hBAD));
        write_instr(START_PC + 64'd112, encode_r(OP_MULF,   5'd13, 5'd10, 5'd11));
        write_instr(START_PC + 64'd116, encode_r(OP_DIVF,   5'd14, 5'd12, 5'd10));
        write_instr(START_PC + 64'd120, encode_r(OP_CALL,   5'd25, 5'd0,  5'd0));
        write_instr(START_PC + 64'd124, encode_i(OP_MOV_I,  5'd16, 5'd0,  5'd0, 12'd1));
        write_instr(START_PC + 64'd128, encode_r(OP_MOV_R,  5'd18, 5'd5,  5'd0));
        write_instr(START_PC + 64'd132, encode_r(OP_NOT,    5'd19, 5'd1,  5'd0));
        write_instr(START_PC + 64'd136, encode_r(OP_BR,     5'd26, 5'd0,  5'd0));
        write_instr(START_PC + 64'd140, encode_i(OP_MOV_I,  5'd17, 5'd0,  5'd0, 12'hBAD));
        write_instr(START_PC + 64'd144, encode_i(OP_MOV_I,  5'd15, 5'd0,  5'd0, 12'd2));
        write_instr(START_PC + 64'd148, encode_r(OP_RETURN, 5'd0,  5'd0,  5'd0));

        @(posedge clk);
        #1;
        reset = 1'b0;

        seed_reg(5'd20, START_PC + 64'd60);
        seed_reg(5'd21, START_PC + 64'd72);
        seed_reg(5'd22, START_PC + 64'd80);
        seed_reg(5'd23, 64'd12);
        seed_reg(5'd24, START_PC + 64'd112);
        seed_reg(5'd25, START_PC + 64'd144);
        seed_reg(5'd26, START_PC + 64'd152);
        seed_reg(5'd10, 64'h4000_0000_0000_0000);
        seed_reg(5'd11, 64'h4008_0000_0000_0000);
        seed_reg(5'd12, 64'h4018_0000_0000_0000);

        step_cycles(29);

        check_reg("mov_i/add/sub/shift", 5'd3, 64'd5);
        check_reg("load after store",    5'd5, 64'd5);
        check_reg("brnz not taken path", 5'd6, 64'd1);
        check_reg("brnz taken skip",     5'd7, 64'd0);
        check_reg("brgt not taken path", 5'd8, 64'd1);
        check_reg("brr skip markers",    5'd9, 64'd0);
        check_reg("mulf 2*3",            5'd13, 64'h4018_0000_0000_0000);
        check_reg("divf 6/2",            5'd14, 64'h4008_0000_0000_0000);
        check_reg("call subroutine ran", 5'd15, 64'd2);
        check_reg("returned to caller",  5'd16, 64'd1);
        check_reg("branch over callee",  5'd17, 64'd0);
        check_reg("mov_r final",         5'd18, 64'd5);
        check_reg("not final",           5'd19, 64'hFFFF_FFFF_FFFF_FFFA);
        check_mem64("stored value",      DATA_BASE + 64'd8, 64'd5);
        check_mem64("return addr pushed", 64'h0000_0000_0007_FFF8, START_PC + 64'd124);
        check_reg("stack ptr restored",  5'd31, 64'h0000_0000_0008_0000);
        check_pc("pc after program", START_PC + 64'd156);

        if (errors == 0)
            $display("All tinker_core tests passed.");
        else
            $display("tinker_core tests finished with %0d failure(s).", errors);

        $finish;
    end
endmodule
