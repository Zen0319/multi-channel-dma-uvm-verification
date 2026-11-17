
`timescale 1ns/1ps

module dma_cfg_regs (
    input  logic        clk,
    input  logic        rst_n,

    // CPU configuration interface
    input  logic        cfg_valid,
    input  logic        cfg_write,
    input  logic [7:0]  cfg_addr,
    input  logic [31:0] cfg_wdata,

    output logic        cfg_ready,
    output logic [31:0] cfg_rdata,

    // Channel 0 configuration
    output logic [31:0] ch0_src,
    output logic [31:0] ch0_dst,
    output logic [31:0] ch0_len,

    // Channel 1 configuration
    output logic [31:0] ch1_src,
    output logic [31:0] ch1_dst,
    output logic [31:0] ch1_len,

    // Pending transfer requests
    output logic        ch0_pending,
    output logic        ch1_pending,

    // Transfer completion signals
    input  logic        ch0_done,
    input  logic        ch1_done
);

    // Register addresses
    localparam logic [7:0] CH0_SRC_ADDR  = 8'h00;
    localparam logic [7:0] CH0_DST_ADDR  = 8'h04;
    localparam logic [7:0] CH0_LEN_ADDR  = 8'h08;
    localparam logic [7:0] CH0_CTRL_ADDR = 8'h0C;

    localparam logic [7:0] CH1_SRC_ADDR  = 8'h10;
    localparam logic [7:0] CH1_DST_ADDR  = 8'h14;
    localparam logic [7:0] CH1_LEN_ADDR  = 8'h18;
    localparam logic [7:0] CH1_CTRL_ADDR = 8'h1C;

    // Channel status registers
    logic ch0_done_status;
    logic ch1_done_status;
    logic ch0_error;
    logic ch1_error;

    // Validate a DMA transfer before accepting START.
    // V1 supports 1 to 256 aligned 32-bit words.
    // Neither address range may wrap past 0xFFFFFFFF.
    function automatic logic valid_transfer (
        input logic [31:0] src,
        input logic [31:0] dst,
        input logic [31:0] len
    );
        logic [32:0] last_src;
        logic [32:0] last_dst;
        logic [32:0] byte_offset;

        begin
            byte_offset = ({1'b0, len} - 33'd1) << 2;
            last_src = {1'b0, src} + byte_offset;
            last_dst = {1'b0, dst} + byte_offset;

            valid_transfer =
                (len >= 32'd1) &&
                (len <= 32'd256) &&
                (src[1:0] == 2'b00) &&
                (dst[1:0] == 2'b00) &&
                (!last_src[32]) &&
                (!last_dst[32]);
        end
    endfunction

    // Always-ready configuration interface
    assign cfg_ready = 1'b1;

    // Sequential register update logic
    always_ff @(posedge clk) begin
        if (!rst_n) begin

            // Reset Channel 0
            ch0_src         <= 32'd0;
            ch0_dst         <= 32'd0;
            ch0_len         <= 32'd0;
            ch0_pending     <= 1'b0;
            ch0_done_status <= 1'b0;
            ch0_error       <= 1'b0;

            // Reset Channel 1
            ch1_src         <= 32'd0;
            ch1_dst         <= 32'd0;
            ch1_len         <= 32'd0;
            ch1_pending     <= 1'b0;
            ch1_done_status <= 1'b0;
            ch1_error       <= 1'b0;

        end
        else begin

            // Handle completed transfers
            if (ch0_done && ch0_pending) begin
                ch0_pending     <= 1'b0;
                ch0_done_status <= 1'b1;
            end

            if (ch1_done && ch1_pending) begin
                ch1_pending     <= 1'b0;
                ch1_done_status <= 1'b1;
            end

            // CPU register writes
            if (cfg_valid && cfg_write && cfg_ready) begin

                case (cfg_addr)

                    // Channel 0 registers
                    CH0_SRC_ADDR: begin
                        if (!ch0_pending)
                            ch0_src <= cfg_wdata;
                    end

                    CH0_DST_ADDR: begin
                        if (!ch0_pending)
                            ch0_dst <= cfg_wdata;
                    end

                    CH0_LEN_ADDR: begin
                        if (!ch0_pending)
                            ch0_len <= cfg_wdata;
                    end

                    CH0_CTRL_ADDR: begin
                        if (cfg_wdata[0] && !ch0_pending) begin

                            ch0_done_status <= 1'b0;
                            ch0_error       <= 1'b0;

                            if (valid_transfer(
                                ch0_src, ch0_dst, ch0_len
                            )) begin
                                ch0_pending <= 1'b1;
                            end
                            else begin
                                ch0_error <= 1'b1;
                            end
                        end
                    end

                    // Channel 1 registers
                    CH1_SRC_ADDR: begin
                        if (!ch1_pending)
                            ch1_src <= cfg_wdata;
                    end

                    CH1_DST_ADDR: begin
                        if (!ch1_pending)
                            ch1_dst <= cfg_wdata;
                    end

                    CH1_LEN_ADDR: begin
                        if (!ch1_pending)
                            ch1_len <= cfg_wdata;
                    end

                    CH1_CTRL_ADDR: begin
                        if (cfg_wdata[0] && !ch1_pending) begin

                            ch1_done_status <= 1'b0;
                            ch1_error       <= 1'b0;

                            if (valid_transfer(
                                ch1_src, ch1_dst, ch1_len
                            )) begin
                                ch1_pending <= 1'b1;
                            end
                            else begin
                                ch1_error <= 1'b1;
                            end
                        end
                    end

                    default: begin
                        // Unmapped writes are ignored
                    end

                endcase
            end
        end
    end

    // CPU register read logic
    always_comb begin
        cfg_rdata = 32'd0;

        if (cfg_valid && !cfg_write) begin
            case (cfg_addr)

                CH0_SRC_ADDR:
                    cfg_rdata = ch0_src;

                CH0_DST_ADDR:
                    cfg_rdata = ch0_dst;

                CH0_LEN_ADDR:
                    cfg_rdata = ch0_len;

                CH0_CTRL_ADDR:
                    cfg_rdata = {
                        28'd0,
                        ch0_error,
                        ch0_done_status,
                        ch0_pending,
                        1'b0
                    };

                CH1_SRC_ADDR:
                    cfg_rdata = ch1_src;

                CH1_DST_ADDR:
                    cfg_rdata = ch1_dst;

                CH1_LEN_ADDR:
                    cfg_rdata = ch1_len;

                CH1_CTRL_ADDR:
                    cfg_rdata = {
                        28'd0,
                        ch1_error,
                        ch1_done_status,
                        ch1_pending,
                        1'b0
                    };

                default:
                    cfg_rdata = 32'd0;

            endcase
        end
    end

endmodule

