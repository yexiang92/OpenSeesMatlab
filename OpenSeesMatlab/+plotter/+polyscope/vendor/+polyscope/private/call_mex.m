function varargout = call_mex(varargin)
%CALL_MEX Internal helper to dispatch to the polyscope_mex MEX file.
    [varargout{1:nargout}] = polyscope_mex(varargin{:});
end
