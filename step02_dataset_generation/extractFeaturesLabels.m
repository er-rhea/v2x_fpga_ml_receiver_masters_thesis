function [features, labels] = extractFeaturesLabels(rxGrid, txSymbols, simParams, speed)
    % Quantization and normalization
    rxGridQ = applyQuantization(rxGrid, simParams.BasebandBits);
    rxNorm = rxGridQ / max(abs(rxGridQ(:)));

    % Features: real/imaginary channels
    features.input = cat(3, real(rxNorm), imag(rxNorm));

    % Meta features
    features.speed = speed;
    features.SNR = simParams.SNR;

    % Modulation label (numeric)
    switch upper(simParams.Modulation)
        case 'QPSK',    modID = 0;
        case '16QAM',   modID = 1;
        case '64QAM',   modID = 2;
        case '256QAM',  modID = 3;
        otherwise,      error('Unknown modulation');
    end
    features.modulation = modID;

    % Labels = clean constellation symbols
    labels.symbols = txSymbols;
end
