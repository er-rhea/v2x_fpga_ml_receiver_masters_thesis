# ML-Enhanced FPGA Receiver for V2X Communication

A real-time receiver system for Vehicle-to-Everything (V2X) communication that replaces conventional DSP-based channel estimation, equalization, and demodulation with a hardware-accelerated 1D Convolutional Neural Network (CNN) deployed on an FPGA.

This project was developed as a Master's thesis at RMIT University, School of Engineering.

## Overview

Conventional DSP-based V2X receivers rely on static assumptions that struggle to keep up with fast-changing vehicular channel conditions. This project explores a machine-learning alternative: a 1D CNN trained to predict transmitted symbols directly from noisy received signals, then quantized and synthesized onto an FPGA for real-time, low-latency inference.

The system covers the full pipeline, from synthetic dataset generation through to a working hardware deployment:

```
Transmitter & Channel Simulation → Dataset Generation → ML Model (Training & Quantization) → HDL Design → HDL Simulation → FPGA Deployment
```

## System Configuration

| Parameter | Value | Notes |
|---|---|---|
| Vehicle speed | 0–100 km/h | Drives Doppler variation across the dataset |
| Carrier frequency | 30 GHz | mmWave band used by emerging NR-V2X / C-V2X systems |
| Baseband bits | 14 | ADC/DAC resolution |
| Sample rate | 10 Ms/sec | |
| Resource blocks | 52 | ~10 MHz bandwidth |
| Modulation schemes | QPSK / 16QAM / 64QAM / 256QAM | |
| SNR range | 5–50 dB | |

## Software & Hardware Used

**Software:** MATLAB R2025b (Communications, Deep Learning, Fixed-Point Designer, Parallel Computing, DSP, HDL Toolboxes), Intel Quartus Prime Lite Edition, QuestaSim

**Hardware:** Terasic DE10-Nano (Intel Cyclone V SoC, 5CSEBA6U23I7) — ~110k logic elements, 5MB M10K memory, 112 DSP blocks, dual-core ARM Cortex-A9

## The Model

A 5-layer 1D CNN was selected after comparing SVM, RNN, CNN, Transformer, and FCN architectures for accuracy, computational cost, and FPGA-compatibility. The CNN gave the best accuracy (95.67% in initial testing) while remaining small enough, and structurally simple enough (feedforward, streamable, no recurrence), to synthesize on the DE10-Nano.

Kernel sizes shrink through the network (9 → 7 → 5 → 3 → 1) — a pyramid scheme that captures coarse-to-fine temporal context while keeping the final layer trivial to stream sample-by-sample on hardware.

## Results

| Metric | Software (Floating Point) | Software (Fixed Point) | Hardware (FPGA) |
|---|---|---|---|
| RMSE | 0.09 | 0.10 | 0.119 |
| Latency | 5.6 µs (CPU) / 4.5 µs (GPU) | — | **3.126 µs** |
| Throughput | 178,176 (CPU) / 222,204 (GPU) | — | **319,264** |

The FPGA implementation achieves ultra-low latency with only a marginal accuracy trade-off versus the floating-point baseline, confirming the approach is viable for real-time V2X deployment.

## Repository Structure

| Folder | Contents |
|---|---|
| [`step01_transmitter_channel/`](step01_transmitter_channel) | MATLAB transmitter (5G NR PDSCH-based) and CDL channel model |
| [`step02_dataset_generation/`](step02_dataset_generation) | End-to-end simulation loop generating labeled training data |
| [`step03_ml_model/`](step03_ml_model) | CNN architecture, training, and fixed-point quantization |
| [`step04_hdl_design/`](step04_hdl_design) | Verilog implementation of the CNN receiver |
| [`step05_hdl_simulation/`](step05_hdl_simulation) | QuestaSim testbenches and verification |
| [`step06_hardware_implementation/`](step06_hardware_implementation) | Quartus synthesis, pin planning, and DE10-Nano deployment |
| [`results/`](results) | Final performance results and comparison plots |

Run `main.m` from the repository root (after adding the step folders to your MATLAB path) to execute the transmitter → channel → receiver → dataset generation loop.

## Notes on Reproducibility

System parameters (carrier frequency, SNR range, resource blocks, etc.) reflect this author's own research-based design choices rather than any externally supplied specification, and are shared here as-is.

## Future Work

- A more pipelined hardware design using multiple parallel MACs to reduce latency further
- Adapting the model for emerging 6G V2X standards (largely a parameter change)
- Larger FPGAs to reduce the need for aggressive quantization
- Real-world field testing beyond simulated channel conditions
- Online/continuous learning for the deployed model

## Acknowledgements

This project was completed under the supervision of Assoc. Prof. Ke Wang at RMIT University, with early guidance from an industry contact who introduced the research area. Full acknowledgements are in the accompanying thesis document.
