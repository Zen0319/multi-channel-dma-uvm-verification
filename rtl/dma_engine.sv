
`timescale 1ns/1ps

module dma_engine (
    input  logic        clk,
    input  logic        rst_n,

    // Transfer command from arbiter/controller
    input  logic        start_valid,
    output logic        start_ready,
    input  logic        start_channel,
    input  logic [31:0] start_src,
    input  logic [31:0] start_dst,
    input  logic [31:0] start_len,

    // Memory read request
    output logic        rd_req_valid,
    input  logic        rd_req_ready,
    output logic [31:0] rd_req_addr,

    // Memory read response
    input  logic        rd_rsp_valid,
    output logic        rd_rsp_ready,
    input  logic [31:0] rd_rsp_data,

    // Memory write request
    output logic        wr_req_valid,
    input  logic        wr_req_ready,
    output logic [31:0] wr_req_addr,
    output logic [31:0] wr_req_data,

    // Transfer completion
    output logic        done_valid,
    output logic        done_channel
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_READ_REQ,
        ST_WAIT_RSP,
        ST_WRITE_REQ,
        ST_DONE
    } state_t;

    state_t state;

    logic [31:0] src_addr;
    logic [31:0] dst_addr;
    logic [31:0] data_buffer;
    logic [8:0]  words_left;
    logic        active_channel;

    // Output handshake logic
    assign start_ready  = (state == ST_IDLE);

    assign rd_req_valid = (state == ST_READ_REQ);
    assign rd_req_addr  = src_addr;

    assign rd_rsp_ready = (state == ST_WAIT_RSP);

    assign wr_req_valid = (state == ST_WRITE_REQ);
    assign wr_req_addr  = dst_addr;
    assign wr_req_data  = data_buffer;

    assign done_valid   = (state == ST_DONE);
    assign done_channel = active_channel;

    // DMA transfer state machine
    always_ff @(posedge clk) begin

        if (!rst_n) begin
            state          <= ST_IDLE;
            src_addr       <= 32'd0;
            dst_addr       <= 32'd0;
            data_buffer    <= 32'd0;
            words_left     <= 9'd0;
            active_channel <= 1'b0;
        end
        else begin

            case (state)

                ST_IDLE: begin
                    if (start_valid && start_ready) begin
                        src_addr       <= start_src;
                        dst_addr       <= start_dst;
                        words_left     <= start_len[8:0];
                        active_channel <= start_channel;
                        state          <= ST_READ_REQ;
                    end
                end

                ST_READ_REQ: begin
                    // Wait until memory accepts read request
                    if (rd_req_valid && rd_req_ready)
                        state <= ST_WAIT_RSP;
                end

                ST_WAIT_RSP: begin
                    // Capture returned read data
                    if (rd_rsp_valid && rd_rsp_ready) begin
                        data_buffer <= rd_rsp_data;
                        state       <= ST_WRITE_REQ;
                    end
                end

                ST_WRITE_REQ: begin
                    // Advance only when write is accepted
                    if (wr_req_valid && wr_req_ready) begin

                        if (words_left == 9'd1) begin
                            words_left <= 9'd0;
                            state      <= ST_DONE;
                        end
                        else begin
                            words_left <= words_left - 9'd1;
                            src_addr   <= src_addr + 32'd4;
                            dst_addr   <= dst_addr + 32'd4;
                            state      <= ST_READ_REQ;
                        end
                    end
                end

                ST_DONE: begin
                    // Completion pulse lasts one cycle
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end

            endcase
        end
    end

endmodule

