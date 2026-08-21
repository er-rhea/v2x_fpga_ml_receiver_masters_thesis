function cdlChan = channel(simParams, speed)
    light_speed = physconst('LightSpeed');
    doppler_shift_freq = (speed / 3.6) * simParams.Carrier_freq / light_speed;

    f = linspace(-doppler_shift_freq, doppler_shift_freq, 200);
S = (1/pi) ./ sqrt(1-(f/doppler_shift_freq).^2);  % Jakes spectrum
plot(f, S);
xlabel('Frequency (Hz)'); ylabel('Relative Power');
title(['Doppler Spectrum at ' num2str(simParams.MaxSpeed) ' km/h']);
grid on;

    cdlChan = nrCDLChannel;
    cdlChan.DelayProfile = 'CDL-D';
    cdlChan.DelaySpread = 300e-9;
    cdlChan.CarrierFrequency = simParams.Carrier_freq;
    cdlChan.MaximumDopplerShift = doppler_shift_freq;
    cdlChan.SampleRate = 2000 * simParams.SampleRate;
    cdlChan.NormalizeChannelOutputs = true;

    % SISO Antenna
    cdlChan.TransmitAntennaArray.Size = [1 1 1 1 1];
    cdlChan.ReceiveAntennaArray.Size = [1 1 1 1 1];
    
    %[rows, columns, layers, polarization, panels].
end

