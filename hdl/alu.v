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

function [63:0] fp_mul;
    input [63:0] x;
    input [63:0] y;

    reg        sx, sy, sr;
    reg [10:0] ex, ey, er;
    reg [52:0] mx, my;
    reg [105:0] product;

    begin
        sx = x[63];   ex = x[62:52];   mx = { 1'b1, x[51:0] };
        sy = y[63];   ey = y[62:52];   my = { 1'b1, y[51:0] };

        if (ex == 11'd0 || ey == 11'd0) begin
            fp_mul = 64'd0;
        end else begin
            sr = sx ^ sy;

            er = ex + ey - 11'd1023;

            product = mx * my;

           //normalize
            if (product[105]) begin
                fp_mul = { sr, er, product[104:53] };
            end else begin
                fp_mul = { sr, er - 11'd1, product[103:52] };
            end
        end
    end
endfunction


function [63:0] fp_div;
    input [63:0] x;
    input [63:0] y;

    reg        sx, sy, sr;
    reg [10:0] ex, ey, er;
    reg [52:0] mx, my;
    reg [105:0] dividend;
    reg [52:0]  quotient; 
    begin
        sx = x[63];   ex = x[62:52];   mx = { 1'b1, x[51:0] };
        sy = y[63];   ey = y[62:52];   my = { 1'b1, y[51:0] };

        // zero dividend -> result is 0
        if (ex == 11'd0) begin
            fp_div = 64'd0;
        end else begin
            sr = sx ^ sy;

            er = ex - ey + 11'd1023;

            dividend = { mx, 53'b0 };
            quotient = dividend / { 53'b0, my };

            //normalize
            if (quotient[52]) begin
                fp_div = { sr, er, quotient[51:0] };
            end else begin
                fp_div = { sr, er - 11'd1, quotient[50:0], 1'b0 };
            end
        end
    end
endfunction
