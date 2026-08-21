module relu #(
    parameter integer W = 24
)(
    input  wire signed [W-1:0] in_data,
    input  wire                 in_valid,
    output reg  signed [W-1:0] out_data,
    output reg                  out_valid
);

    always @* begin
        out_data  = in_data[W-1] ? {W{1'b0}} : in_data;
        out_valid = in_valid;
    end

endmodule
