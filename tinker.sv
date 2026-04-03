`ifndef MEM_SIZE
`define MEM_SIZE 524288
`endif

module tinker_core(
    input clk,
    input reset
);
   
    wire [63:0] pc;
    reg  [63:0] next_pc;

    wire [31:0] instr;

  
    wire [4:0]  read_addr_a;
    wire [4:0]  read_addr_b;
    wire [4:0]  read_addr_c;
    wire [4:0]  write_addr;
    wire        write_en_dec;

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

    // Register file outputs
    wire [63:0] reg_data_a;
    wire [63:0] reg_data_b;
    wire [63:0] reg_data_c;

    
    wire [63:0] alu_b = use_imm ? imm : reg_data_b;
    wire [63:0] alu_result;

    //address for load store
    wire [63:0] data_rdata;
    wire [63:0] mem_addr = reg_data_a + imm;

    // Loads write the value coming back from memory.
    wire [63:0] write_back_data = mem_read ? data_rdata : alu_result;

    //are we writing or nah
    wire write_back_en = write_en_dec & ~illegal & ~call & ~ret &
                                ~branch_abs & ~branch_rel & ~branch_nz & ~branch_gt;

    
    // The fetch module owns the program counter register.
    // On reset: PC becomes 0x2000.
    // On each later clock edge: PC becomes `next_pc`.
    //should have direct access to memory?
    fetch_unit fetch (
        .clk(clk),
        .reset(reset),
        .next_pc(next_pc),
        .pc(pc)
    );

    
    decoder decoder (
        .instr(instr),
        .read_addr_a(read_addr_a),
        .read_addr_b(read_addr_b),
        .read_addr_c(read_addr_c),
        .write_addr(write_addr),
        .write_en(write_en_dec),
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


    //register reads combinational, values to read appear after decoder gets reg numbers
    //register writes are synchronous, data written on rising edge if write_back_en is high
    reg_file reg_file (
        .clk(clk),
        .reset(reset),
        .rd_addr(write_addr),
        .wr_data(write_back_data),
        .wr_en(write_back_en),
        .rs_addr(read_addr_a),
        .rs_data(reg_data_a),
        .rt_addr(read_addr_b),
        .rt_data(reg_data_b),
        .ru_addr(read_addr_c),
        .ru_data(reg_data_c)
    );

    alu alu (
        .a(reg_data_a),
        .b(alu_b),
        .op(alu_op),
        .result(alu_result)
    );

   
    // 1. Instruction fetch: read the PC and get the instruction at that PC
    // 2. Data access: read/write 8-byte values for load/store instructions.
    tinker_memory memory (
        .clk(clk),
        .instr_addr(pc),
        .instr(instr),
        .data_addr(mem_addr),
        .data_wdata(reg_data_b),
        .data_we(mem_write & ~illegal),
        .data_rdata(data_rdata)
    );

    /*always@(*) begin
        if(reset = )
    end*/
  //next pc logic
    always @(*) begin
        next_pc = pc + 64'd4;

        if (branch_abs) begin
            next_pc = reg_data_c;
        end else if (branch_rel) begin
            next_pc = use_imm ? (pc + imm) : (pc + reg_data_c);
        end else if (branch_nz) begin
            next_pc = (reg_data_a != 64'd0) ? reg_data_c : (pc + 64'd4);
        end else if (branch_gt) begin
            next_pc = ($signed(reg_data_a) > $signed(reg_data_b)) ? reg_data_c
                                                                   : (pc + 64'd4);
        end else if (call) begin
            next_pc = reg_data_c;
            //TODO: decrement stack pointer by 8 and write pc + 4 there
        end else if (ret) begin
            //TODO: supposed to read memory at r31 - 8 and jump there
            next_pc = data_rdata;
        end
    end

    // Debug trace for instruction decode, ALU inputs/outputs, and writeback.
    // Enable with: iverilog ... -DTRACE_TINKER
`ifdef TRACE_TINKER
    always @(posedge clk) begin
        if (!reset) begin
            $display(
                "TRACE pc=%h instr=%h opcode=%02h rd=%0d rs=%0d rt=%0d | ra=%0d rb=%0d rc=%0d wa=%0d | A=%h B=%h IMM=%h use_imm=%b | alu_op=%02h alu_res=%h | mem_r=%b mem_w=%b data_r=%h | wr_dec=%b wr_en=%b illegal=%b | br_abs=%b br_rel=%b br_nz=%b br_gt=%b call=%b ret=%b | next_pc=%h",
                pc, instr, instr[4:0], instr[9:5], instr[14:10], instr[19:15],
                read_addr_a, read_addr_b, read_addr_c, write_addr,
                reg_data_a, reg_data_b, imm, use_imm,
                alu_op, alu_result,
                mem_read, mem_write, data_rdata,
                write_en_dec, write_back_en, illegal,
                branch_abs, branch_rel, branch_nz, branch_gt, call, ret,
                next_pc
            );
        end
    end
