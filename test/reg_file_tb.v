`timescale 1ns/1ps

module reg_file_tb;
    reg         clk;
    reg         reset;
    reg  [4:0]  rd_addr;
    reg  [63:0] wr_data;
    reg         wr_en;
    reg  [4:0]  rs_addr;
    reg  [4:0]  rt_addr;
    reg  [4:0]  ru_addr;
    wire [63:0] rs_data;
    wire [63:0] rt_data;
    wire [63:0] ru_data;

    integer errors;

    reg_file dut (
        .clk(clk),
        .reset(reset),
        .rd_addr(rd_addr),
        .wr_data(wr_data),
        .wr_en(wr_en),
        .rs_addr(rs_addr),
        .rs_data(rs_data),
        .rt_addr(rt_addr),
        .rt_data(rt_data),
        .ru_addr(ru_addr),
        .ru_data(ru_data)
    );

    always #5 clk = ~clk;

    task check_read;
        input [255:0] test_name;
        input [63:0] exp_rs;
        input [63:0] exp_rt;
        input [63:0] exp_ru;
        begin
            #1;
            if (rs_data !== exp_rs || rt_data !== exp_rt || ru_data !== exp_ru) begin
                errors = errors + 1;
                $display("FAIL %-20s rs=%h/%h rt=%h/%h ru=%h/%h",
                         test_name, rs_data, exp_rs, rt_data, exp_rt, ru_data, exp_ru);
            end else begin
                $display("PASS %-20s rs=%h rt=%h ru=%h", test_name, rs_data, rt_data, ru_data);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/reg_file_tb.vcd");
        $dumpvars(0, reg_file_tb);

        clk = 1'b0;
        reset = 1'b1;
        rd_addr = 5'd0;
        wr_data = 64'd0;
        wr_en = 1'b0;
        rs_addr = 5'd0;
        rt_addr = 5'd0;
        ru_addr = 5'd31;
        errors = 0;

        @(posedge clk);
        #1;
        check_read("reset state", 64'd0, 64'd0, 64'd524288);

        reset = 1'b0;
        @(posedge clk);
        #1;

        rd_addr = 5'd3;
        wr_data = 64'h0123_4567_89AB_CDEF;
        wr_en = 1'b1;
        @(posedge clk);
        #1;
        wr_en = 1'b0;
        rs_addr = 5'd3;
        rt_addr = 5'd0;
        ru_addr = 5'd31;
        check_read("write r3", 64'h0123_4567_89AB_CDEF, 64'd0, 64'd524288);

        rd_addr = 5'd7;
        wr_data = 64'hFFFF_0000_AAAA_5555;
        wr_en = 1'b1;
        @(posedge clk);
        #1;
        wr_en = 1'b0;
        rs_addr = 5'd3;
        rt_addr = 5'd7;
        ru_addr = 5'd31;
        check_read("multi-port read",
                   64'h0123_4567_89AB_CDEF,
                   64'hFFFF_0000_AAAA_5555,
                   64'd524288);

        rd_addr = 5'd3;
        wr_data = 64'hDEAD_BEEF_DEAD_BEEF;
        wr_en = 1'b0;
        @(posedge clk);
        #1;
        rs_addr = 5'd3;
        rt_addr = 5'd7;
        ru_addr = 5'd31;
        check_read("write disabled",
                   64'h0123_4567_89AB_CDEF,
                   64'hFFFF_0000_AAAA_5555,
                   64'd524288);

        rd_addr = 5'd31;
        wr_data = 64'h0000_0000_0000_1234;
        wr_en = 1'b1;
        @(posedge clk);
        #1;
        wr_en = 1'b0;
        rs_addr = 5'd31;
        rt_addr = 5'd7;
        ru_addr = 5'd3;
        check_read("write r31",
                   64'h0000_0000_0000_1234,
                   64'hFFFF_0000_AAAA_5555,
                   64'h0123_4567_89AB_CDEF);

        reset = 1'b1;
        @(posedge clk);
        #1;
        rs_addr = 5'd3;
        rt_addr = 5'd7;
        ru_addr = 5'd31;
        check_read("reset clears",
                   64'd0,
                   64'd0,
                   64'd524288);

        if (errors == 0)
            $display("All reg_file tests passed.");
        else
            $display("reg_file tests finished with %0d failure(s).", errors);

        $finish;
    end
endmodule
