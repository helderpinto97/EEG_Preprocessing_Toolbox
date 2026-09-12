function [EEG, qc] = prep_chanlocs(EEG, cfg)
% PREP_CHANLOCS  Attach and verify electrode positions.

qc.chanloc_source = "existing";

%% 1. rename channels if the montage uses a non-standard scheme ----------
if ~isempty(cfg.renameChans)
    labels = {EEG.chanlocs.labels};
    for k = 1:size(cfg.renameChans, 1)
        idx = strcmpi(labels, cfg.renameChans{k,1});
        if any(idx)
            [EEG.chanlocs(idx).labels] = deal(cfg.renameChans{k,2});
        end
    end
    EEG = eeg_checkset(EEG);
end

%% Electrodes Position
% 'lookup', not 'load'. pop_chanedit's 'load' runs readlocs and replaces
% the whole chanlocs array in file order, with no label matching and no
% count check, so a full-cap montage misaligns against the reduced channel
% set left after the non-EEG drop and overwrites the labels too. 'lookup'
% intersects on lowercased labels and copies only the coordinate fields.
% If the montage file carries no labels nothing matches and the
% verification below fails, which beats a silent misalignment.
if ~isempty(cfg.chanlocFile)
    if ~isfile(cfg.chanlocFile)
        error('prep_chanlocs:noFile', ...
              'Montage file not found: %s', cfg.chanlocFile);
    end
    before = {EEG.chanlocs.labels};
    EEG    = pop_chanedit(EEG, 'lookup', cfg.chanlocFile);
    assert(isequal({EEG.chanlocs.labels}, before), 'prep_chanlocs:relabelled', ...
           'Montage load altered the channel labels; positions cannot be trusted.');
    qc.chanloc_source = "file";

%% Otherwise template lookup, but only for channels that lack coords 
elseif ~isempty(cfg.lookupTemplate) && n_with_coords(EEG) < EEG.nbchan
    tmpl = find_template(cfg.lookupTemplate);
    EEG  = pop_chanedit(EEG, 'lookup', tmpl);
    qc.chanloc_source = "template";
end

%% Verification 
qc.nchan_with_locs = n_with_coords(EEG);
qc.frac_with_locs  = qc.nchan_with_locs / EEG.nbchan;

if qc.frac_with_locs < cfg.minLocFrac
    noloc = {EEG.chanlocs(~has_coords(EEG)).labels};
    error('prep_chanlocs:missing', ...
        ['Only %d/%d channels have coordinates (need >= %.0f%%).\n' ...
         'Without positions: %s\n' ...
         'Either the labels do not match the lookup template (common with\n' ...
         'BioSemi and EGI caps - use cfg.renameChans), or you need to\n' ...
         'supply the montage explicitly via cfg.chanlocFile.'], ...
         qc.nchan_with_locs, EEG.nbchan, 100*cfg.minLocFrac, ...
         strjoin(noloc(1:min(end,10)), ', '));
end

if qc.chanloc_source == "template"
    warning('prep_chanlocs:template', ...
        ['%s: using TEMPLATE electrode positions. Adequate for artifact\n' ...
         'rejection and ICLabel; a known error source for source\n' ...
         'reconstruction. Use measured positions there if you have them.'], ...
         EEG.setname);
end
end

%% Auxiliary Functions
function tf = has_coords(EEG)
% A channel counts as located only if X, Y and Z are all present and finite.
% EEGLAB leaves these empty rather than NaN when unset, hence the isempty.
tf = arrayfun(@(c) ~isempty(c.X) && ~isempty(c.Y) && ~isempty(c.Z) && ...
                    all(isfinite([c.X c.Y c.Z])), EEG.chanlocs);
end

function n = n_with_coords(EEG)
n = sum(has_coords(EEG));
end

function f = find_template(name)
f = which(name);
if ~isempty(f), return; end

dipfitDir = fileparts(which('pop_dipfit_settings'));
cand = { fullfile(dipfitDir, 'standard_BEM', 'elec', name), ...
         fullfile(dipfitDir, 'standard_BESA', name) };
for k = 1:numel(cand)
    if isfile(cand{k}), f = cand{k}; return; end
end
error('prep_chanlocs:noTemplate', ...
    ['Could not find the montage template "%s".\n' ...
     'It ships with the DIPFIT plugin; check DIPFIT is installed, or\n' ...
     'set cfg.chanlocFile to your own montage instead.'], name);
end
