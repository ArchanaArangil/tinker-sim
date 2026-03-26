
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
