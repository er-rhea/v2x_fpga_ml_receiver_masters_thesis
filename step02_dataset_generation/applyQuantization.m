function quantized = applyQuantization(x, numBits)
    % Uniform quantization of complex-valued signal x using numBits bits.
    % Assumes symmetric quantizer with range [-1, 1] for both real and imag parts.

    % Saturate inputs to [-1, 1] range
    x = max(min(real(x), 1), -1) + 1i * max(min(imag(x), 1), -1);

    % Quantization levels
    levels = 2^numBits;
    step = 2 / (levels - 1); % step size for range [-1, 1]

    % Quantize real and imaginary parts separately
    quantizedReal = round((real(x) + 1) / step) * step - 1;
    quantizedImag = round((imag(x) + 1) / step) * step - 1;

    quantized = complex(quantizedReal, quantizedImag);
end