function prep_checkcfg(cfg)
% PREP_CHECKCFG  Validate parameter VALUES before a batch starts.
%
% prep_config already rejects unknown field NAMES. This checks the values, so
% a bad number surfaces here rather than forty minutes into a batch, or worse,
% as a silently wrong derivative.

    function req(cond, id, msg, varargin)
        if ~cond, error(['prep_checkcfg:' id], msg, varargin{:}); end
    end
    function tf = posScalarOrEmpty(v)
        tf = isempty(v) || (isnumeric(v) && isscalar(v) && isfinite(v) && v > 0);
    end

%% Paths
req(isfolder(cfg.inDir),  'noInDir',  'cfg.inDir does not exist: %s', cfg.inDir);
req(ischar(cfg.fileExt) || isstring(cfg.fileExt), 'fileExt', ...
    'cfg.fileExt must be a pattern such as ''*.set''.');

%% Sampling 
req(posScalarOrEmpty(cfg.srate), 'srate', ...
    'cfg.srate must be a positive scalar or [] to leave the rate unchanged.');

%% Filtering 
req(posScalarOrEmpty(cfg.hpAnalysis), 'hpAnalysis', 'cfg.hpAnalysis must be positive or [].');
req(posScalarOrEmpty(cfg.hpICA),      'hpICA',      'cfg.hpICA must be positive or [].');
req(posScalarOrEmpty(cfg.lp),         'lp',         'cfg.lp must be positive or [].');
req(posScalarOrEmpty(cfg.lineFreq),   'lineFreq',   'cfg.lineFreq must be positive or [].');

if ~isempty(cfg.hpAnalysis) && ~isempty(cfg.hpICA)
    req(cfg.hpICA >= cfg.hpAnalysis, 'hpOrder', ...
        ['cfg.hpICA (%g Hz) is below cfg.hpAnalysis (%g Hz). The ICA branch is\n' ...
         'meant to be the copy with the stronger high-pass; swapping them\n' ...
         'defeats the two-branch design.'], cfg.hpICA, cfg.hpAnalysis);
end
if ~isempty(cfg.lp) && ~isempty(cfg.hpAnalysis)
    req(cfg.lp > cfg.hpAnalysis, 'passband', ...
        'cfg.lp (%g Hz) must be above cfg.hpAnalysis (%g Hz).', cfg.lp, cfg.hpAnalysis);
end
if ~isempty(cfg.srate)
    nyq = cfg.srate / 2;
    if ~isempty(cfg.lp)
        req(cfg.lp < nyq, 'lpNyquist', ...
            'cfg.lp (%g Hz) must be below Nyquist (%g Hz at cfg.srate %g).', ...
            cfg.lp, nyq, cfg.srate);
    end
    if ~isempty(cfg.lineFreq)
        req(cfg.lineFreq < nyq, 'lineNyquist', ...
            ['cfg.lineFreq (%g Hz) is at or above Nyquist (%g Hz at cfg.srate %g),\n' ...
             'so the mains component is aliased and cannot be removed. Raise\n' ...
             'cfg.srate or set cfg.lineFreq = [].'], cfg.lineFreq, nyq, cfg.srate);
    end
end

%% Fractions
for f = {'minLocFrac','maxBadFrac','chanCorr','icaThresh'}
    v = cfg.(f{1});
    req(isnumeric(v) && isscalar(v) && v >= 0 && v <= 1, 'fraction', ...
        'cfg.%s must be a scalar between 0 and 1 (got %s).', f{1}, mat2str(v));
end

%% ICA --------------------------------------------------------------------
req(ismember(lower(cfg.icaType), {'runica','picard'}), 'icaType', ...
    'cfg.icaType must be ''runica'' or ''picard'' (got ''%s'').', cfg.icaType);
req(ismember(lower(cfg.icaMode), {'subtract','flag'}), 'icaMode', ...
    'cfg.icaMode must be ''subtract'' or ''flag'' (got ''%s'').', cfg.icaMode);

% The class names themselves are checked against the classifier at run time,
% since only then is its class list known. Here, only the shape.
req(iscellstr(cfg.icaRemove) || isstring(cfg.icaRemove), 'icaRemove', ...
    'cfg.icaRemove must be a cell array or string array of ICLabel class names.');

%% Reference
r = cfg.reref;
req(isempty(r) || ischar(r) || isstring(r) || iscellstr(r), 'reref', ...
    ['cfg.reref must be [] for average, ''none'' to leave the data alone, ' ...
     'or a channel label / cell array of labels.']);

%% Montage
if ~isempty(cfg.chanlocFile)
    req(isfile(cfg.chanlocFile), 'chanlocFile', ...
        'cfg.chanlocFile does not exist: %s', cfg.chanlocFile);
end
if ~isempty(cfg.renameChans)
    req(iscell(cfg.renameChans) && size(cfg.renameChans,2) == 2, 'renameChans', ...
        'cfg.renameChans must be an N-by-2 cell array, {old,new} per row.');
end

%% Epoching
useEvents = ~isempty(cfg.events);
useFixed  = ~isempty(cfg.epochLength);

% Time-locked and fixed-length epoching are two choices, not a fallback
% order: a config asking for both has a mistake in it, and picking one
% silently would hide which.
req(~(useEvents && useFixed), 'epochMode', ...
    ['cfg.events and cfg.epochLength are both set, which asks for\n' ...
     'time-locked and fixed-length epoching at the same time.\n' ...
     'Clear whichever one you did not mean.']);

if useEvents
    req(iscell(cfg.events) || isstring(cfg.events), 'events', ...
        'cfg.events must be a cell or string array of event types.');
    req(isnumeric(cfg.window) && numel(cfg.window) == 2 && cfg.window(2) > cfg.window(1), ...
        'window', 'cfg.window must be [start stop] in seconds, stop > start.');
end

if useFixed
    req(posScalarOrEmpty(cfg.epochLength), 'epochLength', ...
        'cfg.epochLength must be a positive scalar in seconds, or [].');
    req(isnumeric(cfg.epochOverlap) && isscalar(cfg.epochOverlap) && ...
        cfg.epochOverlap >= 0 && cfg.epochOverlap < 1, 'epochOverlap', ...
        ['cfg.epochOverlap must be a fraction in [0, 1). An overlap of 1\n' ...
         'would step nothing between epochs and never reach the end.']);
end

% The epoch spans cfg.window when time-locked and [0 cfg.epochLength] when
% fixed, so the baseline has to be checked against whichever applies.
if (useEvents || useFixed) && ~isempty(cfg.baseline)
    req(isnumeric(cfg.baseline) && numel(cfg.baseline) == 2, 'baseline', ...
        'cfg.baseline must be [start stop] in MILLISECONDS, or [].');
    if useEvents, win = cfg.window; else, win = [0 cfg.epochLength]; end
    % window is seconds, baseline is milliseconds. An easy mix-up, and
    % pop_rmbase does nothing rather than complain.
    req(cfg.baseline(1) >= win(1)*1000 - 1e-9 && ...
        cfg.baseline(2) <= win(2)*1000 + 1e-9, 'baselineRange', ...
        ['cfg.baseline [%g %g] ms falls outside the epoch [%g %g] s.\n' ...
         'Note the epoch is in SECONDS and the baseline in MILLISECONDS.\n' ...
         'Fixed-length epochs start at 0, so the default [-200 0] does not\n' ...
         'fit one: set cfg.baseline = [] to skip baseline correction.'], ...
         cfg.baseline(1), cfg.baseline(2), win(1), win(2));
end

%% Epoch Rejection
req(posScalarOrEmpty(cfg.epochThresh), 'epochThresh', ...
    'cfg.epochThresh must be a positive scalar in uV, or [].');
req(posScalarOrEmpty(cfg.epochProbSD), 'epochProbSD', ...
    'cfg.epochProbSD must be a positive scalar in SD, or [].');
req(isnumeric(cfg.epochMaxRejFrac) && isscalar(cfg.epochMaxRejFrac) && ...
    cfg.epochMaxRejFrac > 0 && cfg.epochMaxRejFrac <= 1, 'epochMaxRejFrac', ...
    'cfg.epochMaxRejFrac must be a fraction in (0, 1].');

%% QC Figures
req(isnumeric(cfg.qcTraceSecs) && isscalar(cfg.qcTraceSecs) && cfg.qcTraceSecs > 0, ...
    'qcTraceSecs', 'cfg.qcTraceSecs must be a positive number of seconds.');
req(isnumeric(cfg.qcIcsMargin) && isscalar(cfg.qcIcsMargin) && ...
    cfg.qcIcsMargin >= 0 && cfg.qcIcsMargin <= 1, 'qcIcsMargin', ...
    'cfg.qcIcsMargin must be a probability margin in [0, 1].');

%% Flags
for f = {'asrForChannelDetection','interpolate','overwrite','icaReproducible', ...
         'recursive','epochReject'}
    v = cfg.(f{1});
    req(islogical(v) && isscalar(v), 'flag', ...
        'cfg.%s must be true or false.', f{1});
end

% After the flags loop, so cfg.epochReject is known to be a real logical.
% Rejection with nothing to reject on is a contradiction that would
% otherwise surface as a warning on every subject in the batch.
if cfg.epochReject
    req(~isempty(cfg.epochThresh) || ~isempty(cfg.epochProbSD), 'epochReject', ...
        ['cfg.epochReject is true but both cfg.epochThresh and\n' ...
         'cfg.epochProbSD are empty, so no epoch could ever be rejected.']);
    req(~isempty(cfg.events) || ~isempty(cfg.epochLength), 'epochReject', ...
        ['cfg.epochReject needs epochs: set cfg.events or cfg.epochLength,\n' ...
         'or turn the rejection off.']);
end
end
