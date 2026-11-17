
`timescale 1ns/1ps

module tb_dma_controller;

    logic clk = 0;
    logic rst_n;

    // CPU configuration interface
    logic cfg_valid, cfg_write;
    logic [7:0] cfg_addr;
    logic [31:0] cfg_wdata;
    logic cfg_ready;
    logic [31:0] cfg_rdata;

    // Memory read interface
    logic rd_req_valid, rd_req_ready;
    logic [31:0] rd_req_addr;

    logic rd_rsp_valid, rd_rsp_ready;
    logic [31:0] rd_rsp_data;
    logic [31:0] response_data;

    // Memory write interface
    logic wr_req_valid, wr_req_ready;
    logic [31:0] wr_req_addr, wr_req_data;

    // Completion
    logic done_valid, done_channel;

    int cycle_count;
    int reads_ch0, reads_ch1;
    int writes_ch0, writes_ch1;
    int completions_ch0, completions_ch1;
    
    
    // Count how many times each channel is issued
    int accepts_ch0;
    int accepts_ch1;


    always #5 clk = ~clk;

    // ------------------------------------
    // DUT: Complete DMA Controller
    // ------------------------------------
    dma_controller dut (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_valid(cfg_valid),
        .cfg_write(cfg_write),
        .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata),
        .cfg_ready(cfg_ready),
        .cfg_rdata(cfg_rdata),

        .rd_req_valid(rd_req_valid),
        .rd_req_ready(rd_req_ready),
        .rd_req_addr(rd_req_addr),

        .rd_rsp_valid(rd_rsp_valid),
        .rd_rsp_ready(rd_rsp_ready),
        .rd_rsp_data(rd_rsp_data),

        .wr_req_valid(wr_req_valid),
        .wr_req_ready(wr_req_ready),
        .wr_req_addr(wr_req_addr),
        .wr_req_data(wr_req_data),

        .done_valid(done_valid),
        .done_channel(done_channel)
    );

    // Deterministic memory contents
    function automatic logic [31:0] mem_pattern(
        input logic [31:0] addr
    );
        return addr ^ 32'hA5A5_5A5A;
    endfunction

    // Introduce periodic memory stalls
    assign rd_req_ready = (cycle_count % 3 != 0);
    assign wr_req_ready = (cycle_count % 4 != 0);
    assign rd_rsp_data = response_data;

    // Read responder: one outstanding read
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycle_count   <= 0;
            rd_rsp_valid  <= 0;
            response_data <= 0;
        end
        else begin
            cycle_count <= cycle_count + 1;

            if (rd_req_valid && rd_req_ready) begin
                rd_rsp_valid  <= 1;
                response_data <= mem_pattern(rd_req_addr);
            end
            else if (rd_rsp_valid && rd_rsp_ready) begin
                rd_rsp_valid <= 0;
            end
        end
    end

    // ------------------------------------
    // CPU register-write task
    // ------------------------------------
    task automatic write_reg(
        input logic [7:0] addr,
        input logic [31:0] data
    );
        @(negedge clk);

        cfg_valid = 1;
        cfg_write = 1;
        cfg_addr  = addr;
        cfg_wdata = data;

        if (cfg_ready !== 1'b1)
            $fatal(1, "Config interface not ready");

        @(negedge clk);
        cfg_valid = 0;
        cfg_write = 0;
    endtask

    // CPU register-read checker
    task automatic check_reg(
        input logic [7:0] addr,
        input logic [31:0] expected,
        input string description
    );
        @(negedge clk);

        cfg_addr  = addr;
        cfg_valid = 1;
        cfg_write = 0;

        #1;
        if (cfg_rdata !== expected)
            $fatal(1,
                "FAIL: %s expected=%h got=%h",
                description, expected, cfg_rdata);

        $display("PASS: %s", description);

        @(negedge clk);
        cfg_valid = 0;
    endtask

    // ------------------------------------
    // Independent read/write checks
    // ------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin

            if (rd_req_valid && rd_req_ready) begin
                if (rd_req_addr >= 32'h1000 &&
                    rd_req_addr < 32'h1010) begin

                    if (rd_req_addr !==
                        (32'h1000 + reads_ch0 * 4))
                        $fatal(1, "CH0 read address error");

                    reads_ch0++;
                end
                else if (rd_req_addr >= 32'h3000 &&
                         rd_req_addr < 32'h3020) begin

                    if (rd_req_addr !==
                        (32'h3000 + reads_ch1 * 4))
                        $fatal(1, "CH1 read address error");

                    reads_ch1++;
                end
                else
                    $fatal(1,
                        "Unexpected read address %h",
                        rd_req_addr);
            end

            if (wr_req_valid && wr_req_ready) begin

                if (wr_req_addr >= 32'h2000 &&
                    wr_req_addr < 32'h2010) begin

                    if (wr_req_addr !==
                        (32'h2000 + writes_ch0 * 4))
                        $fatal(1, "CH0 write address error");

                    if (wr_req_data !== mem_pattern(
                        32'h1000 + writes_ch0 * 4))
                        $fatal(1, "CH0 write data error");

                    writes_ch0++;
                end
                else if (wr_req_addr >= 32'h4000 &&
                         wr_req_addr < 32'h4020) begin

                    if (wr_req_addr !==
                        (32'h4000 + writes_ch1 * 4))
                        $fatal(1, "CH1 write address error");

                    if (wr_req_data !== mem_pattern(
                        32'h3000 + writes_ch1 * 4))
                        $fatal(1, "CH1 write data error");

                    writes_ch1++;
                end
                else
                    $fatal(1,
                        "Unexpected write address %h",
                        wr_req_addr);
            end

            if (done_valid) begin
                if (done_channel == 0) begin
                    if (writes_ch0 != 4)
                        $fatal(1, "CH0 completed early");
                    completions_ch0++;
                end
                else begin
                    if (writes_ch1 != 8)
                        $fatal(1, "CH1 completed early");
                    completions_ch1++;
                end
            end
        end
    end
    
    // NEW: Count accepted channel commands
    always @(posedge clk) begin
        if (rst_n && dut.arb_accept) begin
            if (dut.start_channel == 1'b0) begin
                accepts_ch0++;
                if (accepts_ch0 > 1)
                    $fatal(1,
                        "CH0 DUPLICATE START DETECTED");
            end
            else begin
                accepts_ch1++;
                if (accepts_ch1 > 1)
                    $fatal(1,
                        "CH1 DUPLICATE START DETECTED");
            end
        end
    end

    // FSDB waveforms
    initial begin
        $fsdbDumpfile("results/dma_controller.fsdb");
        $fsdbDumpvars(0, tb_dma_controller);
    end

    // ------------------------------------
    // Main test sequence
    // ------------------------------------
    initial begin
        rst_n = 0;
        cfg_valid = 0;
        cfg_write = 0;
        cfg_addr = 0;
        cfg_wdata = 0;

        reads_ch0 = 0;
        reads_ch1 = 0;
        writes_ch0 = 0;
        writes_ch1 = 0;
        completions_ch0 = 0;
        completions_ch1 = 0;

        accepts_ch0 = 0;
        accepts_ch1 = 0;

        repeat (2) @(negedge clk);
        rst_n = 1;

        // Program Channel 0
        write_reg(8'h00, 32'h1000);
        write_reg(8'h04, 32'h2000);
        write_reg(8'h08, 32'd4);

        // Program Channel 1
        write_reg(8'h10, 32'h3000);
        write_reg(8'h14, 32'h4000);
        write_reg(8'h18, 32'd8);

        // Start both DMA channels
        write_reg(8'h0C, 32'h1);
        write_reg(8'h1C, 32'h1);

        // Wait for both completions
        wait (completions_ch0 == 1 &&
              completions_ch1 == 1);

        // Allow status registers to update
        @(negedge clk);

        // Verify transfer counts
        if (reads_ch0 != 4 || writes_ch0 != 4)
            $fatal(1, "CH0 transfer count mismatch");

        if (reads_ch1 != 8 || writes_ch1 != 8)
            $fatal(1, "CH1 transfer count mismatch");

        $display("PASS: CH0 transferred 4 words");
        $display("PASS: CH1 transferred 8 words");

        // DONE bit set, BUSY bit clear
        check_reg(8'h0C, 32'h4, "CH0 DONE status");
        check_reg(8'h1C, 32'h4, "CH1 DONE status");

        if (completions_ch0 != 1 ||
            completions_ch1 != 1)
            $fatal(1, "Duplicate completion detected");

        // Verify both channels were accepted exactly once
        if (accepts_ch0 != 1 ||
            accepts_ch1 != 1)
            $fatal(1,
                "Incorrect acceptance count: CH0=%0d CH1=%0d",
                accepts_ch0, accepts_ch1);

        $display("PASS: Each DMA channel accepted exactly once");

        $display("--------------------------------");
        $display("INTEGRATED DMA CONTROLLER PASSED");
        $display("--------------------------------");

        $finish;
    end

    // Timeout protection
    initial begin
        #20000;
        $fatal(1, "DMA controller simulation timeout");
    end

endmodule

