classdef (Abstract) OpenSeesMatlabBase < ops.core.Commands
    %OPENSEESMATLABBASE Compatibility base for the OpenSeesMatlab toolbox.
    %
    % Compatibility inheritance point for the toolbox command layer.

    methods
        function obj = OpenSeesMatlabBase(mexName, mexDir)
            if nargin < 1 || isempty(mexName)
                mexName = "OpenSeesMATLAB";
            end
            if nargin < 2 || isempty(mexDir)
                mexDir = "";
            end

            obj@ops.core.Commands(mexName, mexDir);
        end
    end
end
