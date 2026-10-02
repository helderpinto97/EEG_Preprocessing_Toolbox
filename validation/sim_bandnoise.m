function x = sim_bandnoise(pnts, srate, band)
% SIM_BANDNOISE  Unit-variance noise with power only inside BAND (Hz).
%
%   x = sim_bandnoise(pnts, srate, [fLow fHigh])   fHigh may be Inf
%
% Shaped in the frequency domain, so no toolbox filter is needed.
F = fft(randn(1, pnts));
f = (0:pnts-1) * srate / pnts;
f = min(f, srate - f);                     % two-sided frequency axis
F(f < band(1) | f > band(2)) = 0;
x = real(ifft(F));
x = x / std(x);
end
