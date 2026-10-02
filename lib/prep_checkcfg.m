function prep_checkcfg(cfg)
% PREP_CHECKCFG  Validate parameter values before a batch starts.
%
% prep_config rejects unknown names; this checks the values, so a mistake
% stops the batch at the start rather than midway or in the output.

    function req(cond, id, msg, varargin)
        if ~cond, error(['prep_checkcfg:' id], msg, varargin{:}); end
    end
    function tf = num(v, lo, hi)          % numeric scalar in [lo, hi]
        tf = isnumeric(v) && isscalar(v) && isfinite(v) && v >= lo && v <= hi;
    end
    function tf = posOrEmpty(v)
        tf = isempty(v) || (num(v, 0, Inf) && v > 0);
    end

%% Paths
req(isfolder(cfg.inDir), 'noInDir', 'cfg.inDir does not exist: %s', cfg.inDir);
req(ischar(cfg.fileExt) || isstring(cfg.fileExt), 'fileExt', ...
    'cfg.fileExt must be a pattern such as ''*.set''.');

%% Positive values or []
for f = {'srate','hpAnalysis','hpICA','lp','lineFreq','epochThresh','epochProbSD'}
    req(posOrEmpty(cfg.(f{1})), f{1}, 'cfg.%s must be a positive scalar, or [].', f{1});
end

%% Filter bands
if ~isempty(cfg.hpAnalysis) && ~isempty(cfg.hpICA)
    req(cfg.hpICA >= cfg.hpAnalysis, 'hpOrder', ...
        'cfg.hpICA (%g Hz) is below cfg.hpAnalysis (%g Hz); the ICA copy needs the stronger high-pass.', ...
        cfg.hpICA, cfg.hpAnalysis);
end
if ~isempty(cfg.lp) && ~isempty(cfg.hpAnalysis)
    req(cfg.lp > cfg.hpAnalysis, 'passband', ...
        'cfg.lp (%g Hz) must be above cfg.hpAnalysis (%g Hz).', cfg.lp, cfg.hpAnalysis);
end
if ~isempty(cfg.srate)
    nyq = cfg.srate / 2;
    req(isempty(cfg.lp) || cfg.lp < nyq, 'lpNyquist', ...
        'cfg.lp (%g Hz) must be below Nyquist (%g Hz at cfg.srate %g).', cfg.lp, nyq, cfg.srate);
    req(isempty(cfg.lineFreq) || cfg.lineFreq < nyq, 'lineNyquist', ...
        ['cfg.lineFreq (%g Hz) is at or above Nyquist (%g Hz at cfg.srate %g), so the\n' ...
         'mains cannot be removed. Raise cfg.srate or set cfg.lineFreq = [].'], ...
        cfg.lineFreq, nyq, cfg.srate);
end

%% Fractions
for f = {'minLocFrac','maxBadFrac','chanCorr','icaThresh','qcIcsMargin'}
    v = cfg.(f{1});
    req(num(v, 0, 1), 'fraction', 'cfg.%s must be a scalar between 0 and 1 (got %s).', f{1}, mat2str(v));
end
req(num(cfg.epochMaxRejFrac, 0, 1) && cfg.epochMaxRejFrac > 0, 'epochMaxRejFrac', ...
    'cfg.epochMaxRejFrac must be a fraction in (0, 1].');
req(num(cfg.qcTraceSecs, 0, Inf) && cfg.qcTraceSecs > 0, 'qcTraceSecs', ...
    'cfg.qcTraceSecs must be a positive number of seconds.');

%% ICA and component rules
% Class names are checked against the classifier at run time; here, the shape.
req(ismember(lower(cfg.icaType), {'runica','picard'}), 'icaType', ...
    'cfg.icaType must be ''runica'' or ''picard'' (got ''%s'').', cfg.icaType);
req(ismember(lower(cfg.icaMode), {'subtract','flag'}), 'icaMode', ...
    'cfg.icaMode must be ''subtract'' or ''flag'' (got ''%s'').', cfg.icaMode);
req(iscellstr(cfg.icaRemove) || isstring(cfg.icaRemove), 'icaRemove', ...
    'cfg.icaRemove must be a cell array or string array of ICLabel class names.');

