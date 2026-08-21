%% HDL-LIKE 24-BIT LAYER-BY-LAYER FIXED-POINT EVALUATION WITH HEX EXPORT
clc; clear; close all;
%% Helper function to convert fixed-point to hex
function hex_str = fi_to_hex(fi_val)
    % Convert fixed-point value to 24-bit hex string
    % Get the binary representation as a string
    bin_str = fi_val.bin;
    
    % Convert binary string to decimal (unsigned interpretation)
    val_uint = bin2dec(bin_str);
    
    % Format as 6-character hex string
    hex_str = sprintf('%06X', val_uint);
end
%% Load trained model & dataset
load('SymbolRecoveryModel_UNIVERSAL_further_reduced_HDLCOMPAT.mat', ...
    'netForHDL', 'dataMean', 'dataStd', 'modMap');
datasetPath = 'dataset_n';
fprintf('🔍 Loading dataset from %s\n', datasetPath);
filePattern = fullfile(datasetPath, 'frame_*.mat');
files = dir(filePattern);
X_sequences = {};
Y_sequences = {};
modLabels = [];
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
    
    if isfield(S.features, 'modulation')
        modCode = double(S.features.modulation);
        if isKey(modMap, modCode)
            modOrder = modMap(modCode);
        else
            modOrder = 16;
        end
    else
        modOrder = 16;
    end
    
    feats = S.features.input;
    seqLen = size(feats, 1);
    inputSeq = reshape(feats, seqLen, [])';
    modFeature = repmat(log2(modOrder)/8, 1, size(inputSeq, 2)); 
    inputSeq = [inputSeq; modFeature];
    
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
%% --- Define 24-bit fixed-point types ---
% Intermediate layers: Q3.20
T_int = numerictype(1,24,22);
% Output layer: Q1.22
T_final_out = numerictype(1,24,22); 
F = fimath('RoundingMethod','Nearest','OverflowAction','Saturate', ...
           'ProductMode','SpecifyPrecision','ProductWordLength',24,'ProductFractionLength',22, ...
           'SumMode','SpecifyPrecision','SumWordLength',24,'SumFractionLength',22);
%% --- QUANTIZE WEIGHTS AND BIASES ---
fprintf('🔧 Quantizing weights and biases...\n');
% Storage for quantized weights and biases
W_fixed = cell(5,1);
B_fixed = cell(5,1);
layer_idx = 0;
% Determine the total number of layers for the final output check
num_total_layers = numel(layers);
for l = 2:num_total_layers
    layer = layers(l);
    
    if isa(layer, 'nnet.cnn.layer.Convolution1DLayer')
        layer_idx = layer_idx + 1;
        
        % Check if the next layer is the RegressionLayer
        is_output_layer = (l == num_total_layers - 1);
        
        if is_output_layer
            % Output layer: Q1.22
            W_fixed{layer_idx} = fi(layer.Weights, T_final_out, F);
            B_fixed{layer_idx} = fi(layer.Bias, T_final_out, F);
            fprintf('   Layer %d (Output): Quantized to Q1.22\n', layer_idx);
        else
            % Intermediate layers: Q3.20
            W_fixed{layer_idx} = fi(layer.Weights, T_int, F);
            B_fixed{layer_idx} = fi(layer.Bias, T_int, F);
            fprintf('   Layer %d (Hidden): Quantized to Q2.21\n', layer_idx);
        end
    end
