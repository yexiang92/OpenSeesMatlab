function loadExamples(ops, modelName)
        % loadExamples Load example models into the OpenSees MATLAB interface.
        %
        %   ops.loadExamples(modelName) loads the specified example model.
        %
        %   Parameters
        %   ----------
        %   modelName : string or char
        %       Name of the example model to load. Supported values are:
        %       'Frame3D', 'ArchBridge', 'ArchBridge2', 'CableStayedBridge', ...
        %       'SuspensionBridge', 'TrussBridge', 'Dam'.

        modelName = char(string(modelName));
        
        switch lower(modelName)
            case 'frame3d'
                demos.Frame3D(ops);
            case 'archbridge'
                demos.ArchBridge(ops);
            case 'archbridge2'
                demos.ArchBridge2(ops);
            case 'cablestayedbridge'
                demos.CableStayedBridge(ops);
            case 'suspensionbridge'
                demos.SuspensionBridge(ops);
            case 'trussbridge'
                demos.TrussBridge(ops);
            case 'dam'
                demos.Dam(ops);
            otherwise
                error(['Unsupported model name: %s. Supported models are: ', ...
                    'Frame3D, ArchBridge, ArchBridge2, CableStayedBridge, ', ...
                    'SuspensionBridge, TrussBridge, Dam'], modelName);
        end
    end