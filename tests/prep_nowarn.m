function c = prep_nowarn(varargin)
% PREP_NOWARN  Silence warnings until the returned object goes out of scope.
%
%   c = prep_nowarn()                    all warnings
%   c = prep_nowarn('prep_epoch:foo')    one identifier
%
% Keep the return value. The restore happens when it is cleared, so
% dropping it silences nothing:
%
%   c = prep_nowarn('prep_epoch:highRejection');   %#ok<NASGU>
%
% Separate from prep_quiet on purpose. Quieting console output and
% suppressing warnings are different decisions, and a test that asserts on a
% warning needs the first without the second.

if isempty(varargin), varargin = {'all'}; end
old = warning('off', varargin{:});
c   = onCleanup(@() warning(old));
end
