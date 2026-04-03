`timescale 1ns/1ps

module tinker_core_tb;
    reg clk;
    reg reset;

    integer errors;

    localparam START_PC = 64'h0000_0000_0000_2000;

    localparam OP_AND = 5'h00;
    localparam OP_OR  = 5'h01;
    localparam OP_XOR = 5'h02;
    localparam OP_NOT = 5'h03;
    localparam OP_MULF = 5'h16;
    localparam OP_DIVF = 5'h17;

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

    task clear_memory;
        integer i;
        begin
            for (i = 0; i < 256; i = i + 1)
                dut.memory.bytes[i] = 8'h00;

            for (i = START_PC; i < START_PC + 64'd64; i = i + 1)
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
                $display("FAIL %-20s r%0d expected=%h got=%h", test_name, reg_idx, expected, got);
            end else begin
                $display("PASS %-20s r%0d=%h", test_name, reg_idx, got);
            end
        end
    endtask

    task step_cycles;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1)
                @(posedge clk);
            #5;
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        errors = 0;

        $dumpfile("sim/tinker_core_tb.vcd");
        $dumpvars(0, tinker_core_tb);

        clear_memory();

        // Program:
        //   r4  = r1 & r2
        //   r5  = r1 | r2
        //   r6  = r1 ^ r2
        //   r7  = ~r3
        //   r13 = r10 * r11   (2.0 * 3.0 = 6.0)
        //   r14 = r12 / r10   (6.0 / 2.0 = 3.0)
        write_instr(START_PC + 64'd0,  encode_r(OP_AND, 5'd4, 5'd1, 5'd2));
        write_instr(START_PC + 64'd4,  encode_r(OP_OR,   5'd5,  5'd1,  5'd2));
        write_instr(START_PC + 64'd8,  encode_r(OP_XOR,  5'd6,  5'd1,  5'd2));
        write_instr(START_PC + 64'd12, encode_r(OP_NOT,  5'd7,  5'd3,  5'd0));
        write_instr(START_PC + 64'd16, encode_r(OP_MULF, 5'd13, 5'd10, 5'd11));
        write_instr(START_PC + 64'd20, encode_r(OP_DIVF, 5'd14, 5'd12, 5'd10));

        @(posedge clk);
        #5;

        reset = 1'b0;
        seed_reg(5'd1, 64'h0000_0000_0000_F0F0);
        seed_reg(5'd2, 64'h0000_0000_0000_0FF0);
        seed_reg(5'd3, 64'h0000_0000_0000_00F0);
        seed_reg(5'd10, 64'h4000_0000_0000_0000);
        seed_reg(5'd11, 64'h4008_0000_0000_0000);
        seed_reg(5'd12, 64'h4018_0000_0000_0000);

        step_cycles(6);

        check_reg("and", 5'd4, 64'h0000_0000_0000_00F0);
        check_reg("or",  5'd5, 64'h0000_0000_0000_FFF0);
        check_reg("xor", 5'd6, 64'h0000_0000_0000_FF00);
        check_reg("not", 5'd7, 64'hFFFF_FFFF_FFFF_FF0F);
        check_reg("mulf 2*3", 5'd13, 64'h4018_0000_0000_0000);
        check_reg("divf 6/2", 5'd14, 64'h4008_0000_0000_0000);

        if (errors == 0)
            $display("All tinker_core logic tests passed.");
        else
            $display("tinker_core logic tests finished with %0d failure(s).", errors);

        $finish;
    end
endmodule
