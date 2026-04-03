Archana Arangil
aa224297

Decoder:
iverilog -g2012 -o /tmp/decoder_tb.vvp hdl/decoder.v test/decoder_tb.v
vvp /tmp/decoder_tb.vvp

Register File:
iverilog -g2012 -o /tmp/reg_file_tb.vvp hdl/reg_file.v test/reg_file_tb.v
vvp /tmp/reg_file_tb.vvp

ALU:
iverilog -g2012 -o /tmp/alu_tb.vvp hdl/alu.v test/alu_tb.v
vvp /tmp/alu_tb.vvp

Full tinker.sv:
iverilog -g2012 -o /tmp/tinker_core_tb.vvp tinker.sv test/tinker_core_tb.v
vvp /tmp/tinker_core_tb.vvp
