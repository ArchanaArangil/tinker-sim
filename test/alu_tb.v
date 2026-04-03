`timescale 1ns/1ps

module alu_tb;
    reg  [63:0] a;
    reg  [63:0] b;
    reg  [4:0]  op;
    wire [63:0] result;

    integer errors;

    localparam ADD    = 5'h00;
    localparam SUB    = 5'h01;
    localparam AND    = 5'h02;
    localparam OR     = 5'h03;
    localparam XOR    = 5'h04;
    localparam NOT    = 5'h05;
    localparam LSHIFT = 5'h06;
    localparam RSHIFT = 5'h07;
    localparam MUL    = 5'h08;
    localparam DIV    = 5'h09;
    localparam MOV    = 5'h0A;
    localparam ADDF   = 5'h0B;
    localparam SUBF   = 5'h0C;
    localparam MULF   = 5'h0D;
    localparam DIVF   = 5'h0E;

    alu dut (
        .a(a),
        .b(b),
        .op(op),
        .result(result)
    );

    task check_result;
        input [255:0] test_name;
        input [63:0] expected;
        begin
            #1;
            if (result !== expected) begin
                errors = errors + 1;
                $display("FAIL %-20s op=%h a=%h b=%h expected=%h got=%h",
                         test_name, op, a, b, expected, result);
            end else begin
                $display("PASS %-20s result=%h", test_name, result);
            end
        end
    endtask

    initial begin
        errors = 0;
        a = 64'h0;
        b = 64'h0;
        op = 5'h00;

        $dumpfile("sim/alu_tb.vcd");
        $dumpvars(0, alu_tb);

        a = 64'd10; b = 64'd3; op = ADD;
        check_result("add", 64'd13);

        a = 64'd10; b = 64'd3; op = SUB;
        check_result("sub", 64'd7);

        a = 64'hF0F0; b = 64'h0FF0; op = AND;
        check_result("and", 64'h00F0);

        a = 64'hF0F0; b = 64'h0FF0; op = OR;
        check_result("or", 64'hFFF0);

        a = 64'hAAAA; b = 64'h0F0F; op = XOR;
        check_result("xor", 64'hA5A5);

        a = 64'h0000_0000_0000_00F0; b = 64'h0; op = NOT;
        check_result("not", 64'hFFFF_FFFF_FFFF_FF0F);

        a = 64'd5; b = 64'd2; op = LSHIFT;
        check_result("lshift", 64'd20);

        a = 64'd20; b = 64'd2; op = RSHIFT;
        check_result("rshift", 64'd5);

        a = 64'd6; b = 64'd7; op = MUL;
        check_result("mul", 64'd42);

        a = 64'd42; b = 64'd7; op = DIV;
        check_result("div", 64'd6);

        a = 64'h1234_5678_9ABC_DEF0; b = 64'h0BAD_F00D_DEAD_BEEF; op = MOV;
        check_result("mov", 64'h0BAD_F00D_DEAD_BEEF);

        a = 64'h3FF0_0000_0000_0000; b = 64'h4000_0000_0000_0000; op = ADDF;
        check_result("addf 1+2", 64'h4008_0000_0000_0000);

        a = 64'h4008_0000_0000_0000; b = 64'h3FF0_0000_0000_0000; op = SUBF;
        check_result("subf 3-1", 64'h4000_0000_0000_0000);

        a = 64'h4000_0000_0000_0000; b = 64'h4008_0000_0000_0000; op = MULF;
        check_result("mulf 2*3", 64'h4018_0000_0000_0000);

        a = 64'h3FF8_0000_0000_0000; b = 64'h3FF8_0000_0000_0000; op = MULF;
        check_result("mulf 1.5*1.5", 64'h4002_0000_0000_0000);

        a = 64'hBFF8_0000_0000_0000; b = 64'h4008_0000_0000_0000; op = MULF;
        check_result("mulf -1.5*3", 64'hC012_0000_0000_0000);

        a = 64'h4018_0000_0000_0000; b = 64'h4000_0000_0000_0000; op = DIVF;
        check_result("divf 6/2", 64'h4008_0000_0000_0000);

        a = 64'h4008_0000_0000_0000; b = 64'h4000_0000_0000_0000; op = DIVF;
        check_result("divf 3/2", 64'h3FF8_0000_0000_0000);

        a = 64'h3FF0_0000_0000_0000; b = 64'h4000_0000_0000_0000; op = DIVF;
        check_result("divf 1/2", 64'h3FE0_0000_0000_0000);

        a = 64'hBFF0_0000_0000_0000; b = 64'h0000_0000_0000_0000; op = DIVF;
        check_result("divf -1/0", 64'hFFF0_0000_0000_0000);

        a = 64'h1; b = 64'h2; op = 5'h1F;
        check_result("default", 64'h0);

        if (errors == 0) begin
            $display("All ALU tests passed.");
        end else begin
            $display("ALU tests finished with %0d failure(s).", errors);
        end

        $finish;
    end
endmodule