end
%% --- EXPORT WEIGHTS AND BIASES AS HEX FILES ---
fprintf('💾 Exporting weights and biases to hex files...\n');
output_dir = 'hdl_hex_data';
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end
% This loop needs to correctly determine the quantization type
conv_layer_indices = find(arrayfun(@(x) isa(x, 'nnet.cnn.layer.Convolution1DLayer'), layers));
num_conv_layers = length(conv_layer_indices);
for layer_idx = 1:num_conv_layers
    W = W_fixed{layer_idx};
    B = B_fixed{layer_idx};
    
    % Determine the correct quantization type for writing hex
    % The index l is the full layer index, conv_layer_indices(layer_idx)
    l = conv_layer_indices(layer_idx);
    is_output_layer = (l == num_total_layers - 1);
    
    current_T = T_int;
    if is_output_layer
        current_T = T_final_out;
    end
    
    % Get dimensions
    [K, CIN, COUT] = size(W.data);
    
    % Flatten weights: [K x CIN x COUT] -> linear array
    W_flat = permute(W.data, [3, 2, 1]); % [COUT x CIN x K]
    W_flat = W_flat(:); % Flatten to column vector
    
    % Write weights using proper formatting
    w_filename = fullfile(output_dir, sprintf('weights_layer%d.hex', layer_idx));
    fid = fopen(w_filename, 'w');
    
    for i = 1:length(W_flat)
        % Create a temporary fi object from the data for correct hex conversion
        % using the determined type and fimath
        fi_val = fi(W_flat(i), current_T, F); 
        fprintf(fid, '%s\n', fi_to_hex(fi_val));
    end
    fclose(fid);
    fprintf('   ✓ Wrote %s (%d weights)\n', w_filename, length(W_flat));
    
    % Write biases using proper formatting
    b_filename = fullfile(output_dir, sprintf('biases_layer%d.hex', layer_idx));
    fid = fopen(b_filename, 'w');
    for i = 1:length(B.data)
        fi_val = fi(B.data(i), current_T, F);
        fprintf(fid, '%s\n', fi_to_hex(fi_val));
    end
    fclose(fid);
    fprintf('   ✓ Wrote %s (%d biases)\n', b_filename, length(B.data));
end
%% --- EXPORT NORMALIZATION PARAMETERS ---
fprintf('💾 Exporting normalization parameters...\n');
% Quantize normalization params to Q3.20
dataMean_fixed = fi(dataMean, T_int, F);
dataStd_fixed = fi(dataStd, T_int, F);
% Compute inverse std for multiplication instead of division
dataInvStd = 1 ./ dataStd;
dataInvStd_fixed = fi(dataInvStd, T_int, F);
% Export mean
mean_filename = fullfile(output_dir, 'norm_mean.hex');
fid = fopen(mean_filename, 'w');
for i = 1:length(dataMean_fixed.data)
    fprintf(fid, '%s\n', fi_to_hex(fi(dataMean_fixed.data(i), T_int, F)));
end
fclose(fid);
fprintf('   ✓ Wrote %s (%d values)\n', mean_filename, length(dataMean));
% Export inverse std
invstd_filename = fullfile(output_dir, 'norm_invstd.hex');
fid = fopen(invstd_filename, 'w');
for i = 1:length(dataInvStd_fixed.data)
    fprintf(fid, '%s\n', fi_to_hex(fi(dataInvStd_fixed.data(i), T_int, F)));
end
fclose(fid);
fprintf('   ✓ Wrote %s (%d values)\n', invstd_filename, length(dataInvStd));
%% --- EVALUATE AND EXPORT TEST VECTORS ---

% MODIFICATION 1: Change evaluation size to 100 samples and select randomly
numEval = min(100, numel(XVal)); % Use up to 100 test sequences
eval_indices = randperm(numel(XVal), numEval);
XVal_eval = XVal(eval_indices);
YVal_eval = YVal(eval_indices);

