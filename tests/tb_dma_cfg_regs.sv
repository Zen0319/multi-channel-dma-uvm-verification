
`timescale 1ns/1ps

module tb_dma_cfg_regs;

    logic clk = 0;
    logic rst_n;

    logic cfg_valid, cfg_write;
    logic [7:0] cfg_addr;
    logic [31:0] cfg_wdata;
    logic cfg_ready;
    logic [31:0] cfg_rdata;

    logic [31:0] ch0_src, ch0_dst, ch0_len;
    logic [31:0] ch1_src, ch1_dst, ch1_len;
    logic ch0_pending, ch1_pending;
    logic ch0_done, ch1_done;

    int tests_passed = 0;

    // 10 ns clock period
    always #5 clk = ~clk;

    // Design Under Test
    dma_cfg_regs dut (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_valid(cfg_valid),
        .cfg_write(cfg_write),
        .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata),
        .cfg_ready(cfg_ready),
        .cfg_rdata(cfg_rdata),

        .ch0_src(ch0_src),
        .ch0_dst(ch0_dst),
        .ch0_len(ch0_len),

        .ch1_src(ch1_src),
        .ch1_dst(ch1_dst),
        .ch1_len(ch1_len),

        .ch0_pending(ch0_pending),
        .ch1_pending(ch1_pending),
        .ch0_done(ch0_done),
        .ch1_done(ch1_done)
    );

    // CPU register write
    task automatic write_reg(
        input logic [7:0] addr,
        input logic [31:0] data
    );
        @(negedge clk);
        cfg_valid = 1;
        cfg_write = 1;
        cfg_addr  = addr;
        cfg_wdata = data;

        @(posedge clk);
        #1;

        if (cfg_ready !== 1'b1)
            $fatal(1, "Configuration ready not asserted");

        @(negedge clk);
        cfg_valid = 0;
        cfg_write = 0;
    endtask

    // Read and compare expected register data
    task automatic check_reg(
        input logic [7:0] addr,
        input logic [31:0] expected,
        input string name
    );
        @(negedge clk);
        cfg_valid = 1;
        cfg_write = 0;
        cfg_addr  = addr;

        #1;
        if (cfg_ready !== 1'b1 ||
            cfg_rdata !== expected) begin
            $fatal(1,
                "FAIL: %s expected=%h actual=%h",
                name, expected, cfg_rdata);
        end

        tests_passed++;
        $display("PASS: %s", name);

        @(negedge clk);
        cfg_valid = 0;
    endtask

    // Simulate one-cycle completion pulse
    task automatic complete_ch0;
        @(negedge clk);
        ch0_done = 1;

        @(posedge clk);
        #1;

        @(negedge clk);
        ch0_done = 0;
    endtask

    task automatic complete_ch1;
        @(negedge clk);
        ch1_done = 1;

        @(posedge clk);
        #1;

        @(negedge clk);
        ch1_done = 0;
    endtask

    // Waveform dumping
    initial begin
        $fsdbDumpfile("results/cfg_regs.fsdb");
        $fsdbDumpvars(0, tb_dma_cfg_regs);
    end

    // Main test sequence
    initial begin
        rst_n = 0;
        cfg_valid = 0;
        cfg_write = 0;
        cfg_addr = 0;
        cfg_wdata = 0;
        ch0_done = 0;
        ch1_done = 0;

        // Reset
        repeat (2) @(negedge clk);
        rst_n = 1;

        // Test 1: Reset register values
        check_reg(8'h00, 32'h0, "CH0 reset source");
        check_reg(8'h0C, 32'h0, "CH0 reset status");
        check_reg(8'h1C, 32'h0, "CH1 reset status");

        // Program Channel 0
        write_reg(8'h00, 32'h00001000);
        write_reg(8'h04, 32'h00002000);
        write_reg(8'h08, 32'd4);

        // Test 2: Verify configuration
        check_reg(8'h00, 32'h00001000,
                  "CH0 source programmed");
        check_reg(8'h04, 32'h00002000,
                  "CH0 destination programmed");
        check_reg(8'h08, 32'd4,
                  "CH0 length programmed");

        // Start Channel 0
        write_reg(8'h0C, 32'h1);

        // BUSY = bit 1
        check_reg(8'h0C, 32'h2,
                  "CH0 busy after START");

        // Attempt to modify busy channel
        write_reg(8'h00, 32'h00003000);

        check_reg(8'h00, 32'h00001000,
                  "CH0 configuration locked");

        // Complete Channel 0
        complete_ch0();

        // DONE = bit 2
        check_reg(8'h0C, 32'h4,
                  "CH0 completed successfully");

        // Test invalid transfer length
        write_reg(8'h08, 32'd0);
        write_reg(8'h0C, 32'h1);

        // ERROR = bit 3
        check_reg(8'h0C, 32'h8,
                  "CH0 zero length rejected");

        // Test misaligned source address
        write_reg(8'h08, 32'd4);
        write_reg(8'h00, 32'h00001001);
        write_reg(8'h0C, 32'h1);

        check_reg(8'h0C, 32'h8,
                  "CH0 misaligned address rejected");

        // Test excessive length
        write_reg(8'h00, 32'h00001000);
        write_reg(8'h08, 32'd257);
        write_reg(8'h0C, 32'h1);

        check_reg(8'h0C, 32'h8,
                  "CH0 excessive length rejected");

        // Test address overflow
        write_reg(8'h00, 32'hFFFF_FFFC);
        write_reg(8'h08, 32'd2);
        write_reg(8'h0C, 32'h1);

        check_reg(8'h0C, 32'h8,
                  "CH0 source overflow rejected");

        // Program Channel 1
        write_reg(8'h10, 32'h00003000);
        write_reg(8'h14, 32'h00004000);
        write_reg(8'h18, 32'd8);

        check_reg(8'h10, 32'h00003000,
                  "CH1 source programmed");
        check_reg(8'h14, 32'h00004000,
                  "CH1 destination programmed");
        check_reg(8'h18, 32'd8,
                  "CH1 length programmed");

        write_reg(8'h1C, 32'h1);

        check_reg(8'h1C, 32'h2,
                  "CH1 busy after START");

        complete_ch1();

        check_reg(8'h1C, 32'h4,
                  "CH1 completed successfully");

        $display("--------------------------------");
        $display("ALL %0d REGISTER CHECKS PASSED",
                 tests_passed);
        $display("--------------------------------");

        $finish;
    end

    // Safety timeout
    initial begin
        #10000;
        $fatal(1, "Simulation timeout");
    end

endmodule

