// ======================================================================
// File: cnn_top.v (FIXED with Block RAM inference)
// Description: CNN Controller with proper RAM inference
// ======================================================================

module cnn_top (
    input  wire                   clk_in,
    input  wire                   rst_n,

    input  wire                   start_inference,
    input  wire signed [23:0]     input_data,
    input  wire                   input_data_valid,

    output reg  signed [23:0]     output_result,
    output reg                    output_valid,
    output reg                    output_done,
    output reg  [7:0]             progress
);

    // =============================================================
    // Parameters
    // =============================================================
    localparam integer N_DATA       = 24;
    localparam integer TIME_SAMPLES = 624;

    // Layer parameters
    localparam integer KERNEL_1 = 9,  CIN_1 = 29, COUT_1 = 32;
    localparam integer KERNEL_2 = 7,  CIN_2 = 32, COUT_2 = 64;
    localparam integer KERNEL_3 = 5,  CIN_3 = 64, COUT_3 = 64;
    localparam integer KERNEL_4 = 3,  CIN_4 = 64, COUT_4 = 32;
    localparam integer KERNEL_OUT = 1, CIN_OUT = 32, COUT_OUT = 2;

    // =============================================================
    // Input Buffer (Synchronous RAM for synthesis)
    // =============================================================
    localparam integer IN_BUF_WORDS = TIME_SAMPLES * CIN_1;
    localparam integer IN_ADDR_W    = $clog2(IN_BUF_WORDS);

    reg signed [N_DATA-1:0] input_buffer [0:IN_BUF_WORDS-1];
    reg [IN_ADDR_W-1:0] inbuf_wr_addr;
    reg [IN_ADDR_W-1:0] inbuf_rd_addr;
    reg [IN_ADDR_W:0]   inbuf_wr_count;
    reg                 input_buffer_ready;
    reg signed [N_DATA-1:0] inbuf_rd_data;

    // Synchronous read for input buffer
    always @(posedge clk_in) begin
        inbuf_rd_data <= input_buffer[inbuf_rd_addr];
        if (norm_out_valid)
            input_buffer[inbuf_wr_addr] <= norm_out_data;
    end

    // =============================================================
    // Inter-layer Buffer (Synchronous RAM)
    // =============================================================
    localparam integer LAYER_BUF_WORDS = TIME_SAMPLES * 64;
    localparam integer LAYER_ADDR_W = $clog2(LAYER_BUF_WORDS);
    
    reg signed [N_DATA-1:0] layer_buffer [0:LAYER_BUF_WORDS-1];
    reg [LAYER_ADDR_W-1:0] layer_buf_wr_addr;
    reg [LAYER_ADDR_W-1:0] layer_buf_rd_addr;
    reg signed [N_DATA-1:0] layer_buf_rd_data;
    reg layer_buf_wr_en;

    // Synchronous read/write for layer buffer
    always @(posedge clk_in) begin
        layer_buf_rd_data <= layer_buffer[layer_buf_rd_addr];
        if (layer_buf_wr_en)
            layer_buffer[layer_buf_wr_addr] <= conv_out_data;
    end

    // =============================================================
    // FSM States
    // =============================================================
    localparam [3:0]
        S_IDLE      = 4'd0,
        S_NORM_FILL = 4'd1,
        S_LAYER1    = 4'd2,
        S_LAYER2    = 4'd3,
        S_LAYER3    = 4'd4,
        S_LAYER4    = 4'd5,
        S_LAYER_OUT = 4'd6,
        S_DONE      = 4'd7;

    reg [3:0] state, state_n, state_d;
    wire rst = ~rst_n;

    // =============================================================
    // Normalization
    // =============================================================
    wire signed [N_DATA-1:0] norm_out_data;
    wire norm_out_valid;

    // =============================================================
    // Convolution Core Interface
    // =============================================================
    reg  conv_start;
    wire conv_done;
    reg conv_done_q;
    wire conv_done_rise = conv_done & ~conv_done_q;
    wire conv_ready;
    reg  [3:0]  cfg_kernel;
    reg  [7:0]  cfg_cin, cfg_cout;
    reg         cfg_is_output_layer;
    reg  [7:0]  cfg_shift_out;
    reg  signed [23:0] conv_in_data;
    reg         conv_in_valid;
    wire signed [23:0] conv_out_data;
    wire        conv_out_valid;
    reg         conv_out_ready;

    // Weight/Bias ROMs
    wire [14:0] w_addr;
    wire [6:0]  b_addr;
    reg  [2:0]  layer_select;
    wire signed [23:0] weight_data, bias_data;

    // Pipeline registers for RAM read delay
    reg conv_in_valid_d1, conv_in_valid_d2;
    reg signed [23:0] conv_in_data_d1, conv_in_data_d2;

    // =============================================================
    // FSM Next-State Logic
    // =============================================================
    always @* begin
        state_n = state;
        case (state)
            S_IDLE:      if (start_inference) state_n = S_NORM_FILL;
            S_NORM_FILL: if (input_buffer_ready) state_n = S_LAYER1;
            S_LAYER1:    if (conv_done_rise) state_n = S_LAYER2;
            S_LAYER2:    if (conv_done_rise) state_n = S_LAYER3;
            S_LAYER3:    if (conv_done_rise) state_n = S_LAYER4;
            S_LAYER4:    if (conv_done_rise) state_n = S_LAYER_OUT;
            S_LAYER_OUT: if (conv_done_rise) state_n = S_DONE;
            S_DONE:      state_n = S_IDLE;
            default:     state_n = S_IDLE;
        endcase
    end

    // =============================================================
    // FSM Sequential Logic
    // =============================================================
    always @(posedge clk_in) begin
        if (rst) begin
            state <= S_IDLE;
            state_d <= S_IDLE;
            progress <= 8'h00;
            conv_start <= 1'b0;
            conv_in_valid <= 1'b0;
            conv_out_ready <= 1'b1;
            layer_select <= 3'd0;
            output_result <= 0;
            output_valid <= 1'b0;
            output_done <= 1'b0;
            {cfg_kernel, cfg_cin, cfg_cout, cfg_is_output_layer, cfg_shift_out} <= 0;
            input_buffer_ready <= 1'b0;
            inbuf_wr_addr <= 0;
            inbuf_rd_addr <= 0;
            inbuf_wr_count <= 0;
            conv_done_q <= 1'b0;
            layer_buf_wr_addr <= 0;
            layer_buf_rd_addr <= 0;
            layer_buf_wr_en <= 0;
            conv_in_data <= 0;
            conv_in_valid_d1 <= 0;
            conv_in_valid_d2 <= 0;
            conv_in_data_d1 <= 0;
            conv_in_data_d2 <= 0;
        end else begin
            state_d <= state;
            state <= state_n;

            // Defaults
            conv_start <= 1'b0;
            conv_in_valid <= 1'b0;
            output_valid <= 1'b0;
            output_done <= 1'b0;
            conv_done_q <= conv_done;
            layer_buf_wr_en <= 0;

            // Pipeline for RAM read delays
            conv_in_valid_d1 <= 0;
            conv_in_valid_d2 <= conv_in_valid_d1;
            conv_in_data_d1 <= conv_in_data;
            conv_in_data_d2 <= conv_in_data_d1;

            case (state)
            // -------------------------------------------------
            // IDLE
            // -------------------------------------------------
            S_IDLE: begin
                progress <= 8'h00;
                if (start_inference) begin
                    inbuf_wr_addr <= 0;
                    inbuf_rd_addr <= 0;
                    inbuf_wr_count <= 0;
                    input_buffer_ready <= 1'b0;
                end
            end

            // -------------------------------------------------
            // NORMALIZATION - Fill input buffer
            // -------------------------------------------------
            S_NORM_FILL: begin
                progress <= 8'h01;
                if (norm_out_valid) begin
                    // Write happens in always block above
                    inbuf_wr_addr  <= inbuf_wr_addr + 1'b1;
                    inbuf_wr_count <= inbuf_wr_count + 1'b1;
                    if (inbuf_wr_count == IN_BUF_WORDS - 1) begin
                        input_buffer_ready <= 1'b1;
                    end
                end
            end

            // ------------------- LAYER 1 --------------------
            S_LAYER1: begin
                progress <= 8'h10;
                if (state_d != state) begin
                    layer_select <= 3'd1;
                    cfg_kernel <= KERNEL_1;
                    cfg_cin <= CIN_1;
                    cfg_cout <= COUT_1;
                    cfg_is_output_layer <= 1'b0;
                    cfg_shift_out <= 8'd20;
                    conv_start <= 1'b1;
                    inbuf_rd_addr <= 0;
                    layer_buf_wr_addr <= 0;
                end else if (conv_ready) begin
                    if (inbuf_rd_addr < IN_BUF_WORDS) begin
                        inbuf_rd_addr <= inbuf_rd_addr + 1'b1;
                        conv_in_valid_d1 <= 1'b1;
                        // Data arrives 1 cycle later
                    end
                end
                // Send data from pipeline
                if (conv_in_valid_d2) begin
                    conv_in_data <= inbuf_rd_data;
                    conv_in_valid <= 1'b1;
                end
                // Capture outputs
                if (conv_out_valid) begin
                    layer_buf_wr_en <= 1'b1;
                    layer_buf_wr_addr <= layer_buf_wr_addr + 1'b1;
                end
            end

            // ------------------- LAYER 2 --------------------
            S_LAYER2: begin
                progress <= 8'h20;
                if (state_d != state) begin
                    layer_select <= 3'd2;
                    cfg_kernel <= KERNEL_2;
                    cfg_cin <= COUT_1;
                    cfg_cout <= COUT_2;
                    cfg_is_output_layer <= 1'b0;
                    cfg_shift_out <= 8'd20;
                    conv_start <= 1'b1;
                    layer_buf_rd_addr <= 0;
                    layer_buf_wr_addr <= 0;
                end else if (!conv_ready) begin
                    conv_start <= 1'b1;
                end else if (conv_ready && layer_buf_rd_addr < (TIME_SAMPLES * COUT_1)) begin
                    layer_buf_rd_addr <= layer_buf_rd_addr + 1'b1;
                    conv_in_valid_d1 <= 1'b1;
                end
                // Send data from pipeline
                if (conv_in_valid_d2) begin
                    conv_in_data <= layer_buf_rd_data;
                    conv_in_valid <= 1'b1;
                end
                // Capture outputs
                if (conv_out_valid) begin
                    layer_buf_wr_en <= 1'b1;
                    layer_buf_wr_addr <= layer_buf_wr_addr + 1'b1;
                end
            end

            // ------------------- LAYER 3 --------------------
            S_LAYER3: begin
                progress <= 8'h30;
                if (state_d != state) begin
                    layer_select <= 3'd3;
                    cfg_kernel <= KERNEL_3;
                    cfg_cin <= COUT_2;
                    cfg_cout <= COUT_3;
                    cfg_is_output_layer <= 1'b0;
                    cfg_shift_out <= 8'd20;
                    conv_start <= 1'b1;
                    layer_buf_rd_addr <= 0;
                    layer_buf_wr_addr <= 0;
                end else if (!conv_ready) begin
                    conv_start <= 1'b1;
                end else if (conv_ready && layer_buf_rd_addr < (TIME_SAMPLES * COUT_2)) begin
                    layer_buf_rd_addr <= layer_buf_rd_addr + 1'b1;
                    conv_in_valid_d1 <= 1'b1;
                end
                // Send data from pipeline
                if (conv_in_valid_d2) begin
                    conv_in_data <= layer_buf_rd_data;
                    conv_in_valid <= 1'b1;
                end
                // Capture outputs
                if (conv_out_valid) begin
                    layer_buf_wr_en <= 1'b1;
                    layer_buf_wr_addr <= layer_buf_wr_addr + 1'b1;
                end
            end

            // ------------------- LAYER 4 --------------------
            S_LAYER4: begin
                progress <= 8'h40;
                if (state_d != state) begin
                    layer_select <= 3'd4;
                    cfg_kernel <= KERNEL_4;
                    cfg_cin <= COUT_3;
                    cfg_cout <= COUT_4;
                    cfg_is_output_layer <= 1'b0;
                    cfg_shift_out <= 8'd20;
                    conv_start <= 1'b1;
                    layer_buf_rd_addr <= 0;
                    layer_buf_wr_addr <= 0;
                end else if (!conv_ready) begin
                    conv_start <= 1'b1;
                end else if (conv_ready && layer_buf_rd_addr < (TIME_SAMPLES * COUT_3)) begin
                    layer_buf_rd_addr <= layer_buf_rd_addr + 1'b1;
                    conv_in_valid_d1 <= 1'b1;
                end
                // Send data from pipeline
                if (conv_in_valid_d2) begin
                    conv_in_data <= layer_buf_rd_data;
                    conv_in_valid <= 1'b1;
                end
                // Capture outputs
                if (conv_out_valid) begin
                    layer_buf_wr_en <= 1'b1;
                    layer_buf_wr_addr <= layer_buf_wr_addr + 1'b1;
                end
            end

            // ------------------- OUTPUT LAYER --------------------
            S_LAYER_OUT: begin
                progress <= 8'h50;
                if (state_d != state) begin
                    layer_select <= 3'd5;
                    cfg_kernel <= KERNEL_OUT;
                    cfg_cin <= COUT_4;
                    cfg_cout <= COUT_OUT;
                    cfg_is_output_layer <= 1'b1;
                    cfg_shift_out <= 8'd20;
                    conv_start <= 1'b1;
                    layer_buf_rd_addr <= 0;
                end else if (!conv_ready) begin
                    conv_start <= 1'b1;
                end else if (conv_ready && layer_buf_rd_addr < (TIME_SAMPLES * COUT_4)) begin
                    layer_buf_rd_addr <= layer_buf_rd_addr + 1'b1;
                    conv_in_valid_d1 <= 1'b1;
                end
                // Send data from pipeline
                if (conv_in_valid_d2) begin
                    conv_in_data <= layer_buf_rd_data;
                    conv_in_valid <= 1'b1;
                end
                // Output final results
                if (conv_out_valid) begin
                    output_result <= conv_out_data;
                    output_valid <= 1'b1;
                end
            end

            // ------------------- DONE --------------------
            S_DONE: begin
                progress <= 8'hFF;
                output_done <= 1'b1;
            end

            endcase
        end
    end

    // =============================================================
    // Normalization Module
    // =============================================================
    norm_module #(
        .N_DATA(N_DATA),
        .NUM_FEAT(CIN_1)
    ) u_norm (
        .clk(clk_in),
        .rst(rst),
        .input_data(input_data),
        .data_valid(input_data_valid),
        .output_data(norm_out_data),
        .output_valid(norm_out_valid)
    );

    // =============================================================
    // Convolution Core
    // =============================================================
    cnn_conv_core #(
        .N_DATA(N_DATA),
        .N_ACC(48),
        .ADDR_WIDTH_W(15),
        .ADDR_WIDTH_B(7),
        .T_SAMPLES(TIME_SAMPLES)
    ) u_conv (
        .clk(clk_in),
        .rst(rst),
        .start_conv(conv_start),
        .conv_done(conv_done),
        .input_valid(conv_in_valid),
        .input_ready(conv_ready),
        .output_valid(conv_out_valid),
        .output_ready(conv_out_ready),
        .input_data_bus(conv_in_data),
        .output_data_bus(conv_out_data),
        .cfg_kernel(cfg_kernel),
        .cfg_cin(cfg_cin),
        .cfg_cout(cfg_cout),
        .cfg_is_output_layer(cfg_is_output_layer),
        .cfg_shift_out(cfg_shift_out),
        .w_addr_out(w_addr),
        .weight_data_in(weight_data),
        .b_addr_out(b_addr),
        .bias_data_in(bias_data)
    );

    // =============================================================
    // Weight/Bias ROM Mux
    // =============================================================
    cnn_ram_mux #(
        .N_DATA(N_DATA),
        .MAX_ADDR_W(15),
        .MAX_ADDR_B(7)
    ) u_ram (
        .clk(clk_in),
        .layer_select(layer_select),
        .w_addr_in(w_addr),
        .b_addr_in(b_addr),
        .w_data_out(weight_data),
        .b_data_out(bias_data)
    );

endmodule