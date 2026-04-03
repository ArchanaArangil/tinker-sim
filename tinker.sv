`define MEM_SIZE 524288

`include "hdl/alu.sv"
`include "hdl/reg_file.sv"
`include "hdl/decoder.sv"

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

    wire [63:0] stack_ptr = reg_data_b;
    wire [63:0] call_stack_addr = stack_ptr - 64'd8;
    wire [63:0] ret_stack_addr = stack_ptr;
    wire [63:0] stack_write_data = pc + 64'd4;

    wire [63:0] alu_b = use_imm ? imm : reg_data_b;
    wire [63:0] alu_result;

    //address for load store
    wire [63:0] data_rdata;
    wire [63:0] mem_addr = call ? call_stack_addr :
                           ret  ? ret_stack_addr  :
                           (reg_data_a + imm);
    wire [63:0] mem_wdata = call ? stack_write_data : reg_data_b;
    wire        mem_we = (call | mem_write) & ~illegal;

    // Loads write the value coming back from memory.
    wire [63:0] write_back_data = mem_read ? data_rdata : alu_result;

    // CALL/RETURN both update r31 to push/pop the stack pointer.
    wire [4:0] reg_write_addr = (call || ret) ? 5'd31 : write_addr;
    wire [63:0] reg_write_data = call ? call_stack_addr :
                                 ret  ? (stack_ptr + 64'd8) :
                                 write_back_data;
    wire reg_write_en = call | ret |
                        (write_en_dec & ~illegal & ~branch_abs & ~branch_rel &
                         ~branch_nz & ~branch_gt);

    
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
        .rd_addr(reg_write_addr),
        .wr_data(reg_write_data),
        .wr_en(reg_write_en),
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

   
    // fetch instruction at pc and do load/store
    tinker_memory memory (
        .clk(clk),
        .instr_addr(pc),
        .instr(instr),
        .data_addr(mem_addr),
        .data_wdata(mem_wdata),
        .data_we(mem_we),
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
        end else if (ret) begin
            next_pc = data_rdata;
        end
    end

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

// Pull shared RTL blocks from the hdl/ directory so the core and unit tests
// all exercise one source of truth.
`include "hdl/alu.v"
`include "hdl/reg_file.v"
`include "hdl/decoder.v"
