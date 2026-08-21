%% ============================================================
%  ML Model Comparison for V2X Modulation Classification
%  Models: SVM, FCN, RNN, CNN, Transformer
% ============================================================

clc; clear; close all;

fprintf('🚗 Starting Modulation Classification Model Comparison...\n');

%% Load Dataset
load('v2x_dataset_combined.mat'); % <- use your combined dataset
X = [allData.real_rx, allData.imag_rx, allData.speed, allData.snr]; % features
Y = categorical(allData.modulation); % labels

fprintf("✅ Loaded dataset: %d samples, %d features\n", size(X,1), size(X,2));

%% Clean NaNs or Infs
nanIdx = any(isnan(X), 2) | any(isinf(X), 2);
X(nanIdx,:) = [];
Y(nanIdx,:) = [];

fprintf("✅ Cleaned dataset: %d samples remaining\n", size(X,1));

%% Train/Test Split
cv = cvpartition(Y, 'HoldOut', 0.2);
XTrain = X(training(cv), :);
YTrain = Y(training(cv));
XTest  = X(test(cv), :);
YTest  = Y(test(cv));

fprintf("📊 Train: %d | Test: %d\n", size(XTrain,1), size(XTest,1));

%% Prepare sequence data for RNN/CNN/Transformer
XseqTrain = num2cell(XTrain, 2);
XseqTest  = num2cell(XTest, 2);

%% Training options
opts = trainingOptions('adam', ...
    'MaxEpochs',10, ...
    'MiniBatchSize',256, ...
    'Verbose',false, ...
    'Plots','none');

%% Initialize result arrays
models = ["SVM","FCN","RNN","CNN","Transformer"];
accuracies = zeros(length(models),1);
times = zeros(length(models),1);

%% ============================================================
%  Model 1: Support Vector Machine (SVM)
% ============================================================
fprintf('🔹 Training SVM classifier...\n');
try
    tStart = tic;
    tSVM = templateSVM('KernelFunction','rbf','Standardize',true);
    mdlSVM = fitcecoc(XTrain, YTrain, 'Learners', tSVM, 'Coding','onevsall');
    trainTime = toc(tStart);

    YPred = predict(mdlSVM, XTest);
    acc = mean(YPred == YTest);

    accuracies(1) = acc;
    times(1) = trainTime;
    fprintf("✅ SVM Accuracy: %.2f%% | Training Time: %.2fs\n", acc*100, trainTime);
catch ME
    warning("⚠️ SVM training failed: %s", ME.message);
    accuracies(1) = NaN; times(1) = NaN;
end

%% ============================================================
%  Model 2: Fully Connected Network (FCN)
% ============================================================
fprintf('🔹 Training Fully Connected Network (FCN)...\n');
layersFCN = [
    featureInputLayer(size(XTrain,2))
    fullyConnectedLayer(128)
    reluLayer
    fullyConnectedLayer(64)
    reluLayer
    fullyConnectedLayer(numel(categories(YTrain)))
    softmaxLayer
    classificationLayer
];

try
    tStart = tic;
    mdlFCN = trainNetwork(XTrain, YTrain, layersFCN, opts);
    trainTime = toc(tStart);

    YPred = classify(mdlFCN, XTest);
    acc = mean(YPred == YTest);

    accuracies(2) = acc;
    times(2) = trainTime;
    fprintf("✅ FCN Accuracy: %.2f%% | Training Time: %.2fs\n", acc*100, trainTime);
catch ME
    warning("⚠️ FCN training failed: %s", ME.message);
    accuracies(2) = NaN; times(2) = NaN;
end

%% ============================================================
%  Model 3: RNN (LSTM)
% ============================================================
fprintf('🔹 Training RNN (LSTM)...\n');
layersRNN = [
    sequenceInputLayer(size(XTrain,2))
    lstmLayer(128, 'OutputMode','last')
    fullyConnectedLayer(numel(categories(YTrain)))
    softmaxLayer
    classificationLayer
];

try
    tStart = tic;
    mdlRNN = trainNetwork(XseqTrain, YTrain(1:length(XseqTrain)), layersRNN, opts);
    trainTime = toc(tStart);

    YPred = classify(mdlRNN, XseqTest);
    acc = mean(YPred == YTest(1:length(YPred)));

    accuracies(3) = acc;
    times(3) = trainTime;
    fprintf("✅ RNN Accuracy: %.2f%% | Training Time: %.2fs\n", acc*100, trainTime);
catch ME
    warning("⚠️ RNN training failed: %s", ME.message);
    accuracies(3) = NaN; times(3) = NaN;
end

%% ============================================================
%  Model 4: 1D CNN
% ============================================================
fprintf('🔹 Training 1D CNN...\n');
layersCNN = [
    sequenceInputLayer(size(XTrain,2))
    convolution1dLayer(5,32,'Padding','same')
    batchNormalizationLayer
    reluLayer
    convolution1dLayer(3,64,'Padding','same')
    batchNormalizationLayer
    reluLayer
    globalAveragePooling1dLayer
    fullyConnectedLayer(numel(categories(YTrain)))
    softmaxLayer
    classificationLayer
];

try
    tStart = tic;
    mdlCNN = trainNetwork(XseqTrain, YTrain(1:length(XseqTrain)), layersCNN, opts);
    trainTime = toc(tStart);

    YPred = classify(mdlCNN, XseqTest);
    acc = mean(YPred == YTest(1:length(YPred)));

    accuracies(4) = acc;
    times(4) = trainTime;
    fprintf("✅ CNN Accuracy: %.2f%% | Training Time: %.2fs\n", acc*100, trainTime);
catch ME
    warning("⚠️ CNN training failed: %s", ME.message);
    accuracies(4) = NaN; times(4) = NaN;
end

%% ============================================================
%  Model 5: Transformer
% ============================================================
fprintf('🔹 Training Transformer model...\n');
layersTransformer = [
    sequenceInputLayer(size(XTrain,2))
    transformerEncoderLayer(4,64,128)
    flattenLayer
    fullyConnectedLayer(numel(categories(YTrain)))
    softmaxLayer
    classificationLayer
];

try
    tStart = tic;
    mdlTransformer = trainNetwork(XseqTrain, YTrain(1:length(XseqTrain)), layersTransformer, opts);
    trainTime = toc(tStart);

    YPred = classify(mdlTransformer, XseqTest);
    acc = mean(YPred == YTest(1:length(YPred)));

    accuracies(5) = acc;
    times(5) = trainTime;
    fprintf("✅ Transformer Accuracy: %.2f%% | Training Time: %.2fs\n", acc*100, trainTime);
catch ME
    warning("⚠️ Transformer training failed: %s", ME.message);
    accuracies(5) = NaN; times(5) = NaN;
end

%% ============================================================
%  Summary Table
% ============================================================
fprintf('\n📊 Model Performance Summary:\n');
resultTable = table(models', round(accuracies*100,2), round(times,2), ...
    'VariableNames', {'Model','Accuracy_percent','TrainingTime_sec'});
disp(resultTable);

%% ============================================================
%  Bar Plot Summary
% ============================================================
figure;
yyaxis left;
bar(categorical(resultTable.Model), resultTable.Accuracy_percent);
ylabel('Accuracy (%)');
yyaxis right;
plot(categorical(resultTable.Model), resultTable.TrainingTime_sec, '-o', 'LineWidth', 1.5);
ylabel('Training Time (s)');
title('Model Accuracy vs Training Time');
grid on;
