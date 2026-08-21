function [rxDemod] = reciever_main(rxWaveform, carrier)
    % Perform OFDM demodulation (includes CP removal and FFT)
    rxDemod = nrOFDMDemodulate(carrier, rxWaveform);
end
