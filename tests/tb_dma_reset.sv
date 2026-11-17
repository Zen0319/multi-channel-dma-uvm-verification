
`timescale 1ns/1ps

module tb_dma_reset;

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

    logic done_valid, done_channel;

    int cycles;
    int phase;

    int pre_reads, pre_writes, pre_accepts;
    int post_reads, post_writes, post_accepts;
    int post_completions;

    always #5 clk = ~clk;

    // ------------------------------------
    // DMA Controller DUT
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

    // Deterministic memory data
    function automatic logic [31:0] pattern(
        input logic [31:0] addr
    );
        return addr ^ 32'hA5A5_5A5A;
    endfunction

    // Periodic memory backpressure
    assign rd_req_ready = (cycles % 3 != 0);
    assign wr_req_ready = (cycles % 4 != 0);
    assign rd_rsp_data = response_data;

    // ------------------------------------
    // Memory read responder
    // ------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles        <= 0;
            rd_rsp_valid  <= 0;
            response_data <= 0;
        end
        else begin
            cycles <= cycles + 1;

            if (rd_req_valid && rd_req_ready) begin
                rd_rsp_valid  <= 1;
                response_data <= pattern(rd_req_addr);
            end
            else if (rd_rsp_valid && rd_rsp_ready) begin
                rd_rsp_valid <= 0;
            end
        end
    end

    // ------------------------------------
    // CPU register writer
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
            $fatal(1, "Configuration interface not ready");

        @(negedge clk);
        cfg_valid = 0;
        cfg_write = 0;
    endtask

    // ------------------------------------
    // CPU register read checker
    // ------------------------------------
    task automatic check_reg(
        input logic [7:0] addr,
        input logic [31:0] expected,
        input string description
    );
        @(negedge clk);

        cfg_valid = 1;
        cfg_write = 0;
        cfg_addr  = addr;

        #1;
        if (cfg_rdata !== expected)
            $fatal(1,
                "%s: expected=%h got=%h",
                description, expected, cfg_rdata);

        $display("PASS: %s", description);

        @(negedge clk);
        cfg_valid = 0;
    endtask

    // ------------------------------------
    // Transaction monitor
    // phase 0: transfer before reset
    // phase 1: recovery transfer
    // ------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin

            // DMA start acceptance
            if (dut.arb_accept) begin
                if (dut.start_channel !== 1'b0)
                    $fatal(1, "Unexpected CH1 acceptance");

                if (phase == 0) begin
                    pre_accepts++;
                    if (pre_accepts > 1)
                        $fatal(1, "Duplicate pre-reset START");
                end
                else begin
                    post_accepts++;
                    if (post_accepts > 1)
                        $fatal(1, "Duplicate recovery START");
                end
            end

            // Read address verification
            if (rd_req_valid && rd_req_ready) begin
                if (phase == 0) begin
                    if (rd_req_addr !==
                        (32'h1000 + pre_reads * 4))
                        $fatal(1,
                            "Pre-reset read address mismatch");

                    pre_reads++;
                    if (pre_reads > 16)
                        $fatal(1, "Excess pre-reset reads");
                end
                else begin
                    if (rd_req_addr !==
                        (32'h5000 + post_reads * 4))
                        $fatal(1,
                            "Recovery read address mismatch");

                    post_reads++;
                    if (post_reads > 3)
                        $fatal(1, "Excess recovery reads");
                end
            end

            // Write address and data verification
            if (wr_req_valid && wr_req_ready) begin
                if (phase == 0) begin
                    if (wr_req_addr !==
                        (32'h2000 + pre_writes * 4))
                        $fatal(1,
                            "Pre-reset write address mismatch");

                    if (wr_req_data !== pattern(
                        32'h1000 + pre_writes * 4))
                        $fatal(1,
                            "Pre-reset write data mismatch");

                    pre_writes++;
                    if (pre_writes > 16)
                        $fatal(1, "Excess pre-reset writes");
                end
                else begin
                    if (wr_req_addr !==
                        (32'h6000 + post_writes * 4))
                        $fatal(1,
                            "Recovery write address mismatch");

                    if (wr_req_data !== pattern(
                        32'h5000 + post_writes * 4))
                        $fatal(1,
                            "Recovery write data mismatch");

                    post_writes++;
                    if (post_writes > 3)
                        $fatal(1, "Excess recovery writes");
                end
            end

            // Completion verification
            if (done_valid) begin
                if (phase == 0)
                    $fatal(1,
                        "Pre-reset transfer finished unexpectedly");

                if (done_channel !== 1'b0)
                    $fatal(1, "Wrong completion channel");

                if (post_reads != 3 || post_writes != 3)
                    $fatal(1,
                        "Recovery transfer completed early");

                post_completions++;

                if (post_completions > 1)
                    $fatal(1, "Duplicate recovery completion");
            end
        end
    end

    // ------------------------------------
    // FSDB waveform dump
    // ------------------------------------
    initial begin
        $fsdbDumpfile("results/dma_reset.fsdb");
        $fsdbDumpvars(0, tb_dma_reset);
    end

    // ------------------------------------
    // Main reset-recovery test
    // ------------------------------------
    initial begin
        rst_n = 0;
        cfg_valid = 0;
        cfg_write = 0;
        cfg_addr = 0;
        cfg_wdata = 0;

        phase = 0;

        pre_reads = 0;
        pre_writes = 0;
        pre_accepts = 0;

        post_reads = 0;
        post_writes = 0;
        post_accepts = 0;
        post_completions = 0;

        repeat (2) @(negedge clk);
        rst_n = 1;

        $display("Starting DMA reset recovery test");

        // ---------------------------------
        // Transfer 1: 16 words
        // ---------------------------------
        write_reg(8'h00, 32'h1000);
        write_reg(8'h04, 32'h2000);
        write_reg(8'h08, 32'd16);
        write_reg(8'h0C, 32'h1);

        // Let at least two writes complete
        wait (pre_writes >= 2);
        @(negedge clk);

        if (pre_accepts != 1)
            $fatal(1, "Initial START not accepted");

        if (done_valid || pre_writes >= 16)
            $fatal(1, "Transfer completed before reset");

        $display(
            "PASS: Transfer active before reset, writes=%0d",
            pre_writes
        );

        // Assert synchronous reset
        rst_n = 0;

        // Allow the clocked RTL to process reset
        repeat (3) @(negedge clk);

        // The engine and requests must be inactive
        if (dut.u_engine.state !== 3'd0)
            $fatal(1, "Engine did not return to IDLE");

        if (rd_req_valid !== 1'b0 ||
            wr_req_valid !== 1'b0 ||
            done_valid !== 1'b0)
            $fatal(1,
                "Memory activity remained after reset");

        if (dut.ch0_pending !== 1'b0 ||
            dut.ch1_pending !== 1'b0 ||
            dut.ch0_issued !== 1'b0 ||
            dut.ch1_issued !== 1'b0)
            $fatal(1, "Channel state not cleared");

        $display("PASS: Active DMA transfer cancelled");

        // Status register should be cleared
        check_reg(
            8'h0C,
            32'h0,
            "CH0 control/status cleared by reset"
        );

        check_reg(
            8'h1C,
            32'h0,
            "CH1 control/status cleared by reset"
        );

        // No memory requests during settled reset
        repeat (5) @(negedge clk);

        if (rd_req_valid !== 1'b0 ||
            wr_req_valid !== 1'b0 ||
            done_valid !== 1'b0)
            $fatal(1, "Activity detected while in reset");

        // ---------------------------------
        // Release reset and recover
        // ---------------------------------
        phase = 1;
        rst_n = 1;

        // Verify no cancelled transfer resumes
        repeat (8) @(negedge clk);

        if (post_reads != 0 ||
            post_writes != 0 ||
            post_accepts != 0 ||
            post_completions != 0)
            $fatal(1,
                "Cancelled DMA resumed after reset");

        $display("PASS: No stale transfer after reset");

        // ---------------------------------
        // Transfer 2: 3 words
        // ---------------------------------
        write_reg(8'h00, 32'h5000);
        write_reg(8'h04, 32'h6000);
        write_reg(8'h08, 32'd3);
        write_reg(8'h0C, 32'h1);

        wait (post_completions == 1);
        @(negedge clk);

        if (post_reads != 3 ||
            post_writes != 3 ||
            post_accepts != 1)
            $fatal(1, "Recovery transfer count mismatch");

        check_reg(
            8'h0C,
            32'h4,
            "CH0 DONE after recovery"
        );

        // Observe for duplicate commands
        repeat (20) @(negedge clk);

        if (post_reads != 3 ||
            post_writes != 3 ||
            post_accepts != 1 ||
            post_completions != 1)
            $fatal(1,
                "Unexpected activity after recovery");

        $display("PASS: Recovery transfer completed");
        $display("PASS: No duplicate DMA transactions");
        $display("--------------------------------");
        $display("DMA RESET RECOVERY TEST PASSED");
        $display("--------------------------------");

        $finish;
    end

    // Simulation timeout
    initial begin
        #20000;
        $fatal(1, "DMA reset recovery timeout");
    end

endmodule

