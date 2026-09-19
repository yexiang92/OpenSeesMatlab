classdef OpenSeesNexus < nexus.Commands
    %OPENSEESNEXUS MATLAB interface to the OpenSeesBindings runtime.
    %
    %   ops = OpenSeesNexus() selects the native bundle for the current
    %   MATLAB platform and creates the standalone OpenSees command interface.
    %
    %       ops = OpenSeesNexus();
    %       ops.model("basic", "-ndm", 2, "-ndf", 2);
    %       ops.node(1, 0.0, 0.0);
    %
    %   ops = OpenSeesNexus(mexName, mexDirectory) accepts explicit native
    %   overrides for development. Normal installed use requires neither.

    methods
        function obj = OpenSeesNexus(mexName, mexDirectory)
            arguments
                mexName {mustBeTextScalar} = ""
                mexDirectory {mustBeTextScalar} = ""
            end
            obj@nexus.Commands(mexName, mexDirectory);
        end
    end

    methods (Static)
        function backend = setBackend(backend)
            %SETBACKEND Select serial or OpenSeesSP before construction.
            backend = nexus.setBackend(backend);
        end

        function backend = getBackend()
            %GETBACKEND Return the currently selected native backend.
            backend = nexus.getBackend();
        end

        function platform = platformKey()
            %PLATFORMKEY Return the native directory for this MATLAB host.
            platform = nexus.Runtime.platformKey();
        end
    end
end
