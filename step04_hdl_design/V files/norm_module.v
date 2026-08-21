module norm_module #(
    parameter integer N_DATA  = 24, // data width
    parameter integer NUM_FEAT = 29, // number of channels/features
    parameter integer SHIFT_N  = 0  // right shift after multiply (set per quantization)
)(
    input  wire clk,
    input  wire rst,

    // Input stream: channel-serial, one 24-bit value per cycle when data_valid=1
    input  wire signed [N_DATA-1:0] input_data,
    input  wire                     data_valid,

    // Output stream: one normalized 24-bit value per input sample
    output reg signed [N_DATA-1:0]  output_data,
    output reg                      output_valid
);

    // -----------------------------
    // Channel index
    // -----------------------------
    localparam integer FEAT_AW = 
        (NUM_FEAT <= 2)  ? 1 :
        (NUM_FEAT <= 4)  ? 2 :
        (NUM_FEAT <= 8)  ? 3 :
        (NUM_FEAT <= 16) ? 4 :
        (NUM_FEAT <= 32) ? 5 :
        (NUM_FEAT <= 64) ? 6 : 7;

    reg [FEAT_AW-1:0] ch_idx;

    // -----------------------------
    // ROM outputs (registered, 1-cycle latency inside ROM)
    // -----------------------------
    wire signed [N_DATA-1:0] mean_q;
    wire signed [N_DATA-1:0] invstd_q;

    // Instantiate your generated ROM IPs
    norm_mean u_norm_mean (
        .address(ch_idx),
        .clock(clk),
        .q(mean_q)
    );

    norm_std u_norm_std (
        .address(ch_idx),
        .clock(clk),
        .q(invstd_q)
    );

    // -----------------------------
    // Pipeline registers
    // -----------------------------
    // Stage 0: latch input and channel index
    reg signed [N_DATA-1:0] in_s0;
    reg [FEAT_AW-1:0] ch_s0;
    reg v_s0;

    // Stage 1: subtract mean
    reg signed [N_DATA:0] diff_s1; // 25-bit to hold subtraction
    reg v_s1;

    // Stage 2: multiply (diff * invstd)
    reg signed [47:0] prod_s2; 
    reg v_s2;

    // Stage 3: optional extra pipeline register
    reg signed [47:0] prod_s3;
    reg v_s3;

    // -----------------------------
    // Channel index sequencing
    // -----------------------------
    always @(posedge clk) begin
        if (rst) 
            ch_idx <= {FEAT_AW{1'b0}};
        else if (data_valid) 
            ch_idx <= (ch_idx == NUM_FEAT-1) ? {FEAT_AW{1'b0}} : ch_idx + 1'b1;
    end

    // -----------------------------
    // Stage 0: latch input and index
    // -----------------------------
    always @(posedge clk) begin
        if (rst) begin
            in_s0 <= 0; 
            ch_s0 <= 0; 
            v_s0 <= 1'b0;
        end else begin
            v_s0 <= data_valid;
            if (data_valid) begin
                in_s0 <= input_data;
                ch_s0 <= ch_idx;
            end
        end
    end

    // -----------------------------
    // Stage 1: subtract mean
    // -----------------------------
    always @(posedge clk) begin
        if (rst) begin
            diff_s1 <= 0;
            v_s1 <= 1'b0;
        end else begin
            v_s1 <= v_s0;
            if (v_s0) 
                diff_s1 <= $signed({in_s0[N_DATA-1], in_s0}) - $signed({mean_q[N_DATA-1], mean_q});
        end
    end

    // -----------------------------
    // Stage 2: multiply diff * invstd
    // -----------------------------
    always @(posedge clk) begin
        if (rst) begin
            prod_s2 <= 0; 
            v_s2 <= 1'b0;
        end else begin
            v_s2 <= v_s1;
            if (v_s1) 
                prod_s2 <= $signed(diff_s1[N_DATA-1:0]) * $signed(invstd_q);
        end
    end

    // -----------------------------
    // Stage 3: optional extra register
    // -----------------------------
    always @(posedge clk) begin
        if (rst) begin
            prod_s3 <= 0; 
            v_s3 <= 1'b0;
        end else begin
            v_s3 <= v_s2;
            prod_s3 <= prod_s2;
        end
    end

    // -----------------------------
    // Saturation helper function
    // -----------------------------
    function automatic signed [N_DATA-1:0] sat24;
        input signed [47:0] x;
        reg signed [N_DATA-1:0] maxv, minv;
        begin
            maxv = {1'b0, {(N_DATA-1){1'b1}}};
            minv = {1'b1, {(N_DATA-1){1'b0}}};
            if (x > $signed({1'b0, {(47){1'b1}}})) sat24 = maxv;
            else if (x < $signed({1'b1, {(47){1'b0}}})) sat24 = minv;
            else sat24 = x[N_DATA-1:0];
        end
    endfunction

    // -----------------------------
    // Output stage: shift, saturate
    // -----------------------------
    always @(posedge clk) begin
        if (rst) begin
            output_data <= 0;
            output_valid <= 1'b0;
        end else begin
            output_valid <= v_s3;
            if (v_s3) 
                output_data <= (SHIFT_N == 0) ? sat24(prod_s3) : sat24(prod_s3 >>> SHIFT_N);
        end
    end

endmodule
