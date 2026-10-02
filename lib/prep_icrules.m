function [flag, reason, qc] = prep_icrules(EEG, ECG, cfg)
% PREP_ICRULES  Flag components ICLabel is known to miss.
%
%   [flag, reason, qc] = prep_icrules(EEG, ECG, cfg)
%
% ECG is what prep_ecgref returned, or []. FLAG is 1-by-nIC logical, REASON
% names the rule that fired ("" where none did). The rules ([] or false = off):
%
%   cfg.ecgCorr        cardiac: |r| with a recorded ECG channel
%   cfg.icaHeartbeat   cardiac, used only without an ECG channel: the
%                      component beats like a heart (prep_ic_heartbeat)
%   cfg.icaSingleChan  electrode artifact: this share of the map power on
%                      one channel (pops, loose contact)

nIC    = size(EEG.icaweights, 1);
flag   = false(1, nIC);
reason = strings(1, nIC);
qc = struct('n_ic_ecg', 0, 'n_ic_heartbeat', 0, 'n_ic_singlechan', 0);
if nIC == 0, return, end

useEcg = ~isempty(ECG) && ~isempty(cfg.ecgCorr);
useHb  = isempty(ECG) && cfg.icaHeartbeat;
if useEcg || useHb
    % EEGLAB usually holds the activations already.
    if isequal(size(EEG.icaact), [nIC, EEG.pnts])
        act = double(EEG.icaact);
    else
        act = (EEG.icaweights * EEG.icasphere) * double(EEG.data(EEG.icachansind, :));
    end
end

if useEcg
    % Brought to the rate and band of the EEG here, where it is used.
    if ECG.srate ~= EEG.srate, ECG = pop_resample(ECG, EEG.srate); end
    ECG = pop_eegfiltnew(ECG, 'locutoff', cfg.hpAnalysis, 'hicutoff', cfg.lp);
    if ECG.pnts ~= EEG.pnts
        warning('prep_icrules:ecgLength', ...
            'ECG has %d samples and the EEG %d; the ECG rule is skipped.', ECG.pnts, EEG.pnts);
    else
        r   = max(abs(prep_rowcorr(act, double(ECG.data))), [], 2)';
        hit = r >= cfg.ecgCorr;
        [flag, reason] = mark(flag, reason, hit, compose("ECG r=%.2f", r));
        qc.n_ic_ecg = sum(hit);
    end
end

if useHb
    [hit, f] = prep_ic_heartbeat(act, EEG.srate);
    [flag, reason] = mark(flag, reason, hit, compose("heartbeat %.0f bpm", f.bpm));
    qc.n_ic_heartbeat = sum(hit);
end

if ~isempty(cfg.icaSingleChan)
    w2    = EEG.icawinv .^ 2;
    share = max(w2, [], 1) ./ sum(w2, 1);
    hit   = share >= cfg.icaSingleChan;
    [flag, reason] = mark(flag, reason, hit, compose("one channel %.2f", share));
    qc.n_ic_singlechan = sum(hit);
end
end

function [flag, reason] = mark(flag, reason, hit, text)
% The first rule that fires names the component.
new  = hit(:)' & ~flag;
text = text(:)';
reason(new) = text(new);
flag = flag | hit(:)';
end
