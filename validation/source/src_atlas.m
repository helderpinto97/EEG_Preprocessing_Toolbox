function A = src_atlas(name, src, H)
% SRC_ATLAS  Parcellation of the Brainstorm cortex and of the New York Head.
%
%   A = src_atlas('dkt62' | 'coarse20', src, H)
%
%   A.names   parcel names
%   A.bst     parcel index of every Brainstorm vertex (0 = none)
%   A.ny      parcel index of every New York Head source, from the nearest
%             Brainstorm vertex (0 when that vertex is more than 10 mm away)
%   A.centre  parcel centre: the vertex nearest the parcel mean, MNI mm
%
% dkt62     Mindboggle (DKT) atlas of Brainstorm, 31 regions per hemisphere
% coarse20  the same regions merged into 10 groups per hemisphere

s = load(fullfile(src.bstDir, 'scout_Mindboggle_62.mat'), 'Scouts');
s = s.Scouts;
dkt = zeros(size(H.bst.pos, 1), 1);
for k = 1:numel(s), dkt(s(k).Vertices) = k; end
dktNames = {s.Label};

switch name
    case 'dkt62'
        A.names = dktNames;
        A.bst   = dkt;
    case 'coarse20'
        groups = {
            'dorsal frontal',    {'superiorfrontal','caudalmiddlefrontal','rostralmiddlefrontal'}
            'ventral frontal',   {'parsopercularis','parstriangularis','parsorbitalis', ...
                                  'lateralorbitofrontal','medialorbitofrontal'}
            'precentral',        {'precentral','paracentral'}
            'postcentral',       {'postcentral','supramarginal'}
            'superior parietal', {'superiorparietal','precuneus'}
            'inferior parietal', {'inferiorparietal'}
            'occipital',         {'lateraloccipital','lingual','cuneus','pericalcarine'}
            'lateral temporal',  {'superiortemporal','middletemporal','inferiortemporal', ...
                                  'transversetemporal'}
            'medial temporal',   {'fusiform','parahippocampal','entorhinal'}
            'cingulate insula',  {'caudalanteriorcingulate','rostralanteriorcingulate', ...
                                  'posteriorcingulate','isthmuscingulate','insula'}};
        region = extractBefore(dktNames, ' ');
        hemi   = extractAfter(dktNames, ' ');
        map = zeros(1, numel(dktNames));
        A.names = {};
        for h = {'L', 'R'}
            for g = 1:size(groups, 1)
                A.names{end+1} = [groups{g, 1} ' ' h{1}];
                map(ismember(region, groups{g, 2}) & strcmp(hemi, h{1})) = numel(A.names);
            end
        end
        assert(all(map > 0), 'src_atlas:unmapped', 'Unmapped region(s): %s', ...
               strjoin(dktNames(map == 0), ', '));
        A.bst = zeros(size(dkt));
        A.bst(dkt > 0) = map(dkt(dkt > 0));
    otherwise
        error('src_atlas:name', 'Unknown atlas %s.', name);
end

[d, nn] = min(pdist2(H.ny.pos, H.bst.pos), [], 2);
A.ny = A.bst(nn);
A.ny(d > 10) = 0;

n = numel(A.names);
A.centre = zeros(n, 3);
for p = 1:n
    P = H.bst.pos(A.bst == p, :);
    [~, i] = min(vecnorm(P - mean(P, 1), 2, 2));
    A.centre(p, :) = P(i, :);
end
end
