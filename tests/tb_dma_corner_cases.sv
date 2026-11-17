
`timescale 1ns/1ps

module tb_dma_corner_cases;

    logic clk = 0;
    logic rst_n;

    // Configuration interface
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

    logic done_valid, done_channel;

    int cycle_count;
    int reads_1, writes_1;
    int reads_2, writes_2;
    int accept_count, done_count;

    always #5 clk = ~clk;

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

    function automatic logic [31:0] mem_pattern(
        input logic [31:0] addr
    );
        return addr ^ 32'hA5A5_5A5A;
    endfunction

    // Apply periodic memory backpressure
    assign rd_req_ready = (cycle_count % 3 != 0);
    assign wr_req_ready = (cycle_count % 4 != 0);
    assign rd_rsp_data = response_data;

    // One outstanding read response
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

        if (cfg_ready !== 1'b1)
            $fatal(1, "Configuration interface not ready");

        @(negedge clk);
        cfg_valid = 0;
        cfg_write = 0;
    endtask

    // Check completion status register
    task automatic check_done;
        @(negedge clk);
        cfg_valid = 1;
        cfg_write = 0;
        cfg_addr  = 8'h0C;

        #1;
        if (cfg_rdata !== 32'h4)
            $fatal(1,
                "CH0 DONE status incorrect: %h",
                cfg_rdata);

        @(negedge clk);
        cfg_valid = 0;
    endtask

    // Independent transaction monitor
    always @(posedge clk) begin
        if (rst_n) begin

            // Count accepted DMA commands
            if (dut.arb_accept) begin
                if (dut.start_channel !== 1'b0)
                    $fatal(1, "Unexpected CH1 acceptance");

                accept_count++;

                if (accept_count > 2)
                    $fatal(1, "Unexpected extra DMA START");
            end

            // Verify memory read addresses
            if (rd_req_valid && rd_req_ready) begin

                if (rd_req_addr >= 32'h1000 &&
                    rd_req_addr < 32'h1010) begin

                    if (rd_req_addr !==
                        (32'h1000 + reads_1 * 4))
                        $fatal(1,
                            "Transfer 1 read address error");

                    reads_1++;
                end
                else if (rd_req_addr >= 32'h5000 &&
                         rd_req_addr < 32'h500C) begin

                    if (rd_req_addr !==
                        (32'h5000 + reads_2 * 4))
                        $fatal(1,
                            "Transfer 2 read address error");

                    reads_2++;
                end
                else
                    $fatal(1,
                        "Unexpected read address: %h",
                        rd_req_addr);
            end

            // Verify destination and transferred data
            if (wr_req_valid && wr_req_ready) begin

                if (wr_req_addr >= 32'h2000 &&
                    wr_req_addr < 32'h2010) begin

                    if (wr_req_addr !==
                        (32'h2000 + writes_1 * 4))
                        $fatal(1,
                            "Transfer 1 write address error");

                    if (wr_req_data !== mem_pattern(
                        32'h1000 + writes_1 * 4))
                        $fatal(1,
                            "Transfer 1 write data error");

                    writes_1++;
                end
                else if (wr_req_addr >= 32'h6000 &&
                         wr_req_addr < 32'h600C) begin

                    if (wr_req_addr !==
                        (32'h6000 + writes_2 * 4))
                        $fatal(1,
                            "Transfer 2 write address error");

                    if (wr_req_data !== mem_pattern(
                        32'h5000 + writes_2 * 4))
                        $fatal(1,
                            "Transfer 2 write data error");

                    writes_2++;
                end
                else
                    $fatal(1,
                        "Unexpected write address: %h",
                        wr_req_addr);
            end

            // Verify transfer completion
            if (done_valid) begin
                if (done_channel !== 1'b0)
                    $fatal(1, "Unexpected CH1 completion");

                if (done_count == 0) begin
                    if (reads_1 != 4 || writes_1 != 4)
                        $fatal(1,
                            "Transfer 1 completed incorrectly");
                end
                else if (done_count == 1) begin
                    if (reads_2 != 3 || writes_2 != 3)
                        $fatal(1,
                            "Transfer 2 completed incorrectly");
                end
                else
                    $fatal(1, "Extra DMA completion");

                done_count++;
            end
        end
    end

    // FSDB waveform capture
    initial begin
        $fsdbDumpfile("results/dma_corner_cases.fsdb");
        $fsdbDumpvars(0, tb_dma_corner_cases);
    end

    // Main test
    initial begin
        rst_n = 0;
        cfg_valid = 0;
        cfg_write = 0;
        cfg_addr = 0;
        cfg_wdata = 0;

        reads_1 = 0;
        writes_1 = 0;
        reads_2 = 0;
        writes_2 = 0;
        accept_count = 0;
        done_count = 0;

        repeat (2) @(negedge clk);
        rst_n = 1;

        $display("Starting DMA corner-case verification");

        // ---------------------------------
        // Transfer 1: 4 words
        // ---------------------------------
        write_reg(8'h00, 32'h1000);
        write_reg(8'h04, 32'h2000);
        write_reg(8'h08, 32'd4);
        write_reg(8'h0C, 32'h1);

        wait (done_count == 1);
        @(negedge clk);

        if (reads_1 != 4 || writes_1 != 4 ||
            accept_count != 1)
            $fatal(1, "Transfer 1 count mismatch");

        check_done();

        $display("PASS: First CH0 transfer completed");

        // Check for unexpected reissue while idle
        repeat (10) @(negedge clk);

        if (accept_count != 1 || done_count != 1)
            $fatal(1, "Duplicate first transfer detected");

        // ---------------------------------
        // Transfer 2: 3 words
        // ---------------------------------
        write_reg(8'h00, 32'h5000);
        write_reg(8'h04, 32'h6000);
        write_reg(8'h08, 32'd3);
        write_reg(8'h0C, 32'h1);

        wait (done_count == 2);
        @(negedge clk);

        if (reads_2 != 3 || writes_2 != 3 ||
            accept_count != 2)
            $fatal(1, "Transfer 2 count mismatch");

        check_done();

        $display("PASS: Second CH0 transfer completed");

        // Observe the controller after completion
        repeat (20) @(negedge clk);

        if (accept_count != 2 || done_count != 2 ||
            reads_1 != 4 || writes_1 != 4 ||
            reads_2 != 3 || writes_2 != 3)
            $fatal(1, "Unexpected extra DMA activity");

        $display("PASS: Both transfers accepted exactly once");
        $display("PASS: No duplicate transactions detected");
        $display("--------------------------------");
        $display("BACK-TO-BACK DMA TEST PASSED");
        $display("--------------------------------");

        $finish;
    end

    // Timeout
    initial begin
        #20000;
        $fatal(1, "Back-to-back DMA test timeout");
    end

endmodule