tc = cfg.icaThreshClass;
req(isempty(tc) || (iscell(tc) && size(tc, 2) == 2), 'icaThreshClass', ...
    'cfg.icaThreshClass must be {} or {class, threshold} rows, e.g. {''Muscle'', 0.5}.');
for k = 1:size(tc, 1)
    req((ischar(tc{k, 1}) || isstring(tc{k, 1})) && num(tc{k, 2}, 0, 1), 'icaThreshClass', ...
        'cfg.icaThreshClass row %d must be a class name and a threshold between 0 and 1.', k);
end
for f = {'ecgCorr','icaSingleChan'}
    v = cfg.(f{1});
    req(isempty(v) || (num(v, 0, 1) && v > 0), 'icRule', ...
        'cfg.%s must be a value in (0, 1], or [] to switch the rule off (got %s).', f{1}, mat2str(v));
end
for f = {'nonEEG','nonEEGTypes','ecgChannels'}
    v = cfg.(f{1});
    req(isempty(v) || iscellstr(v) || isstring(v) || ischar(v), 'patterns', ...
        'cfg.%s must be a cell array of label patterns, e.g. {''*ECG*''}.', f{1});
end

%% Reference and montage
r = cfg.reref;
req(isempty(r) || ischar(r) || isstring(r) || iscellstr(r), 'reref', ...
    'cfg.reref must be [] for average, ''none'', or a channel label / cell array of labels.');
req(isempty(cfg.chanlocFile) || isfile(cfg.chanlocFile), 'chanlocFile', ...
    'cfg.chanlocFile does not exist: %s', cfg.chanlocFile);
req(isempty(cfg.renameChans) || (iscell(cfg.renameChans) && size(cfg.renameChans, 2) == 2), ...
    'renameChans', 'cfg.renameChans must be an N-by-2 cell array, {old,new} per row.');

%% Epoching
useEvents = ~isempty(cfg.events);
useFixed  = ~isempty(cfg.epochLength);
req(~(useEvents && useFixed), 'epochMode', ...
    'cfg.events and cfg.epochLength are both set; clear the one you did not mean.');
if useEvents
    req(iscell(cfg.events) || isstring(cfg.events), 'events', ...
        'cfg.events must be a cell or string array of event types.');
    req(isnumeric(cfg.window) && numel(cfg.window) == 2 && cfg.window(2) > cfg.window(1), ...
        'window', 'cfg.window must be [start stop] in seconds, stop > start.');
end
if useFixed
    req(posOrEmpty(cfg.epochLength), 'epochLength', ...
        'cfg.epochLength must be a positive scalar in seconds, or [].');
    req(num(cfg.epochOverlap, 0, 1) && cfg.epochOverlap < 1, 'epochOverlap', ...
        'cfg.epochOverlap must be a fraction in [0, 1).');
end
% The window is in seconds and the baseline in milliseconds; pop_rmbase
% silently does nothing when the baseline falls outside the epoch.
if (useEvents || useFixed) && ~isempty(cfg.baseline)
    req(isnumeric(cfg.baseline) && numel(cfg.baseline) == 2, 'baseline', ...
        'cfg.baseline must be [start stop] in MILLISECONDS, or [].');
    if useEvents, win = cfg.window; else, win = [0 cfg.epochLength]; end
    req(cfg.baseline(1) >= win(1)*1000 - 1e-9 && cfg.baseline(2) <= win(2)*1000 + 1e-9, ...
        'baselineRange', ...
        ['cfg.baseline [%g %g] ms falls outside the epoch [%g %g] s (the baseline is in\n' ...
         'ms, the epoch in s). Fixed-length epochs start at 0: use cfg.baseline = [].'], ...
        cfg.baseline(1), cfg.baseline(2), win(1), win(2));
end

%% Flags
for f = {'asrForChannelDetection','interpolate','overwrite','icaReproducible', ...
         'recursive','epochReject','icaHeartbeat'}
    v = cfg.(f{1});
    req(islogical(v) && isscalar(v), 'flag', 'cfg.%s must be true or false.', f{1});
end
if cfg.epochReject
    req(~isempty(cfg.epochThresh) || ~isempty(cfg.epochProbSD), 'epochReject', ...
        'cfg.epochReject is true but cfg.epochThresh and cfg.epochProbSD are both empty.');
    req(useEvents || useFixed, 'epochReject', ...
        'cfg.epochReject needs epochs: set cfg.events or cfg.epochLength.');
end
end
