function EEG = prep_testdata(varargin)
% PREP_TESTDATA  Synthetic EEG with known ground truth, for the test suite.
%
%   EEG = prep_testdata('Name', value, ...)
%
% Options
%   Labels     cellstr of channel labels (default: a 19-channel 10-20 set)
%   Secs       duration in seconds                       (default 60)
%   Srate      sampling rate                             (default 250)
%   Spatial    true  = spatially smooth fields, so clean_channels'
%                      neighbour-correlation criterion is satisfied
%              false = independent noise, much faster   (default false)
%   NSources   number of simulated sources when Spatial  (default 6)
%   LineFreq   mains frequency to inject, [] for none    (default 50)
%   Alpha      amplitude of a 10 Hz component            (default 12)
%   DupChan    [a b] make channel b a copy of a, dropping rank by 1
%   FlatHead   seconds of dead signal at the START of the recording
%   Seed       rng seed                                  (default 1)
%   Events     cellstr of event types to write, {} for none  (default {})
%   EventEvery spacing between events in seconds          (default 1)
%   EventStart latency of the first event in seconds      (default 1)
%
% Spatial=true needs the dipfit template on the path, because the fields are
% built from real electrode coordinates; without spatially plausible data,
% clean_channels rejects almost every channel and no end-to-end test can run.

p = inputParser;
p.addParameter('Labels', {'Fp1','Fp2','F7','F3','Fz','F4','F8','T7','C3','Cz', ...
                          'C4','T8','P7','P3','Pz','P4','P8','O1','O2'});
p.addParameter('Secs', 60);
p.addParameter('Srate', 250);
p.addParameter('Spatial', false);
p.addParameter('NSources', 6);
p.addParameter('LineFreq', 50);
p.addParameter('Alpha', 12);
p.addParameter('DupChan', []);
p.addParameter('FlatHead', 0);
p.addParameter('Seed', 1);
p.addParameter('Exponent', 1.5);   % aperiodic slope: power ~ 1/f^Exponent
p.addParameter('Events', {});
p.addParameter('EventEvery', 1);
p.addParameter('EventStart', 1);
p.parse(varargin{:});
o = p.Results;

rng(o.Seed);
labels = o.Labels;
n      = numel(labels);
pnts   = round(o.Secs * o.Srate);
t      = (0:pnts-1) / o.Srate;

pos = [];   % populated only for spatially generated data
if o.Spatial
    pos = template_positions(labels);
    P   = zeros(n, o.NSources);
    for j = 1:o.NSources
        c = randn(1,3); c = c / norm(c);
        P(:,j) = exp(-2 * sum((pos - c).^2, 2));   % smooth field on the scalp
    end
    S = zeros(o.NSources, pnts);
    S(1,:) = o.Alpha * sin(2*pi*10*t) .* (1 + 0.3*randn(1,pnts));
    if o.NSources > 1, S(2,:) = 6 * sin(2*pi*6*t); end
    for j = 3:o.NSources
        S(j,:) = pink_noise(1, pnts, o.Exponent, o.Srate) * 60;
    end
    X = P*S + 0.8*randn(n, pnts);
else
    X = pink_noise(n, pnts, o.Exponent, o.Srate) * 15 + o.Alpha * sin(2*pi*10*t);
end

if ~isempty(o.LineFreq)
    X = X + 5 * sin(2*pi*o.LineFreq*t);
end
if ~isempty(o.DupChan)
    X(o.DupChan(2), :) = X(o.DupChan(1), :);
end
if o.FlatHead > 0
    X(:, 1:min(pnts, round(o.FlatHead * o.Srate))) = 0;
end

EEG = eeg_emptyset();
EEG.data   = X;
EEG.srate  = o.Srate;
EEG.nbchan = n;
EEG.pnts   = pnts;
EEG.trials = 1;
EEG.xmin   = 0;
EEG.xmax   = (pnts-1) / o.Srate;
for i = 1:n
    EEG.chanlocs(i).labels = labels{i};
    EEG.chanlocs(i).type   = '';
    % Spatially generated data carries the coordinates it was generated
    % from, so topoplot-based QC can be exercised without a lookup.
    if ~isempty(pos)
        EEG.chanlocs(i).X = pos(i,1);
        EEG.chanlocs(i).Y = pos(i,2);
        EEG.chanlocs(i).Z = pos(i,3);
    end
