function pre = prep_snapshot(EEG, cfg)
% PREP_SNAPSHOT  What the QC figures need from the data before filtering.
%
% The mean spectrum, cfg.qcTraceSecs of traces starting a quarter of the way
% in (the opening seconds are often atypical), and the event times in the
% same clock. Never a copy of the whole recording. A failure costs a panel.

pre = struct('f', [], 'psd', [], 'srate', EEG.srate, 'lineFreq', cfg.lineFreq, ...
             'snippet', [], 'labels', {{}}, 't0', 0);
pre.events = struct('type', {}, 'time', {});

try
    [pre.f, P] = prep_psd(EEG.data, EEG.srate);
    pre.psd = mean(P, 2);
catch ME
    warning('prep_snapshot:failed', 'Could not compute the pre-filter PSD: %s', ME.message);
end

try
    D  = reshape(EEG.data, size(EEG.data, 1), []);   % cut before converting
    n  = size(D, 2);
    w  = min(round(cfg.qcTraceSecs * EEG.srate), n);
    i0 = max(1, min(round(0.25*n), n - w + 1));
    pre.snippet = double(D(:, i0:i0+w-1));
    pre.labels  = {EEG.chanlocs.labels};
    pre.t0      = (i0 - 1) / EEG.srate;
catch ME
    warning('prep_snapshot:snippet', 'Could not keep a trace segment: %s', ME.message);
end

% Taken now: epoching and resampling later rewrite the latencies.
try
    if ~isempty(EEG.event) && isfield(EEG.event, 'latency')
        pre.events = struct('type', {EEG.event.type}, ...
                            'time', num2cell((double([EEG.event.latency]) - 1) / EEG.srate));
    end
catch ME
    warning('prep_snapshot:events', 'Could not keep the event times: %s', ME.message);
end
end