fprintf('🧪 Generating %d test vectors...\n', numEval);
for test_idx = 1:numEval
    % Use the randomly selected evaluation set
    X = XVal_eval{test_idx}; 
    Ytrue = YVal_eval{test_idx};
    
    %% Floating-point prediction
    Yfp = predict(netForHDL, X);
    
    %% Layer-by-layer 24-bit fixed-point
    A = fi(X, T_int, F);
    
    for l = 2:num_total_layers
        layer = layers(l);
        
        is_output_layer = (l == num_total_layers - 1);
        if(is_output_layer)
            current_T_out = T_final_out;
        else
            current_T_out = T_int;
        end
        
        switch class(layer)
            case 'nnet.cnn.layer.Convolution1DLayer'
                % FIX: Use arrayfun instead of cellfun to count preceding Convolution1DLayer objects
                layer_idx = sum(arrayfun(@(x) isa(x, 'nnet.cnn.layer.Convolution1DLayer'), layers(2:l)));
                
                W = W_fixed{layer_idx};
                b = B_fixed{layer_idx};
                
                seqLen = size(A,2);
                numFilt = layer.NumFilters;
                numChA = size(A,1);
                numChW = size(W,2);
                minCh = min(numChA, numChW);
                
                Anew = fi(zeros(numFilt, seqLen), current_T_out, F);
                
                for f = 1:numFilt
                    acc = fi(zeros(1, seqLen), T_int, F);
                    
                    for c = 1:minCh
                        sig = double(A(c,:));       
                        kernel = double(W(:,c,f))';  
                        convOut = conv(sig, fliplr(kernel), 'same');
                        acc = acc + fi(convOut, T_int, F);
                    end
                    
                    acc = acc + fi(double(b(f)), T_int, F);
                    Anew(f,:) = fi(acc, current_T_out, F);
                end
                
                A = Anew;
                
            case 'nnet.cnn.layer.ReLULayer'
                A = fi(max(A,0), current_T_out, F);
                
            case 'nnet.cnn.layer.RegressionLayer'
                continue;
        end
    end
    
    Yfx = double(A);
    
    %% Export test vectors
    % Input (normalized, Q3.20)
    input_filename = fullfile(output_dir, sprintf('test_input_%02d.hex', test_idx));
    fid = fopen(input_filename, 'w');
    [nChannels, nTimeSteps] = size(X);
    % Write as channel-major: Ch0_t0, Ch0_t1, ..., Ch1_t0, Ch1_t1, ...
    for ch = 1:nChannels
        for t = 1:nTimeSteps
            fprintf(fid, '%s\n', fi_to_hex(fi(X(ch, t), T_int, F)));
        end
    end
    fclose(fid);
    
    % Expected output (Q1.22 for I/Q symbols)
    output_filename = fullfile(output_dir, sprintf('test_output_%02d.hex', test_idx));
    fid = fopen(output_filename, 'w');
    [nOutChannels, nOutTimeSteps] = size(Yfx);
    % Write as channel-major: I_t0, I_t1, ..., Q_t0, Q_t1, ...
    for ch = 1:nOutChannels
        for t = 1:nOutTimeSteps
            fprintf(fid, '%s\n', fi_to_hex(fi(Yfx(ch, t), T_final_out, F)));
        end
    end
    fclose(fid);
    
    % Metadata
    meta_filename = fullfile(output_dir, sprintf('test_meta_%02d.txt', test_idx));
    fid = fopen(meta_filename, 'w');
    fprintf(fid, 'Input Channels: %d\n', nChannels);
    fprintf(fid, 'Input Time Steps: %d\n', nTimeSteps);
    fprintf(fid, 'Output Channels: %d\n', nOutChannels);
    fprintf(fid, 'Output Time Steps: %d\n', nOutTimeSteps);
    fprintf(fid, 'Total Input Samples: %d\n', nChannels * nTimeSteps);
    fprintf(fid, 'Total Output Samples: %d\n', nOutChannels * nOutTimeSteps);
    fclose(fid);
    
    fprintf('   ✓ Test %02d: Input=%dx%d, Output=%dx%d\n', ...
            test_idx, nChannels, nTimeSteps, nOutChannels, nOutTimeSteps);
