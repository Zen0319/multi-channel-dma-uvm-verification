
`timescale 1ns/1ps

module tb_dma_arbiter;

    logic clk = 0;
    logic rst_n;
    logic req0, req1, accept;
    logic grant0, grant1;

    // 10 ns clock period
    always #5 clk = ~clk;

    // Instantiate DUT
    dma_arbiter dut (
        .clk(clk),
        .rst_n(rst_n),
        .req0(req0),
        .req1(req1),
        .accept(accept),
        .grant0(grant0),
        .grant1(grant1)
    );

    // Check expected grant values
    task automatic check_grant(
        input logic exp0,
        input logic exp1,
        input string test_name
    );
        #1;
        if (grant0 !== exp0 || grant1 !== exp1) begin
            $fatal(1,
                "FAIL: %s | grant0=%b grant1=%b",
                test_name, grant0, grant1);
        end
        $display("PASS: %s", test_name);
    endtask

    initial begin
        rst_n = 0;
        req0 = 0;
        req1 = 0;
        accept = 0;

        // Apply synchronous reset
        repeat (2) @(negedge clk);
        rst_n = 1;

        // Test 1: No requests
        check_grant(0, 0, "No requests");

        // Test 2: Only channel 0
        req0 = 1;
        req1 = 0;
        check_grant(1, 0, "Channel 0 request");

        // Test 3: Only channel 1
        req0 = 0;
        req1 = 1;
        check_grant(0, 1, "Channel 1 request");

        // Test 4: Both request, priority = 0
        req0 = 1;
        req1 = 1;
        check_grant(1, 0, "Initial priority 0");

        // Test 5: Accept channel 0
        @(negedge clk);
        accept = 1;

        @(negedge clk);
        accept = 0;

        check_grant(0, 1, "Priority rotated to 1");

        // Test 6: Accept channel 1
        @(negedge clk);
        accept = 1;

        @(negedge clk);
        accept = 0;

        check_grant(1, 0, "Priority rotated to 0");

        $display("----------------------------");
        $display("ALL ARBITER TESTS PASSED");
        $display("----------------------------");

        $finish;
    end
    initial begin
      $fsdbDumpfile("results/arbiter.fsdb");
      $fsdbDumpvars(0, tb_dma_arbiter);
    end
endmodule
