function R = run_src_validation(overrides)
% RUN_SRC_VALIDATION  Stage 1 of the source reconstruction validation.
%
%   R = run_src_validation()
%   R = run_src_validation(struct('seeds', 1, 'nBoot', 50))   quick check
%
% Static Gaussian O-information of parcel triplets, recovered from scalp
% EEG through a forward and an inverse model, against the true value that
% follows from the source covariance. No background, no artifacts and no
% preprocessing yet: only forward model, inverse model and parcellation.
% See tests/EEG Source Reconstruction Validation Plan.md, section 12.
%
% Output in validation/results/source/<timestamp>_src_initial/:
%   metrics.csv    one row per seed, montage, atlas, head, method, condition
%   distance.csv   null condition: O-information against parcel distance
%   setup.mat      parameters, parcels, triplets, electrode mismatch
%   summary.png/.pdf  see src_figure

if nargin < 1, overrides = struct(); end
here = fileparts(mfilename('fullpath'));
addpath(here);
src = src_config(overrides);

stamp  = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
outDir = fullfile(src.outRoot, [stamp '_' src.runName]);
mkdir(outDir);

H = src_heads(src);
T = src.secs * src.srate;
R = table();
D = table();
setup = struct('src', src);

for ai = 1:numel(src.atlases)
    A = src_atlas(src.atlases{ai}, src, H);
    nPar = numel(A.names);
    [trips, allTrip, tripDist] = src_triplets(A, src, H.bst.pos);
    [P, srcIdx, off, nPatch] = src_patches(A, H, src);
    setup.(src.atlases{ai}) = struct('names', {A.names}, 'centre', A.centre, ...
        'trips', trips, 'srcOffset_mm', off, 'patchSize', nPatch);

    for mi = fieldnames(src.montages)'
        labels = src.montages.(mi{1});
        [ok, rowNy] = ismember(labels, H.ny.labels);
        assert(all(ok), 'run_src_validation:labels', 'New York Head lacks %s.', ...
               strjoin(labels(~ok), ', '));
        % Template lead field at the 10-10 sites, interpolated from the
        % HydroCel electrodes (that cap has no electrode at Cz). mis is the
        % distance to the nearest HydroCel electrode, for the record.
        mis = min(pdist2(H.ny.chan(rowNy, :), H.bst.chan), [], 2);
        W   = src_interp(H.bst.chan, H.ny.chan(rowNy, :), mean(H.bst.pos, 1));
        setup.(src.atlases{ai}).(['mismatch_' mi{1}]) = mis;
        m  = numel(labels);
        Hc = eye(m) - 1/m;
        Lf = Hc * H.ny.L(rowNy, :) * P;            % forward, one patch per parcel
        % vtx: the inverse source at (or nearest) each true source
        inv.matched  = struct('L', Hc * H.ny.L(rowNy, :),  'lab', A.ny,  'vtx', srcIdx, 'pos', H.ny.pos);
        [~, vb] = min(pdist2(H.ny.pos(srcIdx, :), H.bst.pos), [], 2);
        inv.template = struct('L', Hc * W * H.bst.L,       'lab', A.bst, 'vtx', vb, 'pos', H.bst.pos);
        Kel = struct();                            % eLORETA does not depend on the data
        [hh, mm] = ndgrid(src.headmodels, src.methods);
        runs = [{'oracle', 'none'}; [hh(:) mm(:)]];
        for hi = src.headmodels
            Kel.(hi{1}) = src_inverse('eloreta', inv.(hi{1}).L, eye(m), src.reg, labels, inv.(hi{1}).pos);
        end

        for seed = src.seeds
          for de = src.density
            for ci = 1:numel(src.conditions)
                cond = src.conditions{ci};
                [S, Ctrue, trip] = src_sources(cond, nPar, T, trips, src, seed*100 + ci, de.amp);
                Otrue = src_oinfo3(corrcov(Ctrue), allTrip);
                Y = Lf * S;
                noise = sqrt(mean(var(Y, 0, 2)) / 10^(src.snrDb/10));
                Y = Hc * (Y + noise * randn(size(Y)));
                Cy = (Y * Y') / T;

                % The oracle uses the true sources: it checks the estimator
                % and that the bootstrap test gives no false positives by itself.
                for rr = 1:size(runs, 1)
                    hd = runs{rr, 1}; me = runs{rr, 2};
                    switch me
                        case 'none',    X = S; Xv = S;
                        case 'eloreta', K = Kel.(hd);
                        case 'lcmv',    K = src_inverse('lcmv', inv.(hd).L, Cy, src.reg, labels, inv.(hd).pos);
                    end
                    if ~strcmp(me, 'none')
                        X  = src_pc1(K, inv.(hd).lab, nPar, Cy) * Y;
                        Xv = K(inv.(hd).vtx, :) * Y;
                    end
                    [Oest, p, lo, hi95] = src_boot(X, allTrip, src.nBoot, seed);
                    sig  = p < src.alpha;
                    zero = abs(Otrue) < 1e-12;
                    t  = find(ismember(allTrip, sort(trip), 'rows'));
                    ev = eig(corrcoef(X'));
                    % How well each parcel time series follows its own source
                    rOwn = abs(diag(corr(X', S')));
                    rVtx = abs(diag(corr(Xv', S')));    % same, at the source itself

                    row = table(seed, string(mi{1}), m, string(src.atlases{ai}), nPar, ...
                        string(hd), string(me), string(de.name), string(cond), ...
                        Otrue(t), Oest(t), lo(t), hi95(t), sig(t), ...
                        sig(t) && sign(Oest(t)) == sign(Otrue(t)), ...
                        mean(sig(zero)), mean(sig(zero) & Oest(zero) > 0), ...
                        mean(sig(zero) & Oest(zero) < 0), median(Oest(zero)), ...
                        prctile(abs(Oest(zero)), 95), median(rOwn), min(rOwn(trip)), median(rVtx), ...
                        sum(ev > 1e-6 * max(ev)), max(ev) / max(min(ev), eps), mean(mis), mean(off), ...
                        'VariableNames', {'seed','montage','nchan','atlas','nparcel', ...
                        'head','method','density','condition','O_true','O_est','ci_lo','ci_hi', ...
                        'sig','sign_ok','fpr','fpr_red','fpr_syn','O0_median', ...
                        'O0_abs_p95','r_own_median','r_own_trip_min','r_vertex_median','eff_rank','cond_R', ...
                        'elec_mismatch_mm','src_offset_mm'});
                    R = [R; row]; %#ok<AGROW>

                    if strcmp(cond, 'null')
                        [~, ~, bin] = histcounts(tripDist, src.distEdges);
                        for b = unique(bin(bin > 0))'
                            in = bin == b;
                            D = [D; table(seed, string(mi{1}), string(src.atlases{ai}), ...
                                string(hd), string(me), string(de.name), ...
                                mean(src.distEdges(b:b+1)), sum(in), mean(Oest(in)), mean(sig(in)), ...
                                'VariableNames', {'seed','montage','atlas','head','method','density', ...
                                'dist_mm','n','O_mean','fpr'})]; %#ok<AGROW>
                        end
                    end
                end
                fprintf('%s %s seed %d %s %s done\n', src.atlases{ai}, mi{1}, seed, de.name, cond);
            end
          end
        end
    end
end

writetable(R, fullfile(outDir, 'metrics.csv'));
writetable(D, fullfile(outDir, 'distance.csv'));
save(fullfile(outDir, 'setup.mat'), 'setup');
src_figure(outDir);
fprintf('Results in %s\n', outDir);
end