end
%% --- COMPUTE METRICS ---
fprintf('\n📊 Computing metrics on %d validation samples...\n', numEval);
[Yfp_all, Yfx_all, Ytrue_all] = deal(cell(numEval,1));
for i = 1:numEval
    % Use the randomly selected evaluation set
    X = XVal_eval{i};
    Ytrue_all{i} = YVal_eval{i};
    
    % Floating-point prediction (FP32)
    Yfp_all{i} = predict(netForHDL, X);
    
    % Fixed-point prediction (FX24)
    A = fi(X, T_int, F);
    for l = 2:num_total_layers
        layer = layers(l);
        is_output_layer = (l == num_total_layers - 1);
        if(is_output_layer)
            current_T_out = T_final_out;
        else
            current_T_out = T_int;
        end
        
        switch class(layer)
            case 'nnet.cnn.layer.Convolution1DLayer'
                % FIX: Use arrayfun instead of cellfun to count preceding Convolution1DLayer objects
                layer_idx = sum(arrayfun(@(x) isa(x, 'nnet.cnn.layer.Convolution1DLayer'), layers(2:l)));
                
                W = W_fixed{layer_idx};
                b = B_fixed{layer_idx};
                
                seqLen = size(A,2);
                numFilt = layer.NumFilters;
                numChA = size(A,1);
                numChW = size(W,2);
                minCh = min(numChA, numChW);
                
                Anew = fi(zeros(numFilt, seqLen), current_T_out, F);
                
                for f = 1:numFilt
                    acc = fi(zeros(1, seqLen), T_int, F);
                    for c = 1:minCh
                        sig = double(A(c,:));       
                        kernel = double(W(:,c,f))';  
                        convOut = conv(sig, fliplr(kernel), 'same');
                        acc = acc + fi(convOut, T_int, F);
                    end
                    acc = acc + fi(double(b(f)), T_int, F);
                    Anew(f,:) = fi(acc, current_T_out, F);
                end
                A = Anew;
                
            case 'nnet.cnn.layer.ReLULayer'
                A = fi(max(A,0), current_T_out, F);
        end
    end
    Yfx_all{i} = double(A);
end

% --- ACCURACY AGAINST GROUND TRUTH (True Labels) ---
rmse_fp = sqrt(mean(cellfun(@(y,t) mean((y(:)-t(:)).^2), Yfp_all, Ytrue_all)));
rmse_fx = sqrt(mean(cellfun(@(y,t) mean((y(:)-t(:)).^2), Yfx_all, Ytrue_all)));
mae_fp  = mean(cellfun(@(y,t) mean(abs(y(:)-t(:))), Yfp_all, Ytrue_all));
mae_fx  = mean(cellfun(@(y,t) mean(abs(y(:)-t(:))), Yfx_all, Ytrue_all));
thr = 0.1;
symbol_err_fp = mean(cellfun(@(y,t) mean(vecnorm(y-t) > thr), Yfp_all, Ytrue_all));
symbol_err_fx = mean(cellfun(@(y,t) mean(vecnorm(y-t) > thr), Yfx_all, Ytrue_all));

fprintf('\n=== MODEL ACCURACY (FP32 & FX24 vs TRUE LABELS) ===\n');
fprintf('RMSE (FP32 vs True): %.6f\n', rmse_fp);
fprintf('RMSE (FX24 vs True): %.6f\n', rmse_fx);
fprintf('MAE  (FP32 vs True): %.6f\n', mae_fp);
fprintf('MAE  (FX24 vs True): %.6f\n', mae_fx);
fprintf('SER  (FP32 vs True): %.4f\n', symbol_err_fp);
fprintf('SER  (FX24 vs True): %.4f\n', symbol_err_fx);
fprintf('Relative RMSE degradation from True Accuracy: %.2f%%\n', 100*(rmse_fx - rmse_fp)/rmse_fp);

% MODIFICATION 2: Add Quantization Degradation Metrics
%% --- QUANTIZATION DEGRADATION METRICS (FX24 vs FP32 Output) ---
fprintf('\n=== QUANTIZATION DEGRADATION (FX24 vs FP32 Output) ===\n');

% Calculate Root Mean Squared Error (RMSE) between Fixed-Point and Floating-Point outputs
rmse_quant_degrad = sqrt(mean(cellfun(@(yfx,yfp) mean((yfx(:)-yfp(:)).^2), Yfx_all, Yfp_all)));

% Calculate Mean Absolute Error (MAE) between Fixed-Point and Floating-Point outputs
mae_quant_degrad  = mean(cellfun(@(yfx,yfp) mean(abs(yfx(:)-yfp(:))), Yfx_all, Yfp_all));

% Calculate Symbol Error Rate (SER) based on deviation between FP32 and FX24 output
% Use the same threshold (thr) defined earlier (0.1)
symbol_err_quant_degrad = mean(cellfun(@(yfx,yfp) mean(vecnorm(yfx-yfp) > thr), Yfx_all, Yfp_all));

fprintf('RMSE (FX24 vs FP32 Output): %.6f\n', rmse_quant_degrad);
fprintf('MAE  (FX24 vs FP32 Output): %.6f\n', mae_quant_degrad);
fprintf('SER  (FX24 vs FP32 Output): %.4f\n', symbol_err_quant_degrad);

