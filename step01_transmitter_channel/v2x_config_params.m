function config = v2x_config_params()
    config.RunCount = 100;%Number of loop iterations
    config.Carrier_freq = 30e6; % 30 GHz carrier
    config.MinSpeed = 0; % Minimum Vehicle Speed in km/h
    config.MaxSpeed = 100; % Maximum Vehicle Speed in km/h
    config.BasebandBits = 14; % ADC/DAC resolution
    config.SubcarrierSpacing = 30; % in kHz
    config.SNR = 15; % dB
    config.SampleRate = 10e6; % in Hz 
    config.NumRBs = 52; % RBs (~10 MHz BW)
    config.Modulation = '16QAM';
    config.ErrorCorrectionRatio = 0.5; % % of bits which are useful, the remaining being for error correction 
    config.AntennaCount = 1; %SISO/MIMO
end