end
% Events, cycled through Events in order at a fixed spacing, so a test can
% state the expected count per condition rather than measure it.
if ~isempty(o.Events)
    lat = round(o.EventStart * o.Srate) + 1 : round(o.EventEvery * o.Srate) : pnts;
    for k = 1:numel(lat)
        EEG.event(k).type    = o.Events{mod(k-1, numel(o.Events)) + 1};
        EEG.event(k).latency = lat(k);
        EEG.event(k).urevent = k;
        % The urevent table as well, not just the pointers into it. A file
        % loaded through pop_loadset or pop_fileio always has one, and it is
        % the only record of the original continuous latencies once
        % pop_epoch has rewritten EEG.event. A fixture without it cannot
        % exercise anything that reads back the true timing.
        EEG.urevent(k).type    = EEG.event(k).type;
        EEG.urevent(k).latency = lat(k);
    end
end

EEG.setname = 'testdata';
EEG = eeg_checkset(EEG);
end

% -------------------------------------------------------------------------
function pos = template_positions(labels)
% Unit-sphere coordinates for LABELS, from the dipfit 10-05 template.
f = which('standard_1005.elc');
if isempty(f)
    d = fileparts(which('pop_dipfit_settings'));
    f = fullfile(d, 'standard_BEM', 'elec', 'standard_1005.elc');
end
assert(isfile(f), 'prep_testdata:noTemplate', ...
    'standard_1005.elc not found; dipfit must be installed for Spatial data.');

% Cached across calls. The template is a fixed file of about 340 electrodes
% and the suite builds spatial fixtures a dozen times, so without this the
% same parse runs a dozen times for the same answer.
persistent L cachedFile
if isempty(L) || ~strcmp(cachedFile, f)
    L          = readlocs(f);
    cachedFile = f;
end

pos = zeros(numel(labels), 3);
for i = 1:numel(labels)
    j = find(strcmpi({L.labels}, labels{i}), 1);
    assert(~isempty(j), 'prep_testdata:noLabel', ...
        'Label "%s" is not in the template.', labels{i});
    pos(i,:) = [L(j).X L(j).Y L(j).Z];
end
pos = pos ./ vecnorm(pos, 2, 2);
end

% -------------------------------------------------------------------------
function X = pink_noise(nrow, npts, expo, srate)
% Noise whose power falls as 1/f^EXPO, which is what real EEG looks like.
%
% Shaped in the frequency domain rather than by filtering, so this needs no
% Signal Processing Toolbox licence. The previous fixture used a boxcar
% moving average, whose transfer function has periodic nulls, which put a
% visible comb pattern in every QC spectrum and made simulated data look
% nothing like EEG.
%
% EXPO of 1 is pink; resting EEG is usually nearer 1.5-2.5 in power.

nfft = 2^nextpow2(max(npts, 2));
nOne = floor(nfft/2) + 1;
f    = (0:nOne-1)' * srate / nfft;

amp      = zeros(nOne, 1);
amp(2:end) = 1 ./ (f(2:end) .^ (expo/2));   % power ~ amp^2 ~ 1/f^expo
amp(1)   = 0;                               % no DC

X = zeros(nrow, npts);
for k = 1:nrow
    ph    = exp(1i * 2*pi * rand(nOne, 1));
    ph(1) = 1;
    if mod(nfft, 2) == 0, ph(end) = 1; end  % Nyquist bin must be real
    H    = amp .* ph;
    full = [H; conj(H(end-1:-1:2))];        % Hermitian, so ifft is real
    x    = real(ifft(full));
    X(k,:) = x(1:npts);
end

s = std(X, 0, 2);
s(s == 0) = 1;
X = X ./ s;                                 % unit variance per channel
end
