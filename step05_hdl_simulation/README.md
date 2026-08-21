# Step 5: HDL Simulation & Testing

Verification of the HDL design (`step04_hdl_design`) against the quantized software model, using QuestaSim.

## Files

- `tb.sv`, `tb_new.sv` — SystemVerilog testbenches
- `CNN_FPGA.mpf`, `CNN_FPGA_test.mpf` — ModelSim/QuestaSim project files

## Testbench Design

The testbench streams quantized input samples into the `cnn_top` module and compares the output against pre-computed "gold" reference values from the software model.

**Characteristics:**
- Timescale: 1ns/1ps
- Clock: 50 MHz (20ns period)
- Cycle counter for throughput measurement
- Control signals: reset, `start_inference`, `input_data_valid`
- Input/output hex files read via `$readmemh`
- Simulation time measurement for latency analysis
- Output comparison against gold values: RMSE, MSE, and maximum error calculations
- Timeout and debug print statements

## Purpose

This end-to-end simulation validates that the Verilog implementation matches the behavior of the trained, quantized (24-bit, Q3.20) model before committing to hardware synthesis — catching functional bugs cheaply in simulation rather than on the board. Results from this stage fed directly into the resource/timing decisions made in `step06_hardware_implementation`.
