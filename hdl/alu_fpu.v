// =============================================================================
// alu_fpu.v  –  ALU and FPU for the Tinker CPU
// =============================================================================
//
// What this module does
// ---------------------
// Takes two 64-bit operands (a, b) and a 5-bit operation code (op), and
// produces a 64-bit result every time the inputs change.  There is no clock –
// this is purely *combinational* logic (think of it like a big lookup table
// that continuously recomputes its output whenever an input changes).
//
// Where it sits in the pipeline
// ------------------------------
//   Fetch → Decode → RegFile ──(rs_data / rt_data)──► ALU_FPU ──► RegFile write
//                       │                                 ▲
//                       └────────────(alu_op)─────────────┘
//
// The decoder extracts the opcode from the instruction and maps it to one of
// the OP_* codes defined below.  The register file feeds a and b.
//
// How the file is organized
// -------------------------
//   1. Port declarations
//   2. Operation-code parameters (the "menu" of operations)
//   3. IEEE 754 field extraction wires (for FP)
//   4. Main always @(*) block that dispatches to the right operation
//   5. Three helper functions:  fp_add, fp_mul, fp_div
//      Each function is self-contained and thoroughly commented.
//
// =============================================================================

module alu_fpu (
    input  [63:0] a,          // Operand 1  (usually rs value from register file)
    input  [63:0] b,          // Operand 2  (rt value, or sign-extended immediate)
    input  [4:0]  op,         // Which operation to perform (OP_* codes below)
    output reg [63:0] result  // Computed result (goes back to register file)
);

// =============================================================================
// SECTION 1 – Operation codes
// =============================================================================
//
// The decoder will set `op` to one of these values.  Using named parameters
// instead of raw numbers makes the code readable and avoids typos.
//
// Integer ops occupy codes 0-15; floating-point ops occupy 16-31.
// That split is just a convention – it has no hardware significance.
// =============================================================================

// --- Integer / bitwise operations ---
localparam OP_ADD     = 5'd0;   // a + b           (signed 64-bit)
localparam OP_SUB     = 5'd1;   // a - b
localparam OP_MUL     = 5'd2;   // a * b           (lower 64 bits of product)
localparam OP_AND     = 5'd3;   // a & b
localparam OP_OR      = 5'd4;   // a | b
localparam OP_XOR     = 5'd5;   // a ^ b
localparam OP_NOT     = 5'd6;   // ~a              (unary – only uses a)
localparam OP_LSHIFT  = 5'd7;   // a << b[5:0]     (logical left shift)
localparam OP_RSHIFT  = 5'd8;   // a >> b[5:0]     (logical right shift, fills 0s)
localparam OP_RSHIFTA = 5'd9;   // a >>> b[5:0]    (arithmetic shift, fills sign bit)

// --- Data-movement operations ---
// The decoder controls what goes into a and b, so these are simple pass-throughs.
localparam OP_MOV     = 5'd10;  // result = b  (copy rs or immediate into rd)
localparam OP_MOVL    = 5'd11;  // result = { a[63:16], b[15:0] }
                                //   Load a 16-bit immediate into the LOWER 16 bits.
                                //   Upper 48 bits come from the current rd value (a).
localparam OP_MOVH    = 5'd12;  // result = { b[15:0], a[47:0] }
                                //   Load a 16-bit immediate into the UPPER 16 bits.
                                //   Lower 48 bits come from the current rd value (a).

// --- Floating-point operations (IEEE 754 double precision) ---
//
// IEEE 754 double layout (64 bits total):
//
//   63      62      52        51                              0
//   ┌───┬─────────────┬────────────────────────────────────────┐
//   │ S │  Exponent   │              Mantissa                  │
//   │(1)│  (11 bits)  │              (52 bits)                 │
//   └───┴─────────────┴────────────────────────────────────────┘
//
//   S         – sign bit  (0 = positive, 1 = negative)
//   Exponent  – stored with a bias of 1023
//                 actual_exponent = stored_exponent - 1023
//   Mantissa  – fractional part of the significand
//                 there is always an *implicit* leading 1 bit, so
//                 the full significand is  1.mantissa  (value in [1.0, 2.0))
//
// Example: 1.0
//   S=0, exponent = 1023 (stored) = 0 (actual), mantissa = 0
//   bits: 0_01111111111_0000...0
//
localparam OP_FADD    = 5'd16;  // a + b  (floating point)
localparam OP_FSUB    = 5'd17;  // a - b  (floating point)
localparam OP_FMUL    = 5'd18;  // a * b  (floating point)
localparam OP_FDIV    = 5'd19;  // a / b  (floating point)