%% --- GENERATE VERILOG HEADER ---
fprintf('\n📝 Generating Verilog header file...\n');
header_filename = fullfile(output_dir, 'cnn_params.vh');
fid = fopen(header_filename, 'w');
fprintf(fid, '// Auto-generated CNN parameters\n');
fprintf(fid, '// Generated: %s\n\n', datetime('now'));
fprintf(fid, '// Network architecture\n');
fprintf(fid, '`define NUM_LAYERS %d\n', num_conv_layers);
fprintf(fid, '`define INPUT_CHANNELS %d\n', size(XVal_eval{1}, 1)); % Use eval set to get dimensions
fprintf(fid, '`define INPUT_TIMESTEPS %d\n', size(XVal_eval{1}, 2));
fprintf(fid, '`define OUTPUT_CHANNELS %d\n', size(YVal_eval{1}, 1));
fprintf(fid, '`define OUTPUT_TIMESTEPS %d\n\n', size(YVal_eval{1}, 2));
for layer_idx = 1:num_conv_layers
    [K, CIN, COUT] = size(W_fixed{layer_idx}.data);
    fprintf(fid, '// Layer %d\n', layer_idx);
    fprintf(fid, '`define LAYER%d_KERNEL %d\n', layer_idx, K);
    fprintf(fid, '`define LAYER%d_CIN %d\n', layer_idx, CIN);
    fprintf(fid, '`define LAYER%d_COUT %d\n', layer_idx, COUT);
    fprintf(fid, '`define LAYER%d_WEIGHTS %d\n', layer_idx, K*CIN*COUT);
    fprintf(fid, '`define LAYER%d_BIASES %d\n\n', layer_idx, COUT);
end
fclose(fid);
fprintf('   ✓ Wrote %s\n', header_filename);
fprintf('\n✅ Export complete! Files written to: %s\n', output_dir);
%% --- VERIFICATION: Test hex conversion ---
fprintf('\n🔍 Verifying hex conversion...\n');
test_vals = [0, 1, -1, 0.5, -0.5, 2.5, -2.5];
fprintf('Q3.20 Test Values:\n');
for v = test_vals
    if abs(v) < 8  % Within Q3.20 range (approx 8)
        fi_val = fi(v, T_int, F);
        hex_val = fi_to_hex(fi_val);
        reconstructed = double(fi_val);
        fprintf('  %.4f -> %s -> %.4f (error: %.2e)\n', ...
                v, hex_val, reconstructed, abs(v - reconstructed));
    end
end
fprintf('\nQ1.22 Test Values:\n');
for v = test_vals
    if abs(v) < 2  % Within Q1.22 range (approx 2)
        fi_val = fi(v, T_final_out, F);
        hex_val = fi_to_hex(fi_val);
        reconstructed = double(fi_val);
        fprintf('  %.4f -> %s -> %.4f (error: %.2e)\n', ...
                v, hex_val, reconstructed, abs(v - reconstructed));
    end
end
%% --- Plot example ---
% Plotting the first sample from the new 100-sample evaluation set
idx = 1; 
figure('Name','Q3.20/Q1.22 Fixed-Point Results','Color','w');
subplot(1,2,1);
plot(Ytrue_all{idx}(1,:), Ytrue_all{idx}(2,:), 'k.', 'MarkerSize', 8, 'DisplayName','True'); 
hold on;
plot(Yfp_all{idx}(1,:), Yfp_all{idx}(2,:), 'bo', 'MarkerSize', 4, 'DisplayName','FP32'); 
axis equal; legend; grid on; title('FP32 vs True');
xlabel('I'); ylabel('Q');
subplot(1,2,2);
plot(Ytrue_all{idx}(1,:), Ytrue_all{idx}(2,:), 'k.', 'MarkerSize', 8, 'DisplayName','True'); 
hold on;
plot(Yfx_all{idx}(1,:), Yfx_all{idx}(2,:), 'ro', 'MarkerSize', 4, 'DisplayName','FX24'); 
axis equal; legend; grid on; title('Q3.20/Q1.22 vs True');
xlabel('I'); ylabel('Q');
