
`timescale 1ns/1ps
module dma_arbiter (
    input  logic clk,
    input  logic rst_n,

    input  logic req0,
    input  logic req1,
    input  logic accept,

    output logic grant0,
    output logic grant1
);

    logic priority_reg;

    // Combinational arbitration
    always_comb begin
        grant0 = 1'b0;
        grant1 = 1'b0;

        case ({req1, req0})
            2'b01: grant0 = 1'b1;
            2'b10: grant1 = 1'b1;

            2'b11: begin
                if (priority_reg == 1'b0)
                    grant0 = 1'b1;
                else
                    grant1 = 1'b1;
            end

            default: begin
                grant0 = 1'b0;
                grant1 = 1'b0;
            end
        endcase
    end

    // Rotate priority_reg only when selected
    // channel is accepted
    always_ff @(posedge clk) begin
        if (!rst_n)
            priority_reg <= 1'b0;
        else if (accept && grant0)
            priority_reg <= 1'b1;
        else if (accept && grant1)
            priority_reg <= 1'b0;
    end

endmodule