// =============================================================================
// SECTION 2 – IEEE 754 field extraction
// =============================================================================
//
// Rather than typing a[63], a[62:52], a[51:0] everywhere, we give them names.
// These are combinational wires – they update instantly when a or b changes.
// =============================================================================

wire        fp_sign_a = a[63];      // sign of a
wire [10:0] fp_exp_a  = a[62:52];   // biased exponent of a
wire [51:0] fp_man_a  = a[51:0];    // stored mantissa of a (52 bits, no implicit 1)

wire        fp_sign_b = b[63];
wire [10:0] fp_exp_b  = b[62:52];
wire [51:0] fp_man_b  = b[51:0];


// =============================================================================
// SECTION 3 – Main dispatch block
// =============================================================================
//
// always @(*) means: re-evaluate this block whenever ANY input changes.
// This is the standard way to describe combinational logic in Verilog.
// (SystemVerilog uses always_comb for the same thing.)
// =============================================================================

always @(*) begin
    case (op)

        // ----------------------------------------------------------------
        // Integer arithmetic
        // ----------------------------------------------------------------

        OP_ADD:  result = a + b;

        OP_SUB:  result = a - b;

        // $signed() tells Verilog to treat the bits as two's-complement.
        // Without it, * would do unsigned multiplication and the sign would
        // be wrong for negative numbers.
        OP_MUL:  result = $signed(a) * $signed(b);

        // ----------------------------------------------------------------
        // Bitwise logic
        // ----------------------------------------------------------------

        OP_AND:  result = a & b;
        OP_OR:   result = a | b;
        OP_XOR:  result = a ^ b;
        OP_NOT:  result = ~a;       // b is ignored for unary NOT

        // ----------------------------------------------------------------
        // Shifts
        // ----------------------------------------------------------------
        //
        // b[5:0] gives the shift amount (0–63).  We only need 6 bits because
        // 2^6 = 64, which covers the maximum useful shift for a 64-bit value.
        //
        // Logical right shift (>>)   : fills vacated bits with 0
        // Arithmetic right shift (>>>) : fills vacated bits with the sign bit
        //   → preserves the sign of a signed number after dividing by 2^n
        //
        OP_LSHIFT:  result = a << b[5:0];
        OP_RSHIFT:  result = a >> b[5:0];
        OP_RSHIFTA: result = $signed(a) >>> b[5:0];

        // ----------------------------------------------------------------
        // Data movement
        // ----------------------------------------------------------------

        OP_MOV:  result = b;                            // simple copy

        // movl: preserve the top 48 bits of the destination register (a),
        //       replace the bottom 16 bits with the immediate (b[15:0]).
        OP_MOVL: result = { a[63:16], b[15:0] };

        // movh: replace the top 16 bits with the immediate (b[15:0]),
        //       preserve the bottom 48 bits.
        OP_MOVH: result = { b[15:0], a[47:0] };

        // ----------------------------------------------------------------
        // Floating-point  (delegated to helper functions below)
        // ----------------------------------------------------------------

        OP_FADD: result = fp_add(a, b);

        // Subtraction = addition with b's sign flipped.
        // In IEEE 754 the sign is just bit 63, so XOR-ing it with 1 negates b.
        // This lets fp_add handle both operations.
        OP_FSUB: result = fp_add(a, { ~b[63], b[62:0] });

        OP_FMUL: result = fp_mul(a, b);
        OP_FDIV: result = fp_div(a, b);

        default: result = 64'd0;    // undefined op → zero (safe default)

    endcase
end


// =============================================================================
// SECTION 4 – Floating-point helper functions
// =============================================================================
//
// Verilog FUNCTIONS are like C functions: they take inputs, do work, and
// return a value.  They are *purely combinational* – no clock, no state.
// Inside a function you can use local `reg` variables as scratch registers;
// they don't infer flip-flops the way module-level regs would.
//
// Important rule the spec enforces: do NOT use $realtobits / $bitstoreal.
// Those are simulation-only.  Instead we manipulate the IEEE 754 bit fields
// by hand, exactly as a physical FPU does.
// =============================================================================


