# 20-bit Fixed-Point Quantization — Experiment (Superseded)

This document records an early fixed-point quantization attempt that was tested and ultimately **rejected** in favor of the 24-bit Q3.20 scheme used in the final design (see `README.md` in this folder). It's kept here for transparency about the design process — 16-bit and 20-bit quantization both produced unacceptable accuracy loss, which is what motivated the move to 24-bit.

**Target:** Cyclone V (27×27 DSP blocks)
**Word length:** N = 20 bits
**Accumulator:** 40 bits

| Layer | Weight Format | Bias Format | Activation Format |
|---|---|---|---|
| conv1 | Q1.18 | Q1.18 | Q3.16 |
| conv2 | Q1.18 | Q1.18 | Q3.16 |
| conv3 | Q1.18 | Q1.18 | Q3.16 |
| conv4 | Q1.18 | Q1.18 | Q3.16 |
| conv_out | Q1.18 | Q1.18 | Q1.18 |

**Observed performance at this configuration:**
- NMSE: 4.8365e-01
- EVM: 69.55%
- Degradation: 12.65 dB

These figures reflect an early, non-final iteration and should not be compared directly against the final hardware results reported in the main results table — see `results/README.md` for the final, validated performance.
