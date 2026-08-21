# Step 2: Dataset Generation

Runs the full transmitter → channel → receiver loop across varying speeds, SNR levels, and modulation orders to build a labeled dataset for training the CNN model.

## Files

- `channel.m` — wraps the CDL channel model for a given vehicle speed
- `reciever_main.m` — OFDM demodulation of the received waveform
- `extractFeaturesLabels.m` — converts demodulated symbols into `[feature, target]` training pairs
- `applyQuantization.m` — applies fixed-point quantization to generated samples
- `dataset_generation.m` — saves each generated sample to disk

## Pipeline

For each iteration (see `main.m` at the repo root):

1. **Transmitter** (`transmitter_main`) generates a random bitstream, encodes, modulates, and maps it to the OFDM resource grid, producing a transmit waveform.
2. **Channel** simulates a CDL NLOS urban channel: multipath fading, noise, Doppler effect, and frequency-selective delay.
3. **Receiver** (`reciever_main`) performs OFDM demodulation only (`nrOFDMDemodulator`), converting the noisy received signal into distorted subcarrier symbols using the same PDSCH configuration as the transmitter.
4. **Feature extraction** formats the result as `[feature, target]` pairs.

## Feature / Target Format

**Features** (input to the model):
- Real part of the received symbols
- Imaginary part of the received symbols
- Modulation order
- Vehicle speed (directly relates to the SNR of the symbol)

**Target** (what the model predicts):
- Real part of the transmitted symbol
- Imaginary part of the transmitted symbol

## Dataset Characteristics

- Vehicle speeds: 0–100 km/h
- Modulation orders: QPSK / 16QAM / 64QAM / 256QAM
- 1,000 combinations of speed, SNR, and modulation generated for the final training set
