function [txWaveform, pdschSymbols, carrier_config, pdsch_config] = transmitter_main(simParams)

    % Carrier configuration
    carrier_config = nrCarrierConfig;
    carrier_config.SubcarrierSpacing = simParams.SubcarrierSpacing;
    carrier_config.NSizeGrid = simParams.NumRBs;

    % PDSCH configuration
    pdsch_config = nrPDSCHConfig;
    pdsch_config.Modulation = simParams.Modulation;
    pdsch_config.NumLayers = simParams.AntennaCount;
    pdsch_config.PRBSet = 0:carrier_config.NSizeGrid-1;

    % Determine modulation order Qm
    switch pdsch_config.Modulation
        case 'QPSK',    modOrder = 2;
        case '16QAM',   modOrder = 4;
        case '64QAM',   modOrder = 6;
        case '256QAM',  modOrder = 8;
        otherwise, error('Unsupported modulation scheme.');
    end

    % Transport block
    numRB = carrier_config.NSizeGrid;
    numSymbols = pdsch_config.SymbolAllocation(2);  
    numSubcarriers = 12;
    trBlkSize = floor(numRB * numSubcarriers * numSymbols * modOrder * simParams.ErrorCorrectionRatio);

    txBits = randi([0 1], trBlkSize, 1, 'int8');

    % DL-SCH encoder
    dlsch = nrDLSCH;
    dlsch.TargetCodeRate = simParams.ErrorCorrectionRatio;
    setTransportBlock(dlsch, txBits);

    pdschIndices = nrPDSCHIndices(carrier_config, pdsch_config);
    NumOutBits = length(pdschIndices) * modOrder;
    redundancy = 0;  

    % Encode and modulate
    codedBits = dlsch(pdsch_config.Modulation, pdsch_config.NumLayers, NumOutBits, redundancy);
    pdschSymbols = nrPDSCH(carrier_config, pdsch_config, codedBits);   % <<== labels

    % DM-RS
    dmrsSymbols = nrPDSCHDMRS(carrier_config, pdsch_config);
    dmrsIndices = nrPDSCHDMRSIndices(carrier_config, pdsch_config);

    % Resource grid
    txGrid = nrResourceGrid(carrier_config, pdsch_config.NumLayers);
    txGrid(pdschIndices) = pdschSymbols;
    txGrid(dmrsIndices) = dmrsSymbols;

    figure;
    imagesc(abs(txGrid(:,:,1))); 
    xlabel('OFDM Symbol Index'); ylabel('Subcarrier Index');
    title('PDSCH Resource Grid with DMRS Mapping');
    colorbar;


    % OFDM modulation
    txWaveform = nrOFDMModulate(carrier_config, txGrid);

    % Ensure fixed length
    minLength = 15360;
    if length(txWaveform) < minLength
        padLength = minLength - length(txWaveform);
        txWaveform = [txWaveform; zeros(padLength, size(txWaveform,2))];
    end
end
