# SDC Timing Constraints for CNN_FPGA

# 1. Define Primary Clock
# TARGET FREQUENCY: 50 MHz (Period 20.0 ns)
create_clock -name clk_sys -period 20.0 [get_ports clk_in]

# 2. Set Clock Uncertainty
# Reduced uncertainty for a more realistic timing closure target (was 10.0/5.0 ns)
set_clock_uncertainty -setup -from [get_clocks clk_sys] -to [get_clocks clk_sys] 1.0
set_clock_uncertainty -hold -from [get_clocks clk_sys] -to [get_clocks clk_sys] 0.5

# 3. Set Input Delays (Grouped ports for cleaner constraints)
# MAPPED TO cnn_top PORTS: 'input_data' and 'start_inference'
set_input_delay -clock clk_sys -max 10.0 [get_ports {input_data start_inference}]
set_input_delay -clock clk_sys -min 2.0 [get_ports {input_data start_inference}]

# 4. Set Output Delays (Grouped ports)
# MAPPED TO cnn_top PORTS: 'output_result' and 'output_done'
set_output_delay -clock clk_sys -max 10.0 [get_ports {output_result output_done}]
set_output_delay -clock clk_sys -min 2.0 [get_ports {output_result output_done}]

# 5. Set False Path on Asynchronous Reset
# The top-level reset port is named 'reset_in'
set_false_path -from [get_ports reset_in]
