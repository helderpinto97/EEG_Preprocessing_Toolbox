function H = src_heads(src)
% SRC_HEADS  The two head models of the source validation, in MNI mm.
%
%   H = src_heads(src)
%
%   H.ny   HArtMuT New York Head (5-tissue FEM): makes the data, and is the
%          'matched' inverse. Cortical sources only, fixed normal orientation.
%   H.bst  ICBM152 3-shell OpenMEEG BEM of Brainstorm, cortex of 15002
%          vertices with normal orientation, EGI HydroCel 256 electrodes.
%          The 'template' inverse; it ships with SEREEGA.
%
% Each has L (channels x sources), pos (sources x 3), chan (channels x 3),
% and labels (channel labels). Both are ICBM152 based, so MNI positions
% can be compared directly.

if ~exist('pop_chanedit', 'file')               % lf_generate_fromhartmut needs EEGLAB
    addpath(fullfile(fileparts(src.sereegaPath), 'eeglab'));
    evalc('eeglab nogui');
end
if ~exist('lf_generate_fromhartmut', 'file'), addpath(genpath(src.sereegaPath)); end
if ~exist('HArtMuT_NYhead_small.mat', 'file'), addpath(src.hartmutPath); end

%% New York Head
evalc('lf = lf_generate_fromhartmut(''NYhead_small'');');
cort = find(startsWith(lf.atlas, 'Brain') & ~strcmp(lf.atlas, 'Brain_Subcortical'));
ori  = lf.orientation(cort, :);
H.ny.L      = sum(lf.leadfield(:, cort, :) .* reshape(ori, 1, [], 3), 3);
H.ny.pos    = lf.pos(cort, :);
c = lf.chanlocs;
H.ny.chan   = [-[c.Y]' [c.X]' [c.Z]'];      % EEGLAB axes (X front, Y left) to MNI
H.ny.labels = {c.labels};

%% Brainstorm ICBM152 BEM
t  = load(fullfile(src.bstDir, 'subjectimage_T1.mat'), 'SCS', 'NCS');
hm = load(fullfile(src.bstDir, 'headmodel_surf_openmeeg.mat'), 'Gain', 'GridLoc', 'GridOrient');
ch = load(fullfile(src.bstDir, 'channel_GSN_HydroCel_256_E1.mat'), 'Channel');
% SCS (m) to MNI (mm) through the MRI frame, as Brainstorm cs_convert does
mri2scs = [t.SCS.R t.SCS.T/1000; 0 0 0 1];
mri2mni = [t.NCS.R t.NCS.T/1000; 0 0 0 1];
M = mri2mni / mri2scs;
toMni = @(P) 1000 * (P * M(1:3, 1:3)' + M(1:3, 4)');
G = hm.Gain;                                 % orientation and gain both in SCS
H.bst.L      = G(:, 1:3:end) .* hm.GridOrient(:, 1)' + ...
               G(:, 2:3:end) .* hm.GridOrient(:, 2)' + ...
               G(:, 3:3:end) .* hm.GridOrient(:, 3)';
H.bst.pos    = toMni(hm.GridLoc);
H.bst.chan   = toMni(cell2mat({ch.Channel.Loc})');
H.bst.labels = {ch.Channel.Name};
end
