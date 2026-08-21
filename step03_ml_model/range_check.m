%% --- RANGE CHECKS FOR HDL COMPATIBILITY ---
fprintf('\n🔎 Range Analysis for Weights, Biases, and Outputs...\n');

% === Check 1: Weights and Biases ===
allW = [];
allB = [];

for layer_idx = 1:num_conv_layers
    Wd = double(W_fixed{layer_idx}.data);
    Bd = double(B_fixed{layer_idx}.data);
    
    allW = [allW; Wd(:)];
    allB = [allB; Bd(:)];
    
    fprintf('   Layer %d:\n', layer_idx);
    fprintf('      Weights: min = %+1.6f | max = %+1.6f\n', min(Wd(:)), max(Wd(:)));
    fprintf('      Biases : min = %+1.6f | max = %+1.6f\n', min(Bd(:)), max(Bd(:)));
end

fprintf('→ Global Weight Range: [%+1.6f, %+1.6f]\n', min(allW), max(allW));
fprintf('→ Global Bias Range  : [%+1.6f, %+1.6f]\n', min(allB), max(allB));

% === Check 2: Normalization Parameters ===
fprintf('\n   Normalization Mean range: [%+1.6f, %+1.6f]\n', min(double(dataMean_fixed)), max(double(dataMean_fixed)));
fprintf('   Normalization InvStd range: [%+1.6f, %+1.6f]\n', min(double(dataInvStd_fixed)), max(double(dataInvStd_fixed)));

% === Check 3: Output Activation Ranges (FP32 vs FX24) ===
Yfp_concat = cat(2, Yfp_all{:});
Yfx_concat = cat(2, Yfx_all{:});
Ytrue_concat = cat(2, Ytrue_all{:});

fprintf('\n   FP32 Output Range : I=[%+1.6f, %+1.6f], Q=[%+1.6f, %+1.6f]\n', ...
    min(Yfp_concat(1,:)), max(Yfp_concat(1,:)), min(Yfp_concat(2,:)), max(Yfp_concat(2,:)));
fprintf('   FX24 Output Range : I=[%+1.6f, %+1.6f], Q=[%+1.6f, %+1.6f]\n', ...
    min(Yfx_concat(1,:)), max(Yfx_concat(1,:)), min(Yfx_concat(2,:)), max(Yfx_concat(2,:)));
fprintf('   True Output Range : I=[%+1.6f, %+1.6f], Q=[%+1.6f, %+1.6f]\n', ...
    min(Ytrue_concat(1,:)), max(Ytrue_concat(1,:)), min(Ytrue_concat(2,:)), max(Ytrue_concat(2,:)));

% === Check 4: Saturation / Overflow Detection ===
overflow_W = sum(abs(allW) > 2^3);  % Q3.20 max approx ±8
overflow_B = sum(abs(allB) > 2^3);
overflow_out = sum(abs(Yfx_concat(:)) > 2);

fprintf('\n⚠️  Saturation/Overflow summary:\n');
fprintf('   Weights exceeding Q3.20 range (±8): %d values\n', overflow_W);
fprintf('   Biases  exceeding Q3.20 range (±8): %d values\n', overflow_B);
fprintf('   Outputs exceeding Q1.22 range (±2): %d values\n', overflow_out);

if overflow_W == 0 && overflow_B == 0 && overflow_out == 0
    fprintf('✅ All values fit within HDL fixed-point range limits.\n');
else
    fprintf('⚠️ Some values exceed HDL range! Consider re-scaling or retraining.\n');
end
