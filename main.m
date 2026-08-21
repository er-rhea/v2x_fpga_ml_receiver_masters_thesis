% Add all project subfolders to MATLAB's path
addpath(genpath('step01_transmitter_channel'));
addpath(genpath('step02_dataset_generation'));

% Initialize simulation parameters
simParams = v2x_config_params();

% Create output directory if it doesn't exist
if ~exist('step03_ml_model/dataset_x', 'dir')
    mkdir('step03_ml_model/dataset_x');
end


% Simulation loop
for frameIdx = 1:simParams.RunCount
    % Randomize vehicle speed
    speed = randi([simParams.MinSpeed, simParams.MaxSpeed]);

    % Generate transmit waveform and true symbols
    [txWaveform, txSymbols, carrier, pdsch] = transmitter_main(simParams);

    figure;
    plot(real(txWaveform(1:2000))); hold on;
    plot(imag(txWaveform(1:2000)));
    xlabel('Sample Index'); ylabel('Amplitude');
    title('Time-domain OFDM Waveform (Real and Imaginary Components)');
    legend('Real','Imag');

    % Channel model
    cdlChan = channel(simParams, speed);
    [rxWaveform, pathGains] = cdlChan(txWaveform);

    scatterplot(txSymbols); title('Transmitted 256-QAM Constellation');
    figure;
    scatterplot(rxWaveform(1:5000)); title('Received Signal After CDL-D Channel');


    % OFDM demodulation
    rxGrid = reciever_main(rxWaveform, carrier);

    % Feature and label extraction
    [features, labels] = extractFeaturesLabels(rxGrid, txSymbols, simParams, speed);

    % Save sample
    dataset_generation(features, labels, frameIdx);
end

