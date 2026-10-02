function m = sim_eval(procFile, clean, cont, art, cfg, bands)
% SIM_EVAL  Compare a preprocessed dataset with its clean ground truth.
%
%   m = sim_eval(procFile, clean, cont, art, cfg, bands)
%
% procFile is the pipeline output, clean the ground truth, cont the
% contaminated input, art the injected artifact ([] for the clean
% condition), cfg the pipeline settings, bands the frequency bands.
%
% Truth and input get the same band-pass, channels and reference as the
% output (sim_match), so the comparison measures artifact removal only.
%
%   r_median                 median over channels of r(output, truth)
%   snr_before_db/after_db   truth power over error power, input and output
%   artifact_removed_pct     100 * (1 - error power after / before)
%   pow_err_db_<band>        10*log10(output / truth) band power
%   dar, dtabr, bsi, dasym   stroke measures (_true and _out): delta/alpha,
%                            (delta+theta)/(alpha+beta), pairwise brain
%                            symmetry index (1-25 Hz), delta asymmetry
%                            (L-R)/(L+R) over homologous pairs

P = pop_loadset('filename', procFile);
assert(P.trials == 1, 'sim_eval:epoched', 'sim_eval compares continuous data; the output is epoched.');
assert(P.pnts == clean.pnts, 'sim_eval:length', ...
    'Output has %d samples, ground truth %d. Was cfg.srate set?', P.pnts, clean.pnts);
[ok, keep] = ismember({P.chanlocs.labels}, {clean.chanlocs.labels});
assert(all(ok), 'sim_eval:labels', 'Output has channels the ground truth lacks.');

G = sim_match(clean.data, clean.srate, keep, cfg);
C = sim_match(cont.data,  clean.srate, keep, cfg);
Y = double(P.data);

%% Similarity and artifact suppression
m.r_median = median(arrayfun(@(i) pearson(Y(i,:), G(i,:)), 1:size(G, 1)));
pG   = sum(G.^2, 'all');
eIn  = sum((C - G).^2, 'all');
eOut = sum((Y - G).^2, 'all');
m.snr_before_db = 10*log10(pG / eIn);                 % Inf for the clean condition
m.snr_after_db  = 10*log10(pG / eOut);
m.artifact_removed_pct = NaN;
if ~isempty(art) && eIn > 0                           % 0 if all affected channels were rejected
    m.artifact_removed_pct = 100 * (1 - eOut / eIn);
end

%% Spectra
[sY, f] = welch(Y, clean.srate);
sG      = welch(G, clean.srate);
for b = bands(:)'
    sel = f >= b.range(1) & f < b.range(2);
    m.(['pow_err_db_' b.name]) = 10*log10(sum(mean(sY(sel, :), 2)) / sum(mean(sG(sel, :), 2)));
end
vG = stroke_measures(sG, f, {P.chanlocs.labels}, bands);
vY = stroke_measures(sY, f, {P.chanlocs.labels}, bands);
names = {'dar', 'dtabr', 'bsi', 'dasym'};
for k = 1:numel(names)
    m.([names{k} '_true']) = vG(k);
    m.([names{k} '_out'])  = vY(k);
end
end

function [p, f] = welch(X, srate)
% Per-channel spectrum (frequencies x channels), 2 s Hann windows, 50% overlap.
n = 2 * srate;
[p, f] = pwelch(X', 0.5 - 0.5*cos(2*pi*(0:n-1)'/n), n/2, n, srate);
end

function v = stroke_measures(pc, f, labs, bands)
% [DAR, DTABR, pdBSI, delta asymmetry] from per-channel spectra.
bp  = @(name) sum(pc(f >= bands(strcmp({bands.name}, name)).range(1) & ...
                     f <  bands(strcmp({bands.name}, name)).range(2), :), 1);
dlt = bp('delta'); tht = bp('theta'); alp = bp('alpha'); bet = bp('beta');
dar   = mean(dlt) / mean(alp);
dtabr = (mean(dlt) + mean(tht)) / (mean(alp) + mean(bet));

% Homologous pairs: odd label (left) with the next even one (right), e.g.
% F3-F4, T7-T8; pairs with a rejected channel are skipped.
[L, Rt] = deal([]);
for i = 1:numel(labs)
    tok = regexp(labs{i}, '^(\D+)(\d+)$', 'tokens', 'once');
    if isempty(tok) || mod(str2double(tok{2}), 2) == 0, continue, end
    j = find(strcmp(labs, sprintf('%s%d', tok{1}, str2double(tok{2}) + 1)), 1);
    if ~isempty(j), L(end+1) = i; Rt(end+1) = j; end %#ok<AGROW>
end
if isempty(L)
    v = [dar dtabr NaN NaN];
    return
end
sel   = f >= 1 & f <= 25;
bsi   = mean(abs((pc(sel, Rt) - pc(sel, L)) ./ (pc(sel, Rt) + pc(sel, L))), 'all');
dasym = (sum(dlt(L)) - sum(dlt(Rt))) / (sum(dlt(L)) + sum(dlt(Rt)));
v = [dar dtabr bsi dasym];
end

function r = pearson(a, b)
c = corrcoef(a, b);
r = c(1, 2);
end
