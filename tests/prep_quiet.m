function varargout = prep_quiet(fcn, varargin) %#ok<INUSD>
% PREP_QUIET  Call FCN(varargin{:}) with console output discarded.
%
%   prep_quiet(@prep_epoch, EEG, cfg)           no outputs
%   [EEG, qc] = prep_quiet(@prep_epoch, EEG, cfg)
%
% EEGLAB's pop_ functions print several lines per call, and the suite makes
% hundreds of those calls, so without this the pass and fail markers are
% buried in thousands of lines of chatter.
%
% Warnings are NOT silenced, deliberately. Several tests assert on warnings
% raised through exactly this path, and folding suppression in here would
% make those verifyWarning calls pass without anything having been raised.
% Silence warnings at the call site, with prep_nowarn, when a test wants it.
%
% fcn and varargin are read inside the evaluated string, which checkcode
% cannot see, hence the suppression on the signature.

if nargout == 0
    evalc('feval(fcn, varargin{:})');
else
    out = cell(1, nargout);
    [~, out{:}] = evalc('feval(fcn, varargin{:})');
    varargout = out;
end
end
