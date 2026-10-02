function [EEG, alpha] = sim_inject(EEG, artifact, snrDb)
% SIM_INJECT  EEG + alpha * artifact, with alpha set by a target SNR.
%
%   [EEG, alpha] = sim_inject(EEG, artifact, snrDb)
%
% SNR is 10*log10(P_eeg / P_artifact), power summed over all channels and
% samples after removing the mean of each channel. Defining severity this way
% rather than by a fixed gain makes a level mean the same thing whatever
% the amplitude of the artifact itself or the montage.
%
% ARTIFACT is channels x samples, or 1 x samples to add the same signal to
% every channel (line noise, for example).

X = EEG.data;
A = artifact;
if isrow(A), A = repmat(A, size(X, 1), 1); end
assert(isequal(size(A), size(X)), 'sim_inject:size', ...
    'Artifact is %dx%d, data is %dx%d.', size(A), size(X));

pEeg = sum((X - mean(X, 2)).^2, 'all');
pArt = sum((A - mean(A, 2)).^2, 'all');
assert(pArt > 0, 'sim_inject:zeroArtifact', 'The artifact has no power.');

alpha = sqrt(pEeg / (pArt * 10^(snrDb/10)));
EEG.data = X + alpha * A;
end
