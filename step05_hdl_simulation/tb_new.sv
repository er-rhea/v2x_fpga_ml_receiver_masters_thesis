`timescale 1ns/1ps
module tb_cnn_top_perf;

    parameter TIME_SAMPLES = 624;
    parameter CIN1 = 29;
    parameter COUT_OUT = 2;
    parameter N_DATA = 24;
    parameter CLK_FREQ_MHZ = 50;
    parameter CLK_PERIOD_NS = 20;

    reg clk, rst_n, start_inference;
    reg signed [N_DATA-1:0] input_data;
    reg input_data_valid;
    wire signed [N_DATA-1:0] output_result;
    wire output_valid, output_done;
    wire [7:0] progress;

    // Performance counters
    reg [63:0] cycle_count;
    reg [63:0] start_cycle, end_cycle, total_cycles;
    real execution_time_ms;
    real throughput_fps;

    // Error tracking
    integer mismatches;
    real sum_squared_error;
    real sum_abs_error;
    real max_error;
    integer total_outputs;
    real rmse, mae, max_abs_error;
    
    // Per-sample error for detailed analysis
    real errors [0:TIME_SAMPLES*COUT_OUT-1];

    cnn_top dut (
        .clk_in(clk),
        .rst_n(rst_n),
        .start_inference(start_inference),
        .input_data(input_data),
        .input_data_valid(input_data_valid),
        .output_result(output_result),
        .output_valid(output_valid),
        .output_done(output_done),
        .progress(progress)
    );

    // Clock
    initial clk = 0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    // Cycle counter
    always @(posedge clk) begin
        if (!rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    // Reset
    initial begin
        rst_n = 0;
        start_inference = 0;
        input_data = 0;
        input_data_valid = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        $display("[INFO] Reset released at cycle %0d", cycle_count);
    end

    // Load test data
    parameter IN_WORDS = TIME_SAMPLES * CIN1;
    parameter OUT_WORDS = TIME_SAMPLES * COUT_OUT;
    reg signed [N_DATA-1:0] in_chan_major [0:IN_WORDS-1];
    reg signed [N_DATA-1:0] out_chan_major [0:OUT_WORDS-1];
    reg signed [N_DATA-1:0] stim_time_major [0:IN_WORDS-1];
    reg signed [N_DATA-1:0] gold_time_major [0:OUT_WORDS-1];

    integer t, c, j, idx_tm, idx_cm;

    initial begin
        $readmemh("hdl_hex_data/test_input_01.hex", in_chan_major);
        $readmemh("hdl_hex_data/test_output_01.hex", out_chan_major);

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
    end

    // Main test
    integer in_idx;
    initial begin
        in_idx = 0;
        wait (rst_n);
        repeat (5) @(posedge clk);

        // Start inference and record start time
        start_cycle = cycle_count;
        $display("\n========================================");
        $display("FPGA Inference Performance Test");
        $display("========================================");
        $display("[START] Inference started at cycle %0d", start_cycle);

        start_inference <= 1;
        @(posedge clk);
        start_inference <= 0;

        // Feed input data
        while (in_idx < IN_WORDS) begin
            @(posedge clk);
            input_data <= stim_time_major[in_idx];
            input_data_valid <= 1;
            in_idx = in_idx + 1;
        end

        @(posedge clk);
        input_data_valid <= 0;
        $display("[INFO] Input feeding complete at cycle %0d", cycle_count);

        // Wait for completion
        wait (output_done);
        end_cycle = cycle_count;
        
        repeat (5) @(posedge clk);

        // Calculate performance metrics
        total_cycles = end_cycle - start_cycle;
        execution_time_ms = (total_cycles * 1.0) / (CLK_FREQ_MHZ * 1000.0);
        throughput_fps = 1000.0 / execution_time_ms;

        // Calculate error metrics
        calculate_error_metrics();

        // Print results
        print_results();

        $finish;
    end

    // Output comparison with error tracking
    integer out_idx;
    real error_val, gold_real, rtl_real;
    
    initial begin
        out_idx = 0;
        mismatches = 0;
        sum_squared_error = 0.0;
        sum_abs_error = 0.0;
        max_error = 0.0;
        total_outputs = 0;
    end

    always @(posedge clk) begin
        if (output_valid) begin
            if (out_idx < OUT_WORDS) begin
                // Convert to real values (Q1.22 format: divide by 2^22)
                rtl_real = $signed(output_result) / 4194304.0;  // 2^22
                gold_real = $signed(gold_time_major[out_idx]) / 4194304.0;
                
                // Calculate error
                error_val = rtl_real - gold_real;
                errors[out_idx] = error_val;
                
                // Accumulate error metrics
                sum_squared_error = sum_squared_error + (error_val * error_val);
                sum_abs_error = sum_abs_error + (error_val < 0 ? -error_val : error_val);
                
                if ((error_val < 0 ? -error_val : error_val) > max_error)
                    max_error = (error_val < 0 ? -error_val : error_val);
                
                total_outputs = total_outputs + 1;
                
                // Count mismatches (exact bit match)
                if (output_result !== gold_time_major[out_idx])
                    mismatches = mismatches + 1;
                
                // Print first/last few samples for verification
                if (out_idx < 5 || out_idx >= OUT_WORDS - 5) begin
                    $display("[%0t] Sample %0d: RTL=%h (%.6f) GOLD=%h (%.6f) Error=%.6f",
                             $time, out_idx, output_result, rtl_real, 
                             gold_time_major[out_idx], gold_real, error_val);
                end
            end
            out_idx = out_idx + 1;
        end
    end

    // Calculate final error metrics
    task calculate_error_metrics;
        begin
            if (total_outputs > 0) begin
                rmse = $sqrt(sum_squared_error / total_outputs);
                mae = sum_abs_error / total_outputs;
                max_abs_error = max_error;
            end else begin
                rmse = 0.0;
                mae = 0.0;
                max_abs_error = 0.0;
            end
        end
    endtask

    // Print comprehensive results
    task print_results;
        real relative_rmse;
        integer num_large_errors;
        real error_threshold;
        begin
            $display("\n========================================");
            $display("FPGA Performance Results");
            $display("========================================");
            $display("Clock Frequency:        %0d MHz", CLK_FREQ_MHZ);
            $display("Total Cycles:           %0d", total_cycles);
            $display("Execution Time:         %.3f ms", execution_time_ms);
            $display("Throughput:             %.2f inferences/sec", throughput_fps);
            $display("========================================");
            
            $display("\nError Analysis (Q1.22 Format)");
            $display("========================================");
            $display("Total Outputs:          %0d", total_outputs);
            $display("Exact Matches:          %0d", total_outputs - mismatches);
            $display("Mismatches (bit-exact): %0d (%.2f%%)", 
                     mismatches, (mismatches * 100.0) / total_outputs);
            $display("----------------------------------------");
            $display("RMSE:                   %.6f", rmse);
            $display("MAE (Mean Abs Error):   %.6f", mae);
            $display("Max Absolute Error:     %.6f", max_abs_error);
            
            // Calculate relative error
            if (sum_abs_error > 0) begin
                relative_rmse = (rmse / (sum_abs_error / total_outputs)) * 100.0;
                $display("Relative RMSE:          %.2f%%", relative_rmse);
            end
            
            // Count samples with large errors (>1% of full scale)
            error_threshold = 0.01;  // 1% of Q1.22 range (-2 to +2)
            num_large_errors = 0;
            for (integer i = 0; i < total_outputs; i = i + 1) begin
                if ((errors[i] < 0 ? -errors[i] : errors[i]) > error_threshold)
                    num_large_errors = num_large_errors + 1;
            end
            $display("Samples with >1%% error: %0d (%.2f%%)", 
                     num_large_errors, (num_large_errors * 100.0) / total_outputs);
            
            $display("========================================");
            
            // Pass/Fail criteria
            if (rmse < 0.01 && mae < 0.005) begin
                $display("\n*** TEST PASSED - Excellent accuracy ***");
                $display("RMSE < 1%% and MAE < 0.5%%");
            end else if (rmse < 0.05 && mae < 0.02) begin
                $display("\n*** TEST PASSED - Good accuracy ***");
                $display("RMSE < 5%% and MAE < 2%%");
            end else if (rmse < 0.1) begin
                $display("\n*** TEST PASSED - Acceptable accuracy ***");
                $display("RMSE < 10%%");
            end else begin
                $display("\n*** TEST FAILED - Poor accuracy ***");
                $display("RMSE > 10%%");
            end
            
            $display("========================================\n");
        end
    endtask

    // Layer timing tracker
    reg [63:0] layer_cycles [0:5];
    reg [63:0] layer_start_cycle;
    reg [2:0] prev_state;
    
    initial begin
        layer_start_cycle = 0;
        prev_state = 0;
        for (t = 0; t < 6; t = t + 1)
            layer_cycles[t] = 0;
    end

initial begin
    wait(rst_n);  // Wait for reset to release
    
    // Monitor for 500ms
    repeat(50) begin
        #10_000_000;  // Every 10ms
        $display("\n[%0t] === DEBUG STATUS ===", $time);
        $display("TOP: state=%0d (IDLE=0,NORM=1,L1=2,L2=3,L3=4,L4=5,OUT=6,DONE=7)", dut.state);
        $display("     progress=0x%h conv_start=%b", dut.progress, dut.conv_start);
        $display("CONV: state=%0d (IDLE=0,PREP=1,FILL=2,INIT=3,RUN=4,WAIT=5,DONE=6)", dut.u_conv.state);
        $display("      conv_done=%b conv_ready=%b", dut.conv_done, dut.conv_ready);
        
        if (dut.state == 4'd1) begin  // S_NORM_FILL
            $display("NORM_FILL: inbuf_wr_addr=%0d/%0d buffer_ready=%b norm_valid=%b",
                     dut.inbuf_wr_addr, dut.IN_BUF_WORDS, 
                     dut.input_buffer_ready, dut.norm_out_valid);
        end
        
        if (dut.state == 4'd2) begin  // S_LAYER1
            $display("LAYER1: conv_in_valid=%b inbuf_addr=%0d/%0d",
                     dut.conv_in_valid, dut.inbuf_wr_addr, dut.IN_BUF_WORDS);
        end
        
        if (dut.u_conv.state == 3'd2) begin  // S_FILL
            $display("  FILL: fill_t=%0d/%0d fill_c=%0d/%0d fill_done=%b",
                     dut.u_conv.fill_t, dut.u_conv.T_SAMPLES-1,
                     dut.u_conv.fill_c, dut.u_conv.CIN-1,
                     dut.u_conv.fill_done);
            $display("        input_valid=%b input_ready=%b",
                     dut.conv_in_valid, dut.conv_ready);
        end
        
        if (dut.u_conv.state == 3'd4) begin  // S_MAC_RUN
            $display("  MAC_RUN: t_out=%0d/%0d j_out=%0d/%0d mac_count=%0d target=%0d",
                     dut.u_conv.t_out, dut.u_conv.T_SAMPLES-1,
                     dut.u_conv.j_out, dut.u_conv.COUT-1,
                     dut.u_conv.mac_count, dut.u_conv.CIN * dut.u_conv.K);
        end
    end
    
end

// In testbench
initial begin
    integer norm_count = 0;
    forever begin
        @(posedge clk);
        if (dut.norm_out_valid) begin
            norm_count = norm_count + 1;
            if (norm_count < 10)
                $display("[%0t] Norm output %0d: %h", $time, norm_count, dut.norm_out_data);
        end
    end
end

    always @(posedge clk) begin
        if (dut.state != prev_state) begin
            if (prev_state != 0 && prev_state < 7)
                layer_cycles[prev_state] = cycle_count - layer_start_cycle;
            layer_start_cycle = cycle_count;
            prev_state = dut.state;
        end
    end

    // Timeout
    initial begin
        #2_000_000_000;
        $display("[TIMEOUT] Simulation exceeded 2ms");
        $finish;
    end

endmodule
