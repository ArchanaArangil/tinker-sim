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