// -----------------------------------------------------------------------------
// fp_add  –  add two IEEE 754 doubles
// -----------------------------------------------------------------------------
//
// Algorithm overview (this is how every hardware FPU works):
//
//   1. Extract sign, biased exponent, and mantissa from each operand.
//      Prepend the implicit leading 1 to each mantissa → 53-bit significand.
//
//   2. Align: the number with the smaller exponent must have its significand
//      shifted right so that both exponents match.  This is like lining up
//      decimal points:  1.5 + 0.25 → 1.5 + 0.25 (no shift needed here, but
//      in binary you often must shift).
//
//   3. Add or subtract the aligned significands depending on the signs.
//      Same sign → add.  Different signs → subtract (larger – smaller).
//
//   4. Normalize: after add/sub the result may have the leading 1 in the
//      wrong bit position.  Shift until it's back at bit 52, adjusting the
//      exponent to compensate.
//
//   5. Pack: reassemble sign, exponent, mantissa into a 64-bit result.
//
// -----------------------------------------------------------------------------
function [63:0] fp_add;
    input [63:0] x;   // first operand
    input [63:0] y;   // second operand  (may have sign flipped for subtraction)

    // --- Local scratch variables ---
    reg        sx, sy, sr;     // signs of x, y, and result
    reg [10:0] ex, ey, er;     // biased exponents
    reg [52:0] mx, my;         // 53-bit significands  (bit 52 = implicit leading 1)
    reg [54:0] sum;            // 55-bit accumulator: handles carry out of addition
                               //   bit 54: overflow carry
                               //   bit 53: would-be carry after right-normalize
                               //   bits 52:0: significand bits
    reg [10:0] shift;          // alignment shift amount
    integer    i;              // loop counter for left-normalization

    begin
        // ----- Step 1: Extract fields -----
        sx = x[63];   ex = x[62:52];   mx = { 1'b1, x[51:0] };
        sy = y[63];   ey = y[62:52];   my = { 1'b1, y[51:0] };

        // A biased exponent of 0 encodes +/- zero (or a denormal).
        // Treat them as zero for simplicity.
        if (ex == 11'd0) mx = 53'd0;
        if (ey == 11'd0) my = 53'd0;

        // ----- Step 2: Align -----
        // Make both significands use the larger exponent.
        // Shifting right by N is equivalent to multiplying by 2^-N, which
        // "moves the decimal point" to match the larger-exponent number.
        if (ex >= ey) begin
            shift = ex - ey;
            my    = my >> shift;   // y becomes smaller → shift its bits right
            er    = ex;
        end else begin
            shift = ey - ex;
            mx    = mx >> shift;
            er    = ey;
        end

        // ----- Step 3: Add or subtract -----
        if (sx == sy) begin
            // Same sign: magnitudes add.  Result has the same sign.
            sum = { 2'b0, mx } + { 2'b0, my };   // 55-bit add, no sign issues
            sr  = sx;
        end else begin
            // Different signs: subtract smaller magnitude from larger.
            // The sign of the result follows the larger magnitude.
            if (mx >= my) begin
                sum = { 2'b0, mx } - { 2'b0, my };
                sr  = sx;
            end else begin
                sum = { 2'b0, my } - { 2'b0, mx };
                sr  = sy;
            end
        end

        // ----- Step 4: Normalize -----
        //
        // After addition, bit 53 may be set (carry out).
        // That means the result is >= 2.0 in the 1.xxx form, so we need to
        // shift right once and increment the exponent.
        //
        if (sum[53]) begin
            sum = sum >> 1;
            er  = er + 11'd1;
        end else begin
            // After subtraction, leading 1 may have moved left (cancellation).
            // Shift left until bit 52 is 1 again, decrement exponent each time.
            // We loop at most 52 times (one per mantissa bit).
            for (i = 0; i < 52; i = i + 1) begin
                if (!sum[52] && er > 11'd1) begin
                    sum = sum << 1;
                    er  = er - 11'd1;
                end
            end
        end

        // ----- Step 5: Pack result -----
        // If the significand is all zeros (e.g. x == -x), return +0.
        if (sum[52:0] == 53'd0)
            fp_add = 64'd0;
        else
            fp_add = { sr, er, sum[51:0] };
        //                ^    ^    ^
        //              sign  exp  mantissa (drop the implicit leading 1 at bit 52)
    end
endfunction


// -----------------------------------------------------------------------------
// fp_mul  –  multiply two IEEE 754 doubles
// -----------------------------------------------------------------------------
//
// Algorithm overview:
//
//   1. Result sign  = XOR of input signs  (pos*pos=pos, pos*neg=neg, etc.)
//
//   2. Result exponent = ex + ey - 1023
//      Why subtract 1023?  Both exponents are already biased (+1023 each).
//      Adding them gives bias of 2046; we need bias of 1023, so subtract once.
//
//   3. Result significand = mx * my
//      Both significands are 53 bits (1.fraction).  Their product is up to
//      106 bits.  We keep the top 53 bits and use them as the new significand.
//
//   4. Normalize: the top bit of the product is either bit 105 or bit 104.
//      If bit 105 is set, the product is in [2.0, 4.0) → shift right 1, bump exponent.
//      If bit 104 is set, it's already in [1.0, 2.0) → no shift needed.
//
// -----------------------------------------------------------------------------
function [63:0] fp_mul;
    input [63:0] x;
    input [63:0] y;

    reg        sx, sy, sr;
    reg [10:0] ex, ey, er;
    reg [52:0] mx, my;
    reg [105:0] product;   // 53 bits × 53 bits = up to 106-bit product

    begin
        sx = x[63];   ex = x[62:52];   mx = { 1'b1, x[51:0] };
        sy = y[63];   ey = y[62:52];   my = { 1'b1, y[51:0] };

        // Zero check: if either exponent is 0, the value is 0 → product is 0.
        if (ex == 11'd0 || ey == 11'd0) begin
            fp_mul = 64'd0;
        end else begin
            // ----- Sign -----
            sr = sx ^ sy;

            // ----- Exponent -----
            // Both are biased by 1023; adding them gives double-bias.
            // Subtract one copy of the bias to get the correct result.
            er = ex + ey - 11'd1023;

            // ----- Significand -----
            product = mx * my;
            // product[105:53] contains the top 53 bits when bit 105 is the MSB.

            // ----- Normalize -----
            // mx and my are both in [1.0, 2.0) as 1.fraction values.
            // Their product is in [1.0, 4.0).
            // If the product >= 2.0, bit 105 of `product` is set.
            if (product[105]) begin
                // Product is in [2.0, 4.0): shift right 1 to bring into [1.0, 2.0).
                // Taking bits [104:53] is equivalent to >> 1 then taking [103:52].
                fp_mul = { sr, er, product[104:53] };
            end else begin
                // Product is already in [1.0, 2.0).  Bit 104 is the implicit 1.
                // Decrement exponent to compensate for the missing shift.
                fp_mul = { sr, er - 11'd1, product[103:52] };
            end
        end
    end
endfunction


// -----------------------------------------------------------------------------
// fp_div  –  divide two IEEE 754 doubles  (x / y)
// -----------------------------------------------------------------------------
//
// Algorithm overview:
//
//   1. Result sign  = XOR of input signs (same as multiply).
//
//   2. Result exponent = ex - ey + 1023
//      Subtracting exponents divides the magnitudes; adding back one bias
//      keeps the result biased correctly.
//
//   3. Result significand = mx / my
//      Both are 53-bit integers representing values in [1.0, 2.0).
//      Directly dividing gives a result in (0.5, 2.0).
//      To preserve 52 bits of fractional precision, we shift the dividend
//      left by 53 bits before dividing, then take the top bits.
//
//   4. Normalize: quotient bit 52 is the implicit leading 1.
//      If it ended up at bit 53 (product >= 2.0), shift right 1 and adjust.
//
// -----------------------------------------------------------------------------
function [63:0] fp_div;
    input [63:0] x;
    input [63:0] y;

    reg        sx, sy, sr;
    reg [10:0] ex, ey, er;
    reg [52:0] mx, my;
    reg [105:0] dividend;  // mx shifted left 53 bits to preserve precision
    reg [52:0]  quotient;  // 53-bit integer result of the division

    begin
        sx = x[63];   ex = x[62:52];   mx = { 1'b1, x[51:0] };
        sy = y[63];   ey = y[62:52];   my = { 1'b1, y[51:0] };

        // Zero dividend → result is 0.
        if (ex == 11'd0) begin
            fp_div = 64'd0;
        end else begin
            // ----- Sign -----
            sr = sx ^ sy;

            // ----- Exponent -----
            er = ex - ey + 11'd1023;

            // ----- Significand -----
            //
            // We want  mx / my  with 53 bits of precision.
            // If we just did  mx / my  in integer arithmetic, we'd get either
            // 0 or 1 (since mx and my are both in [2^52, 2^53)).
            //
            // Instead we scale mx up by 2^53 first:
            //   dividend = mx * 2^53
            //   quotient = dividend / my  →  approximately (mx/my) * 2^53
            //
            // The quotient is a 53-bit integer whose bits represent the
            // significand of the result.
            //
            dividend = { mx, 53'b0 };        // left-shift mx by 53 positions
            quotient = dividend / { 53'b0, my }; // integer division gives ~53-bit result

            // ----- Normalize -----
            // quotient[52] should be the implicit leading 1.
            // If the leading 1 landed at bit 52 → result exponent is already correct.
            if (quotient[52]) begin
                fp_div = { sr, er, quotient[51:0] };
            end else begin
                // Leading 1 is at bit 51 (result < 1.0 before re-normalization).
                // Shift left 1 and decrement exponent.
                fp_div = { sr, er - 11'd1, quotient[50:0], 1'b0 };
            end
        end
    end
endfunction


endmodule
