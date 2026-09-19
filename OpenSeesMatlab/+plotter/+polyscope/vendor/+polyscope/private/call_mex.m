function varargout = call_mex(varargin)
%CALL_MEX Internal helper to dispatch to the polyscope_mex MEX file.
    persistent pendingUpdateChecked
    if isempty(pendingUpdateChecked)
        pendingUpdateChecked = true;
        privateDir = fileparts(mfilename('fullpath'));
        pendingMex = fullfile(privateDir, ['polyscope_mex.pending.' mexext]);
        activeMex = fullfile(privateDir, ['polyscope_mex.' mexext]);
        if isfile(pendingMex)
            try
                movefile(pendingMex, activeMex, 'f');
                clear polyscope_mex
            catch
                % The active binary may still be loaded by this MATLAB
                % session. Leave the pending file for the next session.
            end
        end
    end
    [varargout{1:nargout}] = polyscope_mex(varargin{:});
end
