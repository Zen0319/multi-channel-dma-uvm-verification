`timescale 1ns/1ps


module tb_dma_engine;

logic clk = 0;
logic rst_n;

logic start_valid, start_ready;
logic start_channel;
logic [31:0] start_src, start_dst, start_len;

logic rd_req_valid, rd_req_ready;
logic [31:0] rd_req_addr;

logic rd_rsp_valid, rd_rsp_ready;
logic [31:0] rd_rsp_data;

logic wr_req_valid, wr_req_ready;
logic [31:0] wr_req_addr, wr_req_data;

logic done_valid, done_channel;

logic stall_enable;
int cycle_count;


int read_count = 0;
int write_count = 0;
int tests_passed = 0;

logic [31:0] expected_src;
logic [31:0] expected_dst;
int expected_len;
logic expected_channel;

logic [31:0] response_data;

// 100 MHz testbench clock
always #5 clk = ~clk;

// DUT
dma_engine dut (
.clk(clk),
.rst_n(rst_n),

.start_valid(start_valid),
.start_ready(start_ready),
.start_channel(start_channel),
.start_src(start_src),
.start_dst(start_dst),
.start_len(start_len),

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

// Deterministic source-memory contents
function automatic logic [31:0] memory_pattern(
input logic [31:0] addr
);
return addr ^ 32'hA5A5_5A5A;
endfunction

// Simulate occasional memory stalls
assign rd_req_ready =
!stall_enable || ((cycle_count % 3) == 0);

assign wr_req_ready =
!stall_enable || ((cycle_count % 4) == 0);

assign rd_rsp_data = response_data;


    // Memory read-response model
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd_rsp_valid <= 1'b0;
            response_data <= 32'd0;
            cycle_count   <= 0;
        end
        else begin
            cycle_count <= cycle_count + 1;

            if (rd_req_valid && rd_req_ready) begin
                rd_rsp_valid <= 1'b1;
                response_data <= memory_pattern(rd_req_addr);
            end
            else if (rd_rsp_valid && rd_rsp_ready) begin
                rd_rsp_valid <= 1'b0;
            end
        end
    end

    // Check read and write transactions
    always @(posedge clk) begin
        if (rst_n) begin

            if (rd_req_valid && rd_req_ready) begin
                if (rd_req_addr !==
                    (expected_src + (read_count * 4)))
                    $fatal(1,
                        "READ ADDRESS ERROR: got=%h",
                        rd_req_addr);

                read_count = read_count + 1;
            end

            if (wr_req_valid && wr_req_ready) begin

                if (wr_req_addr !==
                    (expected_dst + (write_count * 4)))
                    $fatal(1,
                        "WRITE ADDRESS ERROR: got=%h",
                        wr_req_addr);

                if (wr_req_data !== memory_pattern(
                    expected_src + (write_count * 4)
                ))
                    $fatal(1,
                        "WRITE DATA ERROR: got=%h",
                        wr_req_data);

                write_count = write_count + 1;
            end
        end
    end

    // Run one DMA transfer
    task automatic run_transfer(
        input logic channel,
        input logic [31:0] src,
        input logic [31:0] dst,
        input int length_words,
        input logic enable_stalls,
        input string test_name
    );

        int timeout;

        wait (start_ready == 1'b1);
        @(negedge clk);

        expected_src = src;
        expected_dst = dst;
        expected_len = length_words;
        expected_channel = channel;

        read_count = 0;
        write_count = 0;

        stall_enable = enable_stalls;

        start_channel = channel;
        start_src = src;
        start_dst = dst;
        start_len = length_words;
        start_valid = 1'b1;

        @(negedge clk);
        start_valid = 1'b0;

        timeout = 0;

        while (done_valid !== 1'b1 && timeout < 2500) begin
            @(posedge clk);
            #1;
            timeout++;
        end

        if (done_valid !== 1'b1)
            $fatal(1, "TIMEOUT: %s", test_name);

        if (done_channel !== expected_channel)
            $fatal(1, "WRONG CHANNEL: %s", test_name);

        if (read_count != expected_len)
            $fatal(1, "READ COUNT ERROR: %s", test_name);

        if (write_count != expected_len)
            $fatal(1, "WRITE COUNT ERROR: %s", test_name);

        tests_passed++;

        $display(
            "PASS: %s | channel=%0d words=%0d",
            test_name, channel, length_words
        );

        @(negedge clk);
    endtask

    // FSDB waveform dumping
    initial begin
        $fsdbDumpfile("results/dma_engine.fsdb");
        $fsdbDumpvars(0, tb_dma_engine);
    end

    // Main test sequence
    initial begin
        rst_n = 0;

        start_valid = 0;
        start_channel = 0;
        start_src = 0;
        start_dst = 0;
        start_len = 0;
        stall_enable = 0;

        repeat (2) @(negedge clk);
        rst_n = 1;

        run_transfer(
            0, 32'h00001000, 32'h00002000,
            4, 0, "CH0 four-word transfer"
        );

        run_transfer(
            1, 32'h00003000, 32'h00004000,
            8, 1, "CH1 transfer with stalls"
        );

        run_transfer(
            0, 32'h00005000, 32'h00006000,
            1, 0, "CH0 single-word transfer"
        );

        run_transfer(
            1, 32'h00007000, 32'h00008000,
            256, 1, "CH1 maximum-length transfer"
        );

        $display("--------------------------------");
        $display("ALL %0d DMA ENGINE TESTS PASSED",
                 tests_passed);
        $display("--------------------------------");

        $finish;
    end

    // Simulation watchdog
    initial begin
        #100000;
        $fatal(1, "GLOBAL SIMULATION TIMEOUT");
    end

endmodule

