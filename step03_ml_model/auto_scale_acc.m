%% HDL-LIKE 24-BIT LAYER-BY-LAYER FIXED-POINT EVALUATION WITH 24-BIT MACs
clc; clear; close all;
%% Load trained model & dataset
load('SymbolRecoveryModel_UNIVERSAL_further_reduced_HDLCOMPAT.mat', ...
    'netForHDL', 'dataMean', 'dataStd', 'modMap');
datasetPath = 'dataset_n';
fprintf('🔍 Loading dataset from %s\n', datasetPath);
% NOTE: The dataset must be available at 'dataset_n' for this code to run fully.
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
layers = netForHDL.Layers;
%% --- Step 1: Define 24-bit fixed-point types (HEADROOM FIX) ---
% T_int: Q3.20 (Range approx [-8, 8)), used for all intermediate layers (W, b, A).
T_int = numerictype(1,24,22);
% T_acc: Q3.20 (Range approx [-8, 8)), used for the MAC accumulator.
T_acc = numerictype(1,24,22); 
% T_final_out: Q1.23 (Range approx [-1, 1)), used ONLY for the final output symbols.
T_final_out = numerictype(1,24,22); 

F = fimath('RoundingMethod','Nearest','OverflowAction','Saturate', ...
           'ProductMode','SpecifyPrecision','ProductWordLength',24,'ProductFractionLength',22, ...
           'SumMode','SpecifyPrecision','SumWordLength',24,'SumFractionLength',20);
           
%% --- Step 2: REMOVING Normalization (Relying on T_int Headroom) ---
fprintf('⚠️ Bypassing explicit weight normalization to avoid scaling interference.\n');
% The normalization loop previously here is removed. 
% Weights and Biases will be quantized directly using T_int (Q3.20).

%% --- Step 3: Evaluate subset of validation data ---
numEval = min(100, numel(XVal));
[Yfp, Yfx, Ytrue] = deal(cell(numEval,1));
fprintf('🧪 Running layer-wise 24-bit evaluation with 24-bit MACs...\n');
for i = 1:numEval
    X = XVal{i};
    Ytrue{i} = YVal{i};
    %% Floating-point prediction
    Yfp{i} = predict(netForHDL, X);
    %% Layer-by-layer 24-bit fixed-point
    A = fi(X, T_int, F);  % Input A starts in T_int (Q3.20)
    for l = 2:numel(layers)
        layer = layers(l);
        
        % Determine the output type for the current layer
        current_T_out = T_int; % Default is T_int for intermediate layers
        if l == numel(layers) - 1 
            % The layer *before* the final RegressionLayer must output the symbols (Q1.23)
            current_T_out = T_final_out;
        end
        
        switch class(layer)
            case 'nnet.cnn.layer.Convolution1DLayer'
                % Quantize W and b using the intermediate T_int (Q3.20)
                % This uses the original (un-normalized) weights from netForHDL.
                W = fi(layer.Weights, T_int, F); 
                b = fi(layer.Bias, T_int, F);    
                
                seqLen = size(A,2);
                numFilt = layer.NumFilters;
                numChA = size(A,1);
                numChW = size(W,2);
                minCh = min(numChA, numChW);
                
                % Anew uses the determined output type (T_int or T_final_out)
                Anew = fi(zeros(numFilt, seqLen), current_T_out, F);
                
                for f = 1:numFilt
                    acc = fi(zeros(1, seqLen), T_acc, F);  % 24-bit MAC (Q3.20)
                    
                    for c = 1:minCh
                        sig = double(A(c,:));       
                        kernel = double(W(:,c,f))';  
                        convOut = conv(sig, fliplr(kernel), 'same');
                        acc = acc + fi(convOut, T_acc, F);  % Accumulate in T_acc
                    end
                    
                    acc = acc + fi(double(b(f)), T_acc, F);
                    
                    % Final output cast from T_acc to current_T_out (Q3.20 or Q1.23)
                    Anew(f,:) = fi(acc, current_T_out, F);
                end
                
                A = Anew;
                
            case 'nnet.cnn.layer.ReLULayer'
                % ReLU output uses the determined output type
                A = fi(max(A,0), current_T_out, F);
                
            case 'nnet.cnn.layer.RegressionLayer'
                continue;
            otherwise
                warning('Skipping unsupported layer: %s', class(layer));
        end
    end
    Yfx{i} = double(A);
end
%% --- Step 4: Compute metrics ---
rmse_fp = sqrt(mean(cellfun(@(y,t) mean((y(:)-t(:)).^2), Yfp, Ytrue)));
rmse_fx = sqrt(mean(cellfun(@(y,t) mean((y(:)-t(:)).^2), Yfx, Ytrue)));
mae_fp  = mean(cellfun(@(y,t) mean(abs(y(:)-t(:))), Yfp, Ytrue));
mae_fx  = mean(cellfun(@(y,t) mean(abs(y(:)-t(:))), Yfx, Ytrue));
thr = 0.1;
symbol_err_fp = mean(cellfun(@(y,t) mean(vecnorm(y-t) > thr), Yfp, Ytrue));
symbol_err_fx = mean(cellfun(@(y,t) mean(vecnorm(y-t) > thr), Yfx, Ytrue));
fprintf('\n=== HDL-LIKE MODEL COMPARISON (FP32 vs 24-bit MAC Q3.20/Q1.23 Headroom Fix) ===\n');
fprintf('RMSE (FP32): %.6f\n', rmse_fp);
fprintf('RMSE (FX24): %.6f\n', rmse_fx);
fprintf('MAE  (FP32): %.6f\n', mae_fp);
fprintf('MAE  (FX24): %.6f\n', mae_fx);
fprintf('SER  (FP32): %.4f\n', symbol_err_fp);
fprintf('SER  (FX24): %.4f\n', symbol_err_fx);
fprintf('Relative RMSE degradation: %.2f%%\n', 100*(rmse_fx - rmse_fp)/rmse_fp);
%% --- Step 5: Plot example ---
idx = 5;
figure('Name','24-bit MAC Fixed-Point Output with Headroom Fix','Color','w');
subplot(1,2,1);
plot(Ytrue{idx}(1,:), Ytrue{idx}(2,:), 'k.', 'DisplayName','True'); hold on;
plot(Yfp{idx}(1,:), Yfp{idx}(2,:), 'bo', 'DisplayName','FP32'); axis equal; legend; grid on; title('FP32');
subplot(1,2,2);
plot(Ytrue{idx}(1,:), Ytrue{idx}(2,:), 'k.', 'DisplayName','True'); hold on;
plot(Yfx{idx}(1,:), Yfx{idx}(2,:), 'ro', 'DisplayName','FX24'); axis equal; legend; grid on; title('Q3.20/Q1.23 Headroom Fix (No Scaling)');