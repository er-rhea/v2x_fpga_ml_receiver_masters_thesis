// =====================================================
// Fixed Convolution Core - Synchronous Block RAM
// =====================================================
module cnn_conv_core #(
    parameter integer N_DATA       = 24,
    parameter integer N_ACC        = 48,
    parameter integer ADDR_WIDTH_W = 15,
    parameter integer ADDR_WIDTH_B = 7,
    parameter integer T_SAMPLES    = 624,
    parameter integer MAX_CHANNELS = 64
)(
    input  wire clk,
    input  wire rst,

    // Control
    input  wire start_conv,
    output reg  conv_done,

    // Handshakes
    input  wire input_valid,
    output wire input_ready,
    output reg  output_valid,
    input  wire output_ready,

    // Data
    input  wire signed [N_DATA-1:0] input_data_bus,
    output reg  signed [N_DATA-1:0] output_data_bus,

    // Configuration
    input  wire [3:0]  cfg_kernel,
    input  wire [7:0]  cfg_cin,
    input  wire [7:0]  cfg_cout,
    input  wire        cfg_is_output_layer,
    input  wire [7:0]  cfg_shift_out,

    // ROM interface
    output reg [ADDR_WIDTH_W-1:0] w_addr_out,
    input  wire signed [N_DATA-1:0] weight_data_in,
    output reg [ADDR_WIDTH_B-1:0] b_addr_out,
    input  wire signed [N_DATA-1:0] bias_data_in
);

    // States
    localparam S_IDLE     = 3'd0;
    localparam S_PREP     = 3'd1;
    localparam S_FILL     = 3'd2;
    localparam S_MAC_INIT = 3'd3;
    localparam S_MAC_RUN  = 3'd4;
    localparam S_MAC_WAIT = 3'd5;
    localparam S_DONE     = 3'd6;

    reg [2:0] state, state_n;

    // Configuration
    reg [3:0]  K;
    reg [7:0]  CIN, COUT;
    reg        is_out_layer;
    reg [7:0]  shift_out;
    reg [15:0] cinxk_total;

    // Input buffer - Now with synchronous read
    localparam BUF_SIZE = T_SAMPLES * MAX_CHANNELS;
    localparam BUF_ADDR_W = $clog2(BUF_SIZE);
    
    reg signed [N_DATA-1:0] input_buf [0:BUF_SIZE-1];
    reg [BUF_ADDR_W-1:0] buf_wr_addr;
    reg [BUF_ADDR_W-1:0] buf_rd_addr;
    reg signed [N_DATA-1:0] buf_rd_data;
    reg buf_wr_en;
    
    // Synchronous RAM read/write
    always @(posedge clk) begin
        buf_rd_data <= input_buf[buf_rd_addr];
        if (buf_wr_en)
            input_buf[buf_wr_addr] <= input_data_bus;
    end
    
    // Fill counters
    reg [15:0] fill_t;
    reg [7:0]  fill_c;
    reg        fill_done;

    // Computation state
    reg [15:0] t_out;
    reg [7:0]  j_out;
    reg [7:0]  c_mac;
    reg [3:0]  k_mac;
    reg [15:0] mac_count;
    reg [3:0]  wait_cycles;
    
    // MAC control
    reg mac_ena, mac_sclr;
    wire signed [N_ACC-1:0] mac_result;
    
    // Pipeline registers (extended for RAM read delay)
    reg signed [N_DATA-1:0] weight_d1, weight_d2, weight_d3, weight_d4;
    reg signed [N_DATA-1:0] input_d1, input_d2, input_d3, input_d4;
    reg signed [N_DATA-1:0] bias_q;
    
    // Handshake
    assign input_ready = (state == S_FILL) && !fill_done;

    // FSM
    always @(posedge clk) begin
        if (rst) 
            state <= S_IDLE;
        else
            state <= state_n;
    end

    always @* begin
        state_n = state;
        case (state)
            S_IDLE:     if (start_conv) state_n = S_PREP;
            S_PREP:     state_n = S_FILL;
            S_FILL:     if (fill_done) state_n = S_MAC_INIT;
            S_MAC_INIT: state_n = S_MAC_RUN;
            S_MAC_RUN:  if (mac_count >= (CIN * K + 4)) state_n = S_MAC_WAIT;  // +4 for pipeline
            S_MAC_WAIT: if (wait_cycles >= 4'd6) begin
                            if (output_ready) begin
                                if (t_out == T_SAMPLES-1 && j_out == COUT-1)
                                    state_n = S_DONE;
                                else
                                    state_n = S_MAC_INIT;
                            end
                        end
            S_DONE:     state_n = S_IDLE;
            default:    state_n = S_IDLE;
        endcase
    end

    // Datapath
    reg [15:0] input_time_idx;
    reg [BUF_ADDR_W-1:0] calc_addr;
    
    always @(posedge clk) begin
        if (rst) begin
            {K, CIN, COUT, is_out_layer, shift_out, cinxk_total} <= 0;
            {fill_t, fill_c, fill_done} <= 0;
            {t_out, j_out, c_mac, k_mac, mac_count, wait_cycles} <= 0;
            {mac_ena, mac_sclr} <= 0;
            {weight_d1, weight_d2, weight_d3, weight_d4} <= 0;
            {input_d1, input_d2, input_d3, input_d4, bias_q} <= 0;
            {output_valid, output_data_bus, conv_done} <= 0;
            {w_addr_out, b_addr_out} <= 0;
            {buf_wr_addr, buf_rd_addr, buf_wr_en} <= 0;
                    
        end else begin
            // Defaults
            output_valid <= 0;
            mac_sclr <= 0;
            mac_ena <= 0;
            conv_done <= 0;
            buf_wr_en <= 0;
            
            // 4-stage pipeline (added 1 stage for RAM read delay)
            weight_d1 <= weight_data_in;
            weight_d2 <= weight_d1;
            weight_d3 <= weight_d2;
            weight_d4 <= weight_d3;
            input_d1 <= buf_rd_data;
            input_d2 <= input_d1;
            input_d3 <= input_d2;
            input_d4 <= input_d3;
            
            case (state)
                S_IDLE: begin
                    fill_t <= 0;
                    fill_c <= 0;
                    fill_done <= 0;
                    t_out <= 0;
                    j_out <= 0;
                    conv_done <= 0;
                    buf_wr_addr <= 0;
                    buf_rd_addr <= 0;
                end

                S_PREP: begin
                    K <= (cfg_kernel == 0) ? 4'd1 : cfg_kernel;
                    CIN <= (cfg_cin == 0) ? 8'd1 : cfg_cin;
                    COUT <= (cfg_cout == 0) ? 8'd1 : cfg_cout;
                    is_out_layer <= cfg_is_output_layer;
                    shift_out <= cfg_shift_out;
                    cinxk_total <= cfg_cin * cfg_kernel;
                    
                    fill_t <= 0;
                    fill_c <= 0;
                    fill_done <= 0;
                    t_out <= 0;
                    j_out <= 0;
                    buf_wr_addr <= 0;
                    buf_rd_addr <= 0;
                end

                S_FILL: begin
                    // Fill input buffer in [time][channel] order
                    if (input_valid && input_ready) begin
                        buf_wr_en <= 1;
                        buf_wr_addr <= fill_t * MAX_CHANNELS + fill_c;
                        
                        if (fill_c == CIN - 1) begin
                            fill_c <= 0;
                            if (fill_t == T_SAMPLES - 1) begin
                                fill_done <= 1;
                            end else begin
                                fill_t <= fill_t + 1;
                            end
                        end else begin
                            fill_c <= fill_c + 1;
                        end
                    end
                end

                S_MAC_INIT: begin
                    // Initialize for new output
                    c_mac <= 0;
                    k_mac <= 0;
                    mac_count <= 0;
                    wait_cycles <= 0;
                    mac_sclr <= 1;  // Clear accumulator
                    
                    // Pre-fetch bias
                    b_addr_out <= j_out[ADDR_WIDTH_B-1:0];
                end

                S_MAC_RUN: begin
                    // Calculate weight address for NEXT cycle
                    w_addr_out <= ((j_out * cinxk_total + c_mac * K + k_mac) & 
                                  ((1 << ADDR_WIDTH_W) - 1));
                    
                    // Calculate input buffer address
                    input_time_idx = t_out + k_mac;
                    
                    // Read from buffer (data arrives 1 cycle later)
                    if (input_time_idx < T_SAMPLES && c_mac < CIN)
                        calc_addr = input_time_idx * MAX_CHANNELS + c_mac;
                    else
                        calc_addr = 0;
                    
                    buf_rd_addr <= calc_addr;
                    
                    // Enable MAC (multiplies d4 values from 4 cycles ago)
                    if (mac_count >= 4)  // Start after pipeline fills
                        mac_ena <= 1;
                    
                    mac_count <= mac_count + 1;
                    
                    // Advance counters
                    if (k_mac == K - 1) begin
                        k_mac <= 0;
                        c_mac <= c_mac + 1;
                    end else begin
                        k_mac <= k_mac + 1;
                    end
                end

                S_MAC_WAIT: begin
                    // Wait for pipeline to flush
                    wait_cycles <= wait_cycles + 1;
                    
                    if (wait_cycles == 4'd2) begin
                        // Latch bias (was fetched in INIT)
                        bias_q <= bias_data_in;
                    end
                    
                    if (wait_cycles == 4'd6) begin
                        // MAC result ready, emit output
                        output_data_bus <= postproc(mac_result, bias_q, shift_out, is_out_layer);
                        output_valid <= 1;
                        
                        if (output_ready) begin
                            // Move to next output
                            if (j_out == COUT - 1) begin
                                j_out <= 0;
                                t_out <= t_out + 1;
                            end else begin
                                j_out <= j_out + 1;
                            end
                        end
                    end
                end

                S_DONE: begin
                    conv_done <= 1;
                end
            endcase
        end
    end

    // Post-processing functions (unchanged)
    function automatic signed [N_DATA-1:0] sat24(input signed [N_ACC-1:0] x);
        reg signed [N_DATA-1:0] maxv, minv;
        begin
            maxv = {1'b0, {(N_DATA-1){1'b1}}};
            minv = {1'b1, {(N_DATA-1){1'b0}}};
            if (x > $signed({{(N_ACC-N_DATA){1'b0}}, maxv}))
                sat24 = maxv;
            else if (x < $signed({{(N_ACC-N_DATA){1'b1}}, minv}))
                sat24 = minv;
            else
                sat24 = x[N_DATA-1:0];
        end
    endfunction

    function automatic signed [N_DATA-1:0] postproc(
        input signed [N_ACC-1:0] acc_in,
        input signed [N_DATA-1:0] bias_in,
        input [7:0] shift_r,
        input is_last
    );
        reg signed [N_ACC-1:0] acc_bias, acc_shift, bias_scaled;
        reg signed [N_DATA-1:0] y_sat;
        begin
            if (is_last) begin
                // OUTPUT LAYER (Layer 5)
                acc_shift = (shift_r == 0) ? acc_in : (acc_in >>> shift_r);
                acc_bias = acc_shift + {{(N_ACC-N_DATA){bias_in[N_DATA-1]}}, bias_in};
                y_sat = sat24(acc_bias);
                postproc = y_sat;
                
            end else begin
                // HIDDEN LAYERS (Layers 1-4)
                bias_scaled = {{(N_ACC-N_DATA){bias_in[N_DATA-1]}}, bias_in} << 20;
                acc_bias = acc_in + bias_scaled;
                acc_shift = (shift_r == 0) ? acc_bias : (acc_bias >>> shift_r);
                y_sat = sat24(acc_shift);
                postproc = y_sat[N_DATA-1] ? 24'b0 : y_sat;
            end
        end
    endfunction

    // MAC instance
    mac_24bits u_mac (
        .clock0(clk),
        .ena0(mac_ena),
        .sclr0(mac_sclr),
        .dataa_0(input_d4),   // 4-cycle delayed input
        .datab_0(weight_d4),  // 4-cycle delayed weight
        .result(mac_result)
    );

endmodule