// 四态接口检查：逐 Bank、逐奇偶位驱动 0/1/X/Z，观察顶层和子模块输入。
// 这里只验证端口连接不吞掉 X/Z，不把未知状态定义成合法业务输入。
// Icarus Verilog 可直接编译本文件和 rtl/files.f；不使用二态 Verilator 证明 X/Z。
`timescale 1ns/1ps
module rd_mem_status_four_state_tb;
    reg clk;
    reg rst_n;
    reg [1:0] status_drive [7:0];
    wire [1:0] rd_mem_status [7:0];
    reg injected;
    integer bank, half, value_index, b, checks;
    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : status_connection
            assign rd_mem_status[g] = status_drive[g];
        end
    endgenerate

    cmdbuf_rd dut (
        .clk(clk), .rst_n(rst_n), .arvalid(1'b0),
        .araddr(18'b0), .src(2'b0), .arid(8'b0),
        .ar_port_id(5'b0), .arresp(2'b0), .rready(3'b0),
        .ar_rd_gnt(8'b0), .rw_rd_gnt(8'b0),
        .rd_mem_status(rd_mem_status), .mem_rdata(128'b0), .pc_err(1'b0)
    );

    always #5 clk = ~clk;
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        checks = 0;
        injected = 1'b0;
        for (b = 0; b < 8; b = b + 1) status_drive[b] = 2'b00;
        #2;
        for (bank = 0; bank < 8; bank = bank + 1) begin
            for (half = 0; half < 2; half = half + 1) begin
                for (value_index = 0; value_index < 4; value_index = value_index + 1) begin
                    case (value_index)
                        0: injected = 1'b0;
                        1: injected = 1'b1;
                        2: injected = 1'bx;
                        3: injected = 1'bz;
                    endcase
                    status_drive[bank][half] = injected;
                    #1;
                    if (dut.rd_mem_status[bank][half] !== injected)
                        $fatal(1, "FOUR_STATE_MISMATCH top bank=%0d half=%0d expected=%b actual=%b",
                               bank, half, injected, dut.rd_mem_status[bank][half]);
                    if (dut.u_cmd.rd_mem_status[bank][half] !== injected)
                        $fatal(1, "FOUR_STATE_MISMATCH cmd bank=%0d half=%0d expected=%b actual=%b",
                               bank, half, injected, dut.u_cmd.rd_mem_status[bank][half]);
                    checks = checks + 2;
                end
                status_drive[bank][half] = 1'b0;
            end
        end
        $display("PASS FOUR_STATE_INTERFACE combinations=64 observations=%0d", checks);
        $finish;
    end
endmodule
