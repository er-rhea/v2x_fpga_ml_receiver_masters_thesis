module mac_24bits (
    input clock0,
    input ena0,
    input sclr0,
    input signed [23:0] dataa_0,
    input signed [23:0] datab_0,
    output reg signed [47:0] result
);
    always @(posedge clock0) begin
        if (sclr0)
            result <= 48'sd0;
        else if (ena0)
            result <= result + ($signed(dataa_0) * $signed(datab_0));
    end
endmodule