`endif
endmodule

module fetch_unit(
    input        clk,
    input        reset,
    input  [63:0] next_pc,
    output reg [63:0] pc
);
    
    always @(posedge clk) begin
        if (reset) begin
            //begin at address 0x2000.
            pc <= 64'h0000_0000_0000_2000;
        end else begin
            pc <= next_pc;
        end
    end
endmodule

module tinker_memory(
    input         clk,
    input  [63:0] instr_addr,
    output [31:0] instr,
    input  [63:0] data_addr,
    input  [63:0] data_wdata,
    input         data_we,
    output [63:0] data_rdata
);
    reg [7:0] bytes [0:`MEM_SIZE-1];

    wire [31:0] instr_index = instr_addr[31:0];
    wire [31:0] data_index  = data_addr[31:0];

    //instruction fetch
    assign instr = { bytes[instr_index + 32'd3],
                     bytes[instr_index + 32'd2],
                     bytes[instr_index + 32'd1],
                     bytes[instr_index + 32'd0] };


    assign data_rdata = { bytes[data_index + 32'd7],
                          bytes[data_index + 32'd6],
                          bytes[data_index + 32'd5],
                          bytes[data_index + 32'd4],
                          bytes[data_index + 32'd3],
                          bytes[data_index + 32'd2],
                          bytes[data_index + 32'd1],
                          bytes[data_index + 32'd0] };

    
    always @(posedge clk) begin
        if (data_we) begin
            bytes[data_index + 32'd0] <= data_wdata[7:0];
            bytes[data_index + 32'd1] <= data_wdata[15:8];
            bytes[data_index + 32'd2] <= data_wdata[23:16];
            bytes[data_index + 32'd3] <= data_wdata[31:24];
            bytes[data_index + 32'd4] <= data_wdata[39:32];
            bytes[data_index + 32'd5] <= data_wdata[47:40];
            bytes[data_index + 32'd6] <= data_wdata[55:48];
            bytes[data_index + 32'd7] <= data_wdata[63:56];
        end
    end
endmodule

module alu(
    input logic [63:0] a,
    input logic [63:0] b,
    input logic [4:0] op,
    output logic [63:0] result
);

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

    always_comb begin
        case (op)
            ADD:  result = a + b;
            SUB:  result = a - b;
            MUL: result = a * b;
            DIV: result = a / b;
            AND:  result = a & b;
            OR:   result = a | b;
            XOR:  result = a ^ b;
            NOT:  result = ~a;

            LSHIFT: result = a << b[5:0];
            RSHIFT: result = a >> b[5:0];
            MOV: result = b;

            ADDF: result = fp_add(a, b);
            SUBF: result = fp_add(a, { ~b[63], b[62:0] });
            MULF: result = fp_mul(a, b);
            DIVF: result = fp_div(a, b);
            default:  result = 64'b0;
        endcase
    end
endmodule

function [63:0] fp_add;
    input [63:0] x;
    input [63:0] y;

    reg sx, sy, sr;     // signs
    reg [10:0] ex, ey, er;     // biased exponents
    reg [52:0] mx, my;         // mantissas
    reg [54:0] sum;            // handles carry out of addition
                               //   bit 54: overflow carry
                               //   bit 53: would-be carry after right-normalize
                               //   bits 52:0: significand bits
    reg [10:0] shift;         
    integer    i;              

    begin
        sx = x[63];   
        ex = x[62:52];   
        mx = { 1'b1, x[51:0] };

        sy = y[63];   
        ey = y[62:52];   
        my = { 1'b1, y[51:0] };

        if (ex == 11'd0) mx = 53'd0;
        if (ey == 11'd0) my = 53'd0;

        //align exponents
        if (ex >= ey) begin
            shift = ex - ey;
            my = my >> shift;
            er = ex;
        end else begin
            shift = ey - ex;
            mx = mx >> shift;
            er = ey;
        end

        //add or subtract
        if (sx == sy) begin 
            //same sign
            sum = { 2'b0, mx } + { 2'b0, my };
            sr  = sx;
        end else begin
            // different signs: subtract smaller magnitude from larger.
            if (mx >= my) begin
                sum = { 2'b0, mx } - { 2'b0, my };
                sr  = sx;
            end else begin
                sum = { 2'b0, my } - { 2'b0, mx };
                sr  = sy;
            end
        end

      //normalize carry
        if (sum[53]) begin
            sum = sum >> 1;
            er  = er + 11'd1;
        end else begin
            for (i = 0; i < 52; i = i + 1) begin
                if (!sum[52] && er > 11'd1) begin
                    sum = sum << 1;
                    er  = er - 11'd1;
                end
            end
        end

        if (sum[52:0] == 53'd0)
            fp_add = 64'd0;
        else
            fp_add = { sr, er, sum[51:0] };
end
endfunction

function integer fp_msb106;
    input [105:0] value;
    integer i;
    begin
        fp_msb106 = 0;
        for (i = 0; i < 106; i = i + 1)
            if (value[i])
                fp_msb106 = i;
    end
endfunction

function [63:0] fp_pack;
    input        sign;
    input integer exp_unb;
    input [52:0] mant;

    integer shift;
    reg [52:0] sub_mant;
    reg [10:0] biased_exp;

    begin
        if (mant == 53'd0) begin
            fp_pack = { sign, 11'd0, 52'd0 };
        end else if (exp_unb > 1023) begin
            fp_pack = { sign, 11'h7FF, 52'd0 };
        end else if (exp_unb >= -1022) begin
            biased_exp = exp_unb + 1023;
            fp_pack = { sign, biased_exp, mant[51:0] };
        end else begin
            shift = -1022 - exp_unb;
            if (shift > 52)
                sub_mant = 53'd0;
            else
                sub_mant = mant >> shift;

            if (sub_mant == 53'd0)
                fp_pack = { sign, 11'd0, 52'd0 };
            else
                fp_pack = { sign, 11'd0, sub_mant[51:0] };
        end
    end
endfunction

function [63:0] fp_mul;
    input [63:0] x;
    input [63:0] y;

    reg        sx, sy, sr;
    reg [10:0] ex, ey;
    reg [51:0] fx, fy;
    reg [52:0] mx, my;
    reg [105:0] product;
    reg [105:0] norm_product;
    reg        x_is_zero, y_is_zero;
    reg        x_is_inf,  y_is_inf;
    reg        x_is_nan,  y_is_nan;
    integer    ex_unb, ey_unb, er_unb;
    integer    msb_index, shift;

    begin
        sx = x[63];   ex = x[62:52];   fx = x[51:0];
        sy = y[63];   ey = y[62:52];   fy = y[51:0];
        sr = sx ^ sy;

        x_is_zero = (ex == 11'd0)   && (fx == 52'd0);
        y_is_zero = (ey == 11'd0)   && (fy == 52'd0);
        x_is_inf  = (ex == 11'h7FF) && (fx == 52'd0);
        y_is_inf  = (ey == 11'h7FF) && (fy == 52'd0);
        x_is_nan  = (ex == 11'h7FF) && (fx != 52'd0);
        y_is_nan  = (ey == 11'h7FF) && (fy != 52'd0);

        if (x_is_nan || y_is_nan || ((x_is_inf || y_is_inf) && (x_is_zero || y_is_zero))) begin
            fp_mul = 64'h7FF8_0000_0000_0000;
        end else if (x_is_inf || y_is_inf) begin
            fp_mul = { sr, 11'h7FF, 52'd0 };
        end else if (x_is_zero || y_is_zero) begin
            fp_mul = { sr, 11'd0, 52'd0 };
        end else begin
            mx = (ex == 11'd0) ? { 1'b0, fx } : { 1'b1, fx };
            my = (ey == 11'd0) ? { 1'b0, fy } : { 1'b1, fy };
            ex_unb = (ex == 11'd0) ? -1022 : (ex - 1023);
            ey_unb = (ey == 11'd0) ? -1022 : (ey - 1023);
            product = mx * my;
            msb_index = fp_msb106(product);
            shift = msb_index - 52;
            norm_product = product;
            if (shift > 0)
                norm_product = product >> shift;
            else if (shift < 0)
                norm_product = product << (-shift);
            er_unb = ex_unb + ey_unb + msb_index - 104;
            fp_mul = fp_pack(sr, er_unb, norm_product[52:0]);
        end
    end
endfunction


function [63:0] fp_div;
    input [63:0] x;
    input [63:0] y;

    reg        sx, sy, sr;
    reg [10:0] ex, ey;
    reg [51:0] fx, fy;
    reg [52:0] mx, my;
    reg [105:0] dividend;
    reg [105:0] quotient;
    reg [105:0] norm_quotient;
    reg        x_is_zero, y_is_zero;
    reg        x_is_inf,  y_is_inf;
    reg        x_is_nan,  y_is_nan;
    integer    ex_unb, ey_unb, er_unb;
    integer    msb_index, shift;
    begin
        sx = x[63];   ex = x[62:52];   fx = x[51:0];
        sy = y[63];   ey = y[62:52];   fy = y[51:0];
        sr = sx ^ sy;

        x_is_zero = (ex == 11'd0)   && (fx == 52'd0);
        y_is_zero = (ey == 11'd0)   && (fy == 52'd0);
        x_is_inf  = (ex == 11'h7FF) && (fx == 52'd0);
        y_is_inf  = (ey == 11'h7FF) && (fy == 52'd0);
        x_is_nan  = (ex == 11'h7FF) && (fx != 52'd0);
        y_is_nan  = (ey == 11'h7FF) && (fy != 52'd0);

        if (x_is_nan || y_is_nan || (x_is_zero && y_is_zero) || (x_is_inf && y_is_inf)) begin
            fp_div = 64'h7FF8_0000_0000_0000;
        end else if (x_is_inf) begin
            fp_div = { sr, 11'h7FF, 52'd0 };
        end else if (y_is_inf) begin
            fp_div = { sr, 11'd0, 52'd0 };
        end else if (y_is_zero) begin
            fp_div = { sr, 11'h7FF, 52'd0 };
        end else if (x_is_zero) begin
            fp_div = { sr, 11'd0, 52'd0 };
        end else begin
            mx = (ex == 11'd0) ? { 1'b0, fx } : { 1'b1, fx };
            my = (ey == 11'd0) ? { 1'b0, fy } : { 1'b1, fy };
            ex_unb = (ex == 11'd0) ? -1022 : (ex - 1023);
            ey_unb = (ey == 11'd0) ? -1022 : (ey - 1023);

            dividend = { 1'b0, mx, 52'b0 };
            quotient = dividend / my;
            msb_index = fp_msb106(quotient);
            shift = msb_index - 52;
            norm_quotient = quotient;
            if (shift > 0)
                norm_quotient = quotient >> shift;
            else if (shift < 0)
                norm_quotient = quotient << (-shift);
            er_unb = ex_unb - ey_unb + msb_index - 52;
            fp_div = fp_pack(sr, er_unb, norm_quotient[52:0]);
        end
    end
endfunction



`define MEM_SIZE 524288   // 512 KB

module reg_file (
    input             clk,
    input             reset,

    input      [4:0]  rd_addr,   // which register to write (0–31)
    input      [63:0] wr_data,   // value to write
    input             wr_en,     // 1 = write, 0 = no write

    input      [4:0]  rs_addr,   // 1st register to read
    output     [63:0] rs_data,   // its current value

    input      [4:0]  rt_addr,   // 2nd register to read
    output     [63:0] rt_data,   // its current value

    input      [4:0]  ru_addr,   // 3rd register to read
    output     [63:0] ru_data    // its current value
);

reg [63:0] registers [0:31];

assign rs_data = registers[rs_addr];
assign rt_data = registers[rt_addr];
assign ru_data = registers[ru_addr];


always @(posedge clk) begin //only on rising edge of clock, everything else (fetch, decode, ALU) during clock

    if (reset) begin
        //clear registers and set stack pointer to top of memory
        integer i;
        for (i = 0; i < 32; i = i + 1)
            registers[i] <= 64'd0;
       
        registers[31] <= `MEM_SIZE;

    end else if (wr_en) begin      
        registers[rd_addr] <= wr_data;
    end
    //if wr_en 0 = flip flops just hold their value
end

endmodule


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
    wire [4:0] opcode = instr[31:27];
    wire [4:0] rd     = instr[26:22];
    wire [4:0] rs     = instr[21:17];
    wire [4:0] rt     = instr[16:12];

    wire [11:0] L12 = instr[11:0];

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
