module cnn_ram_mux #(
    parameter integer N_DATA       = 24,
    parameter integer MAX_ADDR_W   = 15,
    parameter integer MAX_ADDR_B   = 7
)(
    input  wire              clk,
    input  wire [2:0]        layer_select,

    // Addresses coming from the conv core
    input  wire [MAX_ADDR_W-1:0] w_addr_in,
    input  wire [MAX_ADDR_B-1:0] b_addr_in,

    // Selected data to conv core
    output reg  signed [N_DATA-1:0] w_data_out,
    output reg  signed [N_DATA-1:0] b_data_out
);

    // ROM sizes (actual number of entries)
    localparam L1_W_SIZE = 8352;   // 29 * 9 * 32
    localparam L2_W_SIZE = 14336;  // 32 * 7 * 64
    localparam L3_W_SIZE = 20480;  // 64 * 5 * 64
    localparam L4_W_SIZE = 6144;   // 64 * 3 * 32
    localparam L5_W_SIZE = 64;     // 32 * 1 * 2

    localparam L1_B_SIZE = 32;
    localparam L2_B_SIZE = 64;
    localparam L3_B_SIZE = 64;
    localparam L4_B_SIZE = 32;
    localparam L5_B_SIZE = 2;

    // Wires from each ROM instance
    wire signed [N_DATA-1:0] w1_q, w2_q, w3_q, w4_q, w5_q;
    wire signed [N_DATA-1:0] b1_q, b2_q, b3_q, b4_q, b5_q;

    // Bounded addresses with modulo operation to prevent out-of-bounds
    wire [13:0] w_addr_l1 = (w_addr_in % L1_W_SIZE);  // 14 bits needed
    wire [13:0] w_addr_l2 = (w_addr_in % L2_W_SIZE);  // 14 bits needed
    wire [14:0] w_addr_l3 = (w_addr_in % L3_W_SIZE);  // 15 bits needed
    wire [12:0] w_addr_l4 = (w_addr_in % L4_W_SIZE);  // 13 bits sufficient (6144 < 8192)
    wire [5:0]  w_addr_l5 = (w_addr_in % L5_W_SIZE);  // 6 bits sufficient (64)

    wire [5:0]  b_addr_l1 = (b_addr_in % L1_B_SIZE);
    wire [5:0]  b_addr_l2 = (b_addr_in % L2_B_SIZE);
    wire [5:0]  b_addr_l3 = (b_addr_in % L3_B_SIZE);
    wire [4:0]  b_addr_l4 = (b_addr_in % L4_B_SIZE);  // 5 bits sufficient (32)
    wire [0:0]  b_addr_l5 = (b_addr_in % L5_B_SIZE);

    // Instantiate weight ROMs
    conv1_w u_w1 (.clock(clk), .address(w_addr_l1), .q(w1_q));
    conv2_w u_w2 (.clock(clk), .address(w_addr_l2), .q(w2_q));
    conv3_w u_w3 (.clock(clk), .address(w_addr_l3), .q(w3_q));
    conv4_w u_w4 (.clock(clk), .address(w_addr_l4), .q(w4_q));
    conv_out_w u_w5 (.clock(clk), .address(w_addr_l5), .q(w5_q));

    // Instantiate bias ROMs
    conv1_b u_b1 (.clock(clk), .address(b_addr_l1), .q(b1_q));
    conv2_b u_b2 (.clock(clk), .address(b_addr_l2), .q(b2_q));
    conv3_b u_b3 (.clock(clk), .address(b_addr_l3), .q(b3_q));
    conv4_b u_b4 (.clock(clk), .address(b_addr_l4), .q(b4_q));
    conv_out_b u_b5 (.clock(clk), .address(b_addr_l5), .q(b5_q));

    // Registered mux outputs
    always @(posedge clk) begin
        case (layer_select)
            3'd1: begin w_data_out <= w1_q; b_data_out <= b1_q; end
            3'd2: begin w_data_out <= w2_q; b_data_out <= b2_q; end
            3'd3: begin w_data_out <= w3_q; b_data_out <= b3_q; end
            3'd4: begin w_data_out <= w4_q; b_data_out <= b4_q; end
            3'd5: begin w_data_out <= w5_q; b_data_out <= b5_q; end
            default: begin w_data_out <= 0; b_data_out <= 0; end
        endcase
    end

endmodule