function [EEG, qc] = prep_chanlocs(EEG, cfg)
% PREP_CHANLOCS  Attach and verify electrode positions.
%
% Order: rename labels (cfg.renameChans), then positions from cfg.chanlocFile,
% or else a template lookup for channels without positions. Stops the file
% when fewer than cfg.minLocFrac of the channels are located, since
% clean_rawdata and ICLabel quietly do worse without positions.

qc.chanloc_source = "existing";

for k = 1:size(cfg.renameChans, 1)
    idx = strcmpi({EEG.chanlocs.labels}, cfg.renameChans{k, 1});
    if any(idx), [EEG.chanlocs(idx).labels] = deal(cfg.renameChans{k, 2}); end
end
if ~isempty(cfg.renameChans), EEG = eeg_checkset(EEG); end

% 'lookup' matches by label; 'load' would replace chanlocs in file order.
if ~isempty(cfg.chanlocFile)
    if ~isfile(cfg.chanlocFile)
        error('prep_chanlocs:noFile', 'Montage file not found: %s', cfg.chanlocFile);
    end
    before = {EEG.chanlocs.labels};
    EEG    = pop_chanedit(EEG, 'lookup', cfg.chanlocFile);
    assert(isequal({EEG.chanlocs.labels}, before), 'prep_chanlocs:relabelled', ...
           'Montage load altered the channel labels; positions cannot be trusted.');
    qc.chanloc_source = "file";
elseif ~isempty(cfg.lookupTemplate) && ~all(has_coords(EEG))
    EEG = pop_chanedit(EEG, 'lookup', find_template(cfg.lookupTemplate));
    qc.chanloc_source = "template";
end

located = has_coords(EEG);
qc.nchan_with_locs = sum(located);
qc.frac_with_locs  = qc.nchan_with_locs / EEG.nbchan;
if qc.frac_with_locs < cfg.minLocFrac
    noloc = {EEG.chanlocs(~located).labels};
    error('prep_chanlocs:missing', ...
        ['Only %d/%d channels have coordinates (need >= %.0f%%). Without positions: %s\n' ...
         'Use cfg.renameChans if the labels do not match the template, or cfg.chanlocFile.'], ...
        qc.nchan_with_locs, EEG.nbchan, 100*cfg.minLocFrac, strjoin(noloc(1:min(end, 10)), ', '));
end
if qc.chanloc_source == "template"
    warning('prep_chanlocs:template', ...
        ['%s: using TEMPLATE electrode positions. Adequate for artifact\n' ...
         'rejection and ICLabel; a known error source for source\n' ...
         'reconstruction. Use measured positions there if you have them.'], EEG.setname);
end
end

%% Auxiliary functions
function tf = has_coords(EEG)
% X, Y and Z all present (EEGLAB leaves them empty when unset) and finite.
tf = arrayfun(@(c) ~isempty(c.X) && ~isempty(c.Y) && ~isempty(c.Z) && ...
                   all(isfinite([c.X c.Y c.Z])), EEG.chanlocs);
end

function f = find_template(name)
% The template ships with DIPFIT.
f = which(name);
if ~isempty(f), return, end
dipfitDir = fileparts(which('pop_dipfit_settings'));
cand = {fullfile(dipfitDir, 'standard_BEM', 'elec', name), fullfile(dipfitDir, 'standard_BESA', name)};
k = find(cellfun(@isfile, cand), 1);
if ~isempty(k), f = cand{k}; return, end
error('prep_chanlocs:noTemplate', ...
    'Could not find the montage template "%s" (it ships with DIPFIT); or set cfg.chanlocFile.', name);
end
