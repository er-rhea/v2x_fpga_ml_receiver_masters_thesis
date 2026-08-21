`timescale 1ns/1ps
module tb_cnn_top;

    // ----------------------------------------------------------------
    // Parameters
    // ----------------------------------------------------------------
    parameter TIME_SAMPLES = 624;
    parameter CIN1         = 29;
    parameter COUT_OUT     = 2;
    parameter N_DATA       = 24;
    parameter TEST_IDX     = 1;

    // ----------------------------------------------------------------
    // DUT I/O
    // ----------------------------------------------------------------
    reg clk;
    reg rst_n;
    reg start_inference;
    reg signed [N_DATA-1:0] input_data;
    reg input_data_valid;
    wire signed [N_DATA-1:0] output_result;
    wire output_valid;
    wire output_done;
    wire [7:0] progress;

    // ----------------------------------------------------------------
    // Instantiate DUT
    // ----------------------------------------------------------------
    cnn_top dut (
        .clk_in           (clk),
        .rst_n            (rst_n),           // Fixed: Direct connection (active-low)
        .start_inference  (start_inference),
        .input_data       (input_data),
        .input_data_valid (input_data_valid),
        .output_result    (output_result),
        .output_valid     (output_valid),
        .output_done      (output_done),
        .progress         (progress)
    );

    // ----------------------------------------------------------------
    // Clock generation (50 MHz)
    // ----------------------------------------------------------------
    initial clk = 1'b0;
    always #10 clk = ~clk;

    // ----------------------------------------------------------------
    // Reset
    // ----------------------------------------------------------------
    initial begin
        rst_n = 1'b0;
        start_inference = 1'b0;
        input_data = 0;
        input_data_valid = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        $display("[%0t] Reset released", $time);
    end

    // ----------------------------------------------------------------
    // File setup
    // ----------------------------------------------------------------
    reg [1023:0] in_fname;
    reg [1023:0] out_fname;

    initial begin
        $sformat(in_fname,  "hdl_hex_data/test_input_01.hex");
        $sformat(out_fname, "hdl_hex_data/test_output_01.hex");
        $display("Using input file : %s", in_fname);
        $display("Using golden file: %s", out_fname);
    end

    // ----------------------------------------------------------------
    // Buffers
    // ----------------------------------------------------------------
    parameter IN_WORDS  = TIME_SAMPLES * CIN1;
    parameter OUT_WORDS = TIME_SAMPLES * COUT_OUT;

    reg signed [N_DATA-1:0] in_chan_major [0:IN_WORDS-1];
    reg signed [N_DATA-1:0] out_chan_major [0:OUT_WORDS-1];
    reg signed [N_DATA-1:0] stim_time_major [0:IN_WORDS-1];
    reg signed [N_DATA-1:0] gold_time_major [0:OUT_WORDS-1];

    integer t, c, j;
    integer idx_tm, idx_cm;

    // ----------------------------------------------------------------
    // Load and reorder
    // ----------------------------------------------------------------
    initial begin
        $readmemh(in_fname,  in_chan_major);
        $readmemh(out_fname, out_chan_major);

        for (t = 0; t < TIME_SAMPLES; t = t + 1)
            for (c = 0; c < CIN1; c = c + 1) begin
                idx_tm = t * CIN1 + c;
                idx_cm = c * TIME_SAMPLES + t;
                stim_time_major[idx_tm] = in_chan_major[idx_cm];
            end

        for (t = 0; t < TIME_SAMPLES; t = t + 1)
            for (j = 0; j < COUT_OUT; j = j + 1) begin
                idx_tm = t * COUT_OUT + j;
                idx_cm = j * TIME_SAMPLES + t;
                gold_time_major[idx_tm] = out_chan_major[idx_cm];
            end

        $display("[%0t] Data loaded and reordered", $time);
    end

    // ----------------------------------------------------------------
    // Drive the DUT
    // ----------------------------------------------------------------
    integer in_idx;
    integer num_input_samples;
    initial begin
        in_idx = 0;
        wait (rst_n);
        repeat (5) @(posedge clk);

        num_input_samples = $size(stim_time_major);
        $display("[%0t] Starting inference... (%0d samples)", $time, num_input_samples);

        start_inference <= 1'b1;
        @(posedge clk);
        start_inference <= 1'b0;

        while (in_idx < num_input_samples) begin
            @(posedge clk);
            input_data       <= stim_time_major[in_idx];
            input_data_valid <= 1'b1;
            in_idx = in_idx + 1;
        end

        @(posedge clk);
        input_data_valid <= 1'b0;
        $display("[%0t] Input feed complete", $time);

        wait (output_done);
        repeat (5) @(posedge clk);

        $display("[%0t] Inference completed", $time);
        $display("Mismatches total: %0d", mismatches);
        //if (mismatches == 0)
           // $display("*** TEST PASSED ***");
        //else
           // $display("*** TEST FAILED ***");
        //$finish;
    end

    // ----------------------------------------------------------------
    // Output comparison
    // ----------------------------------------------------------------
    integer out_idx;
    integer mismatches;
    initial begin
        out_idx = 0;
        mismatches = 0;
    end

    always @(posedge clk) begin
        if (output_valid) begin
            if (out_idx < OUT_WORDS) begin
                if (output_result !== gold_time_major[out_idx]) begin
                    mismatches = mismatches + 1;
                    if (mismatches <= 10)
                        $display("[%0t] MISMATCH @ out_idx=%0d RTL=%h GOLD=%h",
                                 $time, out_idx, output_result, gold_time_major[out_idx]);
                end else begin
                    if (out_idx < 5 || out_idx >= OUT_WORDS - 5)
                        $display("[%0t] MATCH @ out_idx=%0d RTL=%h GOLD=%h",
                                 $time, out_idx, output_result, gold_time_major[out_idx]);
                end
            end
            out_idx = out_idx + 1;
        end
    end

    // ----------------------------------------------------------------
    // Minimal state monitoring
    // ----------------------------------------------------------------
    reg [3:0] prev_state;
    initial prev_state = 4'hF;

    always @(posedge clk) begin
        if (dut.state != prev_state) begin
            prev_state = dut.state;
            $display("[%0t] DUT State -> %0d (Progress: 0x%h)", $time, dut.state, progress);
        end
    end
	// In testbench
always @(posedge clk) begin
    if (dut.u_conv.output_valid && dut.u_conv.t_out < 3) begin
        automatic logic signed [47:0] mac = dut.u_conv.mac_result;
        automatic logic signed [23:0] bias = dut.u_conv.bias_q;
        automatic logic signed [47:0] bias_scaled;
        automatic logic signed [47:0] acc_with_bias;
        automatic logic signed [47:0] shifted;
        automatic logic [7:0] shift_amt = dut.cfg_shift_out;
        automatic logic is_out = dut.cfg_is_output_layer;
        
        if (is_out) begin
            // Output layer: bias after shift
            shifted = mac >>> shift_amt;
            acc_with_bias = shifted + $signed({24'b0, bias});
            $display("[OUT] t=%0d j=%0d: mac=%h shift=%0d?%h bias=%h final=%h (expected=%h)",
                     dut.u_conv.t_out, dut.u_conv.j_out, 
                     mac, shift_amt, shifted, bias, acc_with_bias[23:0],
                     gold_time_major[dut.u_conv.t_out * 2 + dut.u_conv.j_out]);
        end else begin
            // Hidden layer: bias before shift
            bias_scaled = $signed({24'b0, bias}) << 20;
            acc_with_bias = mac + bias_scaled;
            shifted = acc_with_bias >>> shift_amt;
            $display("[HID] t=%0d j=%0d: mac=%h bias_sc=%h sum=%h shift=%0d?%h (expected hidden layer output)",
                     dut.u_conv.t_out, dut.u_conv.j_out,
                     mac, bias_scaled, acc_with_bias, shift_amt, shifted[23:0]);
        end
    end
end
    // ----------------------------------------------------------------
    // Timeout
    // ----------------------------------------------------------------
    initial begin
        #2_000_000_000; // 2 ms sim time
        $display("[%0t] TIMEOUT!", $time);
        $display("  DUT state=%0d conv_state=%0d progress=0x%h", 
                 dut.state, dut.u_conv.state, progress);
        //$display("  read_addr=%0d/%0d write_addr=%0d/%0d",
                 //dut.read_addr, dut.read_bound, dut.write_addr, dut.write_bound);
        //$display("  samples_rcvd=%0d/%0d",
                // dut.u_conv.samples_received, dut.u_conv.samples_needed);
        $display("  conv_ready=%b conv_done=%b", dut.conv_ready, dut.conv_done);
        $finish;
    end

endmodule
