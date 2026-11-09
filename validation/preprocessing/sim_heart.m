function hb = sim_heart(sim, seed)
% SIM_HEART  Heartbeats shared by the cardiac artifact and the coupled EEG.
%
%   hb = sim_heart(sim, seed)
%
% Beat-level model, beat n (heart period n runs from R peak n to n+1):
%   v(n) = sum_k phi_k v(n-k) + cBH * sv * a(n-1) + e(n)
%   a(n) = 0.5 a(n-1) + cHB * v(n-1) / sv + w(n)
% v is the AR(4) heart period variability of sim_ecg (poles 0.9 at 0.3 and
% 0.8 at 0.1 cycles/beat), sv its SD without coupling, a the log amplitude
% of the brain-heart source in heart period n (sim_coupled), e and w white
% unit-variance noise. [cHB cBH] = sim.bhCouple: heart -> brain and
% brain -> heart. The heart period is then 60/sim.heartRate * (1 + 0.05 v/SD(v)),
% and a is scaled to zero mean and unit SD.
%
% HB fields: t (R peak times, s; only beats whose PQRST complex fits in
% sim.secs), rr (heart periods, s, numel(t)-1) and a (log amplitude per
% heart period, numel(t)-1).

rng(seed);
rr0 = 60 / sim.heartRate;
nb  = ceil(1.5 * sim.secs / rr0) + 10;          % more beats than can fit
p   = [0.9 * exp([1 -1] * 1i*2*pi*0.3), 0.8 * exp([1 -1] * 1i*2*pi*0.1)];
den = real(poly(p));                            % [1 -phi_1 ... -phi_4]
h   = filter(1, den, [1 zeros(1, 2000)]);
sv  = sqrt(sum(h.^2));                          % SD of the uncoupled AR(4)
cHB = sim.bhCouple(1); cBH = sim.bhCouple(2);

burn = 200;
v = zeros(1, nb + burn); a = v;
e = randn(2, nb + burn);
for n = 5:nb + burn
    v(n) = -den(2:5) * v(n-1:-1:n-4)' + cBH * sv * a(n-1) + e(1, n);
    a(n) = 0.5 * a(n-1) + cHB * v(n-1) / sv + e(2, n);
end
v = v(burn+1:end); a = a(burn+1:end);
v = 0.05 * (v - mean(v)) / std(v);
a = (a - mean(a)) / std(a);

t = zeros(1, nb + 1);
t(1) = 0.5 + rand * rr0;                        % first R peak, s
for n = 1:nb
    t(n+1) = t(n) + rr0 * (1 + v(n));
end
t = t(t + 0.55 <= sim.secs - 1/sim.srate);      % the beat of sim_ecg ends at +0.55 s
hb.t  = t;
hb.rr = diff(t);
hb.a  = a(1:numel(t) - 1);
end
