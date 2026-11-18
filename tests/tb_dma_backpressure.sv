
`timescale 1ns/1ps

module tb_dma_backpressure;

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

    // Completion interface
    logic done_valid, done_channel;

    int cycles;
    int read_count, write_count;
    int accept_count, done_count;
    int read_stall_cycles, write_stall_cycles;

    logic prev_read_stall, prev_write_stall;
    logic [31:0] held_read_addr;
    logic [31:0] held_write_addr;
    logic [31:0] held_write_data;

    always #5 clk = ~clk;

    // ----------------------------------
    // DMA Controller DUT
    // ----------------------------------
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

    // ----------------------------------
    // Aggressive memory backpressure
    // ----------------------------------
    // Hold reads initially, then accept
    // only one out of every five cycles.
    assign rd_req_ready =
        rst_n && (cycles >= 30) &&
        ((cycles % 5) == 0);

    // Hold writes initially, then accept
    // only one out of every seven cycles.
    assign wr_req_ready =
        rst_n && (cycles >= 65) &&
        ((cycles % 7) == 0);

    assign rd_rsp_data = response_data;

    // ----------------------------------
    // Memory read response model
    // ----------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles        <= 0;
            rd_rsp_valid  <= 0;
            response_data <= 0;
        end
        else begin
            cycles <= cycles + 1;

            if (rd_req_valid && rd_req_ready) begin
                rd_rsp_valid  <= 1'b1;
                response_data <= pattern(rd_req_addr);
            end
            else if (rd_rsp_valid && rd_rsp_ready) begin
                rd_rsp_valid <= 1'b0;
            end
        end
    end

    // ----------------------------------
    // CPU register write
    // ----------------------------------
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
            $fatal(1, "Configuration not ready");

        @(negedge clk);
        cfg_valid = 0;
        cfg_write = 0;
    endtask

    // ----------------------------------
    // Protocol monitor and scoreboard
    // ----------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            prev_read_stall  <= 0;
            prev_write_stall <= 0;
            held_read_addr   <= 0;
            held_write_addr  <= 0;
            held_write_data  <= 0;
        end
        else begin

            // READ: if stalled last cycle,
            // VALID and address must persist.
            if (prev_read_stall) begin
                if (rd_req_valid !== 1'b1)
                    $fatal(1,
                        "READ VALID dropped during stall");

                if (rd_req_addr !== held_read_addr)
                    $fatal(1,
                        "READ address changed during stall");
            end

            // WRITE: VALID, address and data
            // must remain stable under stalls.
            if (prev_write_stall) begin
                if (wr_req_valid !== 1'b1)
                    $fatal(1,
                        "WRITE VALID dropped during stall");

                if (wr_req_addr !== held_write_addr)
                    $fatal(1,
                        "WRITE address changed during stall");

                if (wr_req_data !== held_write_data)
                    $fatal(1,
                        "WRITE data changed during stall");
            end

            // Record stalled requests.
            prev_read_stall <=
                rd_req_valid && !rd_req_ready;

            prev_write_stall <=
                wr_req_valid && !wr_req_ready;

            held_read_addr  <= rd_req_addr;
            held_write_addr <= wr_req_addr;
            held_write_data <= wr_req_data;

            if (rd_req_valid && !rd_req_ready)
                read_stall_cycles++;

            if (wr_req_valid && !wr_req_ready)
                write_stall_cycles++;

            // Count accepted DMA commands
            if (dut.arb_accept) begin
                if (dut.start_channel !== 1'b0)
                    $fatal(1, "Unexpected CH1 START");

                accept_count++;

                if (accept_count > 1)
                    $fatal(1, "Duplicate START detected");
            end

            // Check accepted read requests
            if (rd_req_valid && rd_req_ready) begin
                if (read_count >= 8)
                    $fatal(1, "Excess READ requests");

                if (rd_req_addr !==
                    (32'h1000 + read_count * 4))
                    $fatal(1,
                        "READ address error at word %0d",
                        read_count);

                read_count++;
            end

            // Check accepted write requests
            if (wr_req_valid && wr_req_ready) begin
                if (write_count >= 8)
                    $fatal(1, "Excess WRITE requests");

                if (wr_req_addr !==
                    (32'h2000 + write_count * 4))
                    $fatal(1,
                        "WRITE address error at word %0d",
                        write_count);

                if (wr_req_data !== pattern(
                    32'h1000 + write_count * 4))
                    $fatal(1,
                        "WRITE data mismatch at word %0d",
                        write_count);

                write_count++;
            end

            // Check completion
            if (done_valid) begin
                if (done_channel !== 1'b0)
                    $fatal(1, "Wrong completion channel");

                if (read_count != 8 || write_count != 8)
                    $fatal(1,
                        "DMA completed before all writes");

                done_count++;

                if (done_count > 1)
                    $fatal(1, "Duplicate completion");
            end
        end
    end

    // ----------------------------------
    // Waveforms
    // ----------------------------------
    initial begin
        $fsdbDumpfile("results/dma_backpressure.fsdb");
        $fsdbDumpvars(0, tb_dma_backpressure);
    end

    // ----------------------------------
    // Main test
    // ----------------------------------
    initial begin
        rst_n = 0;
        cfg_valid = 0;
        cfg_write = 0;
        cfg_addr = 0;
        cfg_wdata = 0;

        read_count = 0;
        write_count = 0;
        accept_count = 0;
        done_count = 0;
        read_stall_cycles = 0;
        write_stall_cycles = 0;

        repeat (2) @(negedge clk);
        rst_n = 1;

        $display("Starting DMA backpressure test");

        // Channel 0, eight 32-bit words
        write_reg(8'h00, 32'h1000);
        write_reg(8'h04, 32'h2000);
        write_reg(8'h08, 32'd8);
        write_reg(8'h0C, 32'h1);

        wait (done_count == 1);
        @(negedge clk);

        if (read_count != 8 || write_count != 8)
            $fatal(1, "Transfer count mismatch");

        if (accept_count != 1)
            $fatal(1, "Incorrect START count");

        // Ensure long stalls occurred
        if (read_stall_cycles < 10)
            $fatal(1,
                "Insufficient READ backpressure");

        if (write_stall_cycles < 10)
            $fatal(1,
                "Insufficient WRITE backpressure");

        $display("PASS: 8 reads and 8 writes verified");
        $display("PASS: READ VALID/address stable");
        $display("PASS: WRITE VALID/address/data stable");
        $display(
            "READ stall cycles  = %0d",
            read_stall_cycles
        );
        $display(
            "WRITE stall cycles = %0d",
            write_stall_cycles
        );

        // Observe for unintended relaunch
        repeat (20) @(negedge clk);

        if (accept_count != 1 ||
            done_count != 1 ||
            read_count != 8 ||
            write_count != 8)
            $fatal(1,
                "Unexpected DMA activity after completion");

        $display("PASS: No duplicate DMA transactions");
        $display("--------------------------------");
        $display("DMA BACKPRESSURE TEST PASSED");
        $display("--------------------------------");

        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "DMA backpressure test timeout");
    end

endmodule

