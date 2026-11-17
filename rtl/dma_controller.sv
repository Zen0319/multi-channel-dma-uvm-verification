
`timescale 1ns/1ps

module dma_controller (
    input  logic        clk,
    input  logic        rst_n,

    // CPU configuration interface
    input  logic        cfg_valid,
    input  logic        cfg_write,
    input  logic [7:0]  cfg_addr,
    input  logic [31:0] cfg_wdata,
    output logic        cfg_ready,
    output logic [31:0] cfg_rdata,

    // External memory read request
    output logic        rd_req_valid,
    input  logic        rd_req_ready,
    output logic [31:0] rd_req_addr,

    // External memory read response
    input  logic        rd_rsp_valid,
    output logic        rd_rsp_ready,
    input  logic [31:0] rd_rsp_data,

    // External memory write request
    output logic        wr_req_valid,
    input  logic        wr_req_ready,
    output logic [31:0] wr_req_addr,
    output logic [31:0] wr_req_data,

    // Completion indication
    output logic        done_valid,
    output logic        done_channel
);

    // Channel configuration signals
    logic [31:0] ch0_src;
    logic [31:0] ch0_dst;
    logic [31:0] ch0_len;

    logic [31:0] ch1_src;
    logic [31:0] ch1_dst;
    logic [31:0] ch1_len;

    // Channel requests
    logic ch0_pending;
    logic ch1_pending;

    // Arbiter grants
    logic grant0;
    logic grant1;
    logic arb_accept;
    
    
    // Prevent channels from being issued twice
    logic ch0_issued;
    logic ch1_issued;

    // Requests eligible for arbitration
    logic ch0_request;
    logic ch1_request;

    assign ch0_request = ch0_pending && !ch0_issued;
    assign ch1_request = ch1_pending && !ch1_issued;


    // DMA engine command interface
    logic        start_valid;
    logic        start_ready;
    logic        start_channel;
    logic [31:0] start_src;
    logic [31:0] start_dst;
    logic [31:0] start_len;

    // Completion feedback to registers
    logic ch0_done;
    logic ch1_done;

    // ------------------------------------
    // 1. Configuration Register Block
    // ------------------------------------

    dma_cfg_regs u_cfg_regs (
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

    // ------------------------------------
    // 2. Round-Robin Arbiter
    // ------------------------------------

    dma_arbiter u_arbiter (
        .clk(clk),
        .rst_n(rst_n),

        
        .req0(ch0_request),
        .req1(ch1_request),

        .accept(arb_accept),

        .grant0(grant0),
        .grant1(grant1)
    );
    // ------------------------------------
    // 3. Select the Granted Channel
    // ------------------------------------

    always_comb begin
        start_valid   = grant0 || grant1;

        start_channel = 1'b0;
        start_src     = 32'd0;
        start_dst     = 32'd0;
        start_len     = 32'd0;

        if (grant0) begin
            start_channel = 1'b0;
            start_src     = ch0_src;
            start_dst     = ch0_dst;
            start_len     = ch0_len;
        end
        else if (grant1) begin
            start_channel = 1'b1;
            start_src     = ch1_src;
            start_dst     = ch1_dst;
            start_len     = ch1_len;
        end
    end

    // A grant is accepted only if the
    // engine is ready for a new command.
    assign arb_accept = start_valid && start_ready;
    
    
    // Track channels accepted by the DMA engine
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ch0_issued <= 1'b0;
            ch1_issued <= 1'b0;
        end
        else begin
            // Mark the selected channel as issued
            if (arb_accept && grant0)
                ch0_issued <= 1'b1;

            if (arb_accept && grant1)
                ch1_issued <= 1'b1;

            // Release issued state at completion
            if (done_valid && !done_channel)
                ch0_issued <= 1'b0;

            if (done_valid && done_channel)
                ch1_issued <= 1'b0;
        end
    end


    // ------------------------------------
    // 4. DMA Transfer Engine
    // ------------------------------------

    dma_engine u_engine (
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

    // ------------------------------------
    // 5. Completion Feedback
    // ------------------------------------

    assign ch0_done = done_valid && !done_channel;
    assign ch1_done = done_valid &&  done_channel;

endmodule

