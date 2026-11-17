
`timescale 1ns/1ps

module tb_dma_arbitration;

    logic clk = 0;
    logic rst_n;

    logic cfg_valid, cfg_write;
    logic [7:0] cfg_addr;
    logic [31:0] cfg_wdata;
    logic cfg_ready;
    logic [31:0] cfg_rdata;

    logic rd_req_valid, rd_req_ready;
    logic [31:0] rd_req_addr;
    logic rd_rsp_valid, rd_rsp_ready;
    logic [31:0] rd_rsp_data, response_data;

    logic wr_req_valid, wr_req_ready;
    logic [31:0] wr_req_addr, wr_req_data;

    logic done_valid, done_channel;

    int cycles;
    int accepts_ch0, accepts_ch1;
    int reads_ch0, reads_ch1;
    int writes_ch0, writes_ch1;
    int done_ch0, done_ch1;
    int accept_total;

    always #5 clk = ~clk;

    // Design under test
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

    function automatic logic [31:0] pattern(
        input logic [31:0] addr
    );
        return addr ^ 32'hA5A5_5A5A;
    endfunction

    // Add periodic memory stalls
    assign rd_req_ready = (cycles % 3 != 0);
    assign wr_req_ready = (cycles % 4 != 0);
    assign rd_rsp_data = response_data;

    // Memory read responder
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            rd_rsp_valid <= 0;
            response_data <= 0;
        end
        else begin
            cycles <= cycles + 1;

            if (rd_req_valid && rd_req_ready) begin
                rd_rsp_valid <= 1;
                response_data <= pattern(rd_req_addr);
            end
            else if (rd_rsp_valid && rd_rsp_ready) begin
                rd_rsp_valid <= 0;
            end
        end
    end

    // CPU register writer
    task automatic write_reg(
        input logic [7:0] addr,
        input logic [31:0] data
    );
        @(negedge clk);

        cfg_valid = 1;
        cfg_write = 1;
        cfg_addr = addr;
        cfg_wdata = data;

        if (cfg_ready !== 1'b1)
            $fatal(1, "Configuration not ready");

        @(negedge clk);
        cfg_valid = 0;
        cfg_write = 0;
    endtask

    // Check all accepted DMA commands
    always @(posedge clk) begin
        if (rst_n) begin

            if (dut.arb_accept) begin
            $display(
                "DEBUG time=%0t accepted_ch=%0d grant0=%b grant1=%b pending0=%b pending1=%b issued0=%b issued1=%b",
                $time,
                dut.start_channel,
                dut.grant0,
                dut.grant1,
                dut.ch0_pending,
                dut.ch1_pending,
                dut.ch0_issued,
                dut.ch1_issued
             );
                if (accept_total == 0 &&
                    dut.start_channel !== 1'b0)
                    $fatal(1,
                        "Arbitration error: CH0 must win first");

                if (accept_total == 1 &&
                    dut.start_channel !== 1'b1)
                    $fatal(1,
                        "Arbitration error: CH1 must run second");

                if (accept_total >= 2)
                    $fatal(1,
                        "Unexpected extra DMA acceptance");

                if (dut.start_channel == 0)
                    accepts_ch0++;
                else
                    accepts_ch1++;

                accept_total++;
            end

            // Check memory read addresses
            if (rd_req_valid && rd_req_ready) begin
                if (rd_req_addr >= 32'h1000 &&
                    rd_req_addr < 32'h1010) begin

                    if (rd_req_addr !==
                        (32'h1000 + reads_ch0 * 4))
                        $fatal(1, "CH0 read address mismatch");

                    reads_ch0++;
                end
                else if (rd_req_addr >= 32'h3000 &&
                         rd_req_addr < 32'h3020) begin

                    if (rd_req_addr !==
                        (32'h3000 + reads_ch1 * 4))
                        $fatal(1, "CH1 read address mismatch");

                    reads_ch1++;
                end
                else
                    $fatal(1,
                        "Unexpected read address %h",
                        rd_req_addr);
            end

            // Check memory writes and data
            if (wr_req_valid && wr_req_ready) begin
                if (wr_req_addr >= 32'h2000 &&
                    wr_req_addr < 32'h2010) begin

                    if (wr_req_addr !==
                        (32'h2000 + writes_ch0 * 4))
                        $fatal(1, "CH0 write address mismatch");

                    if (wr_req_data !== pattern(
                        32'h1000 + writes_ch0 * 4))
                        $fatal(1, "CH0 data mismatch");

                    writes_ch0++;
                end
                else if (wr_req_addr >= 32'h4000 &&
                         wr_req_addr < 32'h4020) begin

                    if (wr_req_addr !==
                        (32'h4000 + writes_ch1 * 4))
                        $fatal(1, "CH1 write address mismatch");

                    if (wr_req_data !== pattern(
                        32'h3000 + writes_ch1 * 4))
                        $fatal(1, "CH1 data mismatch");

                    writes_ch1++;
                end
                else
                    $fatal(1,
                        "Unexpected write address %h",
                        wr_req_addr);
            end

            // Check completion after all writes
            if (done_valid) begin
                if (done_channel == 0) begin
                    if (reads_ch0 != 4 || writes_ch0 != 4)
                        $fatal(1, "CH0 incomplete transfer");

                    done_ch0++;

                    if (done_ch0 > 1)
                        $fatal(1, "Duplicate CH0 completion");
                end
                else begin
                    if (reads_ch1 != 8 || writes_ch1 != 8)
                        $fatal(1, "CH1 incomplete transfer");

                    done_ch1++;

                    if (done_ch1 > 1)
                        $fatal(1, "Duplicate CH1 completion");
                end
            end
        end
    end

    // Save waveforms
    initial begin
        $fsdbDumpfile("results/dma_arbitration.fsdb");
        $fsdbDumpvars(0, tb_dma_arbitration);
    end

    // Test sequence
    initial begin
        rst_n = 0;
        cfg_valid = 0;
        cfg_write = 0;
        cfg_addr = 0;
        cfg_wdata = 0;

        accepts_ch0 = 0;
        accepts_ch1 = 0;
        reads_ch0 = 0;
        reads_ch1 = 0;
        writes_ch0 = 0;
        writes_ch1 = 0;
        done_ch0 = 0;
        done_ch1 = 0;
        accept_total = 0;

        repeat (2) @(negedge clk);
        rst_n = 1;

        // Verification-only: prevent command acceptance
        // while both channels are being configured.
        force dut.u_engine.start_ready = 1'b0;

        $display("Starting simultaneous-request arbitration test");

        // Program CH0: 4 words
        write_reg(8'h00, 32'h1000);
        write_reg(8'h04, 32'h2000);
        write_reg(8'h08, 32'd4);

        // Program CH1: 8 words
        write_reg(8'h10, 32'h3000);
        write_reg(8'h14, 32'h4000);
        write_reg(8'h18, 32'd8);

        // Queue both channels before enabling acceptance
        write_reg(8'h0C, 32'h1);
        write_reg(8'h1C, 32'h1);

        #1;

        if (dut.ch0_request !== 1'b1 ||
            dut.ch1_request !== 1'b1)
            $fatal(1,
                "Both DMA channels are not pending");

        if (dut.grant0 !== 1'b1 ||
            dut.grant1 !== 1'b0)
            $fatal(1,
                "Incorrect initial round-robin priority");

        if (accept_total != 0)
            $fatal(1,
                "DMA accepted a command while stalled");
        if (dut.u_engine.state !== 3'd0)
            $fatal(1,
               "DMA engine left IDLE while START was blocked");

        $display("PASS: Both channels queued simultaneously");
        $display("PASS: CH0 has initial arbitration priority");

        // Allow DMA engine to accept the queued commands
        @(negedge clk);
        release dut.u_engine.start_ready;

        // Wait until both channels finish
        wait (done_ch0 == 1 && done_ch1 == 1);
        @(negedge clk);

        if (accepts_ch0 != 1 || accepts_ch1 != 1)
            $fatal(1,
                "Acceptance mismatch CH0=%0d CH1=%0d",
                accepts_ch0, accepts_ch1);

        if (reads_ch0 != 4 || writes_ch0 != 4 ||
            reads_ch1 != 8 || writes_ch1 != 8)
            $fatal(1, "Transfer-count mismatch");

        $display("PASS: CH0 accepted and completed");
        $display("PASS: CH1 accepted and completed");
        $display("PASS: Arbitration order CH0 then CH1");

        // Watch for unexpected extra commands
        repeat (20) @(negedge clk);

        if (accept_total != 2 ||
            done_ch0 != 1 || done_ch1 != 1)
            $fatal(1, "Unexpected duplicate DMA operation");

        $display("PASS: No lost or duplicate requests");
        $display("--------------------------------");
        $display("DMA ARBITRATION TEST PASSED");
        $display("--------------------------------");

        $finish;
    end

    // Simulation timeout
    initial begin
        #20000;
        $fatal(1, "DMA arbitration test timeout");
    end

endmodule

