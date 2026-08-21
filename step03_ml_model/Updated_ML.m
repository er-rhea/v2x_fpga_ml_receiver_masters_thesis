%% UNIVERSAL SYMBOL RECOVERY MODEL (Sample-by-Sample Processing) - HDL Compatible Version
clc; clear; close all;

datasetPath = 'dataset_n';
fprintf('🔍 Loading dataset from %s\n', datasetPath);
filePattern = fullfile(datasetPath, 'frame_*.mat');
files = dir(filePattern);

X_sequences = {};
Y_sequences = {};
modLabels = []; % Keep track of modulation orders for analysis

% Define mapping from dataset's modulation code to real order
modMap = containers.Map([1 2 3 4], [16 64 4 256]);

%% Load data
fprintf('📦 Loading %d files...\n', numel(files));
for k = 1:numel(files)
    if mod(k, 100) == 0 || k == 1
        fprintf('   File %d/%d (%.1f%%)...\n', k, numel(files), 100*k/numel(files));
    end

    dataFile = fullfile(datasetPath, files(k).name);
    S = load(dataFile);

    % Get modulation type if available
    if isfield(S.features, 'modulation')
        modCode = double(S.features.modulation);
        if isKey(modMap, modCode)
            modOrder = modMap(modCode);
        else
            modOrder = 16; % fallback if unknown
        end
    else
        modOrder = 16; % default
    end

    % Features: [624 x 14 x 2] -> [28 x 624]
    feats = S.features.input;
    seqLen = size(feats, 1);
    inputSeq = reshape(feats, seqLen, [])'; % [28 x 624]

    % Append modulation order as an extra constant feature row
    modFeature = repmat(log2(modOrder)/8, 1, size(inputSeq, 2)); 
    inputSeq = [inputSeq; modFeature]; % [29 x 624]

    % Labels: I/Q symbols
    symb = S.labels.symbols(1:seqLen);
    IQ_seq = [real(symb)'; imag(symb)'];

    X_sequences{end+1} = single(inputSeq);
    Y_sequences{end+1} = single(IQ_seq);
    modLabels(end+1) = modOrder;
end
fprintf('✅ Loaded %d sequences across multiple modulations\n', numel(X_sequences));

%% Normalize (per-feature)
fprintf('🧪 Per-feature normalization...\n');
all_X = cat(2, X_sequences{:});
dataMean = mean(all_X, 2);
dataStd = std(all_X, 0, 2);
dataStd(dataStd < 1e-6) = 1;
X_sequences = cellfun(@(x) (x - dataMean) ./ dataStd, X_sequences, 'UniformOutput', false);

%% Split
fprintf('📊 Train/Val split...\n');
numSeqs = numel(X_sequences);
idx = randperm(numSeqs);
numTrain = round(0.8 * numSeqs);

XTrain = X_sequences(idx(1:numTrain));
YTrain = Y_sequences(idx(1:numTrain));
XVal = X_sequences(idx(numTrain+1:end));
YVal = Y_sequences(idx(numTrain+1:end));

fprintf('Training: %d | Validation: %d\n', numel(XTrain), numel(XVal));

%% Modified Model Architecture for Sample-by-Sample (For HDL Compatibility)
layersForHDL = [
    % Input layer to handle sequence input
    sequenceInputLayer(29, 'Name', 'input')  % Input layer with 29 features

    % Convolution layers
    convolution1dLayer(9, 32, 'Padding', 'same', 'Name', 'conv1')
    reluLayer('Name', 'relu1')

    convolution1dLayer(7, 64, 'Padding', 'same', 'Name', 'conv2')
    reluLayer('Name', 'relu2')

    convolution1dLayer(5, 64, 'Padding', 'same', 'Name', 'conv3')
    reluLayer('Name', 'relu3')

    convolution1dLayer(3, 32, 'Padding', 'same', 'Name', 'conv4')
    reluLayer('Name', 'relu4')

    convolution1dLayer(1, 2, 'Name', 'conv_out')  % Output layer for I/Q symbols
    regressionLayer('Name', 'output')
];

%% Training Options for Sample-by-Sample
options = trainingOptions('adam', ...
    'MaxEpochs', 50, ...
    'MiniBatchSize', 1, ...  % Use a batch size of 1 for sample-by-sample processing
    'InitialLearnRate', 1e-3, ...
    'LearnRateSchedule', 'piecewise', ...
    'LearnRateDropFactor', 0.5, ...
    'LearnRateDropPeriod', 20, ...
    'L2Regularization', 1e-6, ...
    'GradientThreshold', 5, ...
    'Shuffle', 'every-epoch', ...
    'ValidationData', {XVal, YVal}, ...
    'ValidationFrequency', 50, ...
    'ValidationPatience', 20, ...
    'Plots', 'training-progress', ...
    'Verbose', true, ...
    'VerboseFrequency', 50);

fprintf('🚀 Training the simplified model...\n');
netForHDL = trainNetwork(XTrain, YTrain, layersForHDL, options);

%% Save the trained model
save('SymbolRecoveryModel_UNIVERSAL_further_reduced_HDLCOMPAT.mat', 'netForHDL', 'dataMean', 'dataStd', 'modMap');
fprintf('💾 Model saved for HDL code generation\n');
