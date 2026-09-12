function pre = prep_snapshot(EEG, cfg)
% PREP_SNAPSHOT  What the QC figures need from the data BEFORE filtering.
%
% Keeps the mean spectrum and a short segment of the traces. Not a copy of
% the whole dataset, which would roughly double peak memory for the run.
%
% The segment starts a quarter of the way in. The opening seconds of an EEG
% file are often atypical, with electrodes settling and the participant
% getting comfortable, and a trace panel showing only that is misleading.

secs = cfg.qcTraceSecs;

pre = struct('f', [], 'psd', [], 'srate', EEG.srate, 'lineFreq', cfg.lineFreq, ...
             'snippet', [], 'labels', {{}}, 't0', 0);
pre.events = struct('type', {}, 'time', {});

try
    [f, P] = prep_psd(EEG.data, EEG.srate);
    pre.f   = f;
    pre.psd = mean(P, 2);
catch ME
    % A missing spectrum costs a panel, never the recording.
    warning('prep_snapshot:failed', ...
            'Could not compute the pre-filter PSD: %s', ME.message);
end

try
    % reshape shares the buffer, so the window is cut before anything is
    % converted. Converting first would allocate a second copy of the whole
    % recording, which is what this function exists to avoid.
    D = reshape(EEG.data, size(EEG.data,1), []);
    n = size(D, 2);
    w = min(round(secs * EEG.srate), n);
    i0 = max(1, min(round(0.25*n), n - w + 1));
    pre.snippet = double(D(:, i0:i0+w-1));
    pre.labels  = {EEG.chanlocs.labels};
    pre.t0      = (i0 - 1) / EEG.srate;
catch ME
    warning('prep_snapshot:snippet', ...
            'Could not keep a trace segment: %s', ME.message);
end

% Event times in the same clock as pre.t0 and pre.snippet. Taken here, not
% read off EEG at figure time: by then pop_epoch has rewritten the latencies
% into the epoched frame and pop_resample has rescaled them. Markers from
% those sit in the wrong place, and a constant offset still looks plausible
% on a trace.
try
    if ~isempty(EEG.event) && isfield(EEG.event, 'latency')
        n  = numel(EEG.event);
        ev = struct('type', cell(1, n), 'time', cell(1, n));
        for k = 1:n
            ev(k).type = EEG.event(k).type;
            ev(k).time = (double(EEG.event(k).latency) - 1) / EEG.srate;
        end
        pre.events = ev;
    end
catch ME
    warning('prep_snapshot:events', ...
            'Could not keep the event times: %s', ME.message);
end
end
