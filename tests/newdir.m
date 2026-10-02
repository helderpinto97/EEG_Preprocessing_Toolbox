function d = newdir()
% NEWDIR  A fresh empty folder for a test to write into.
d = tempname;
mkdir(d);
end
