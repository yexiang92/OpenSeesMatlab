classdef FEMModelAdapter
    %FEMMODELADAPTER Adapt canonical FEMData MODEL values for visualization.
    %
    % FEMData preserves raw OpenSees elemental-load vectors. Model plotters
    % use a display-oriented ten-column representation; this adapter performs
    % that conversion without changing the stored cross-language data.

    methods (Static)
        function loads = loadsForPlotting(loads)
            if ~isstruct(loads) || ~isfield(loads, 'Element') || ...
                    ~isstruct(loads.Element) || ~isfield(loads.Element, 'Beam')
                return;
            end
            beam = loads.Element.Beam;
            if ~isstruct(beam) || ~isfield(beam, 'Values') || isempty(beam.Values)
                return;
            end

            % Legacy files already contain display-oriented rows.
            if ~isfield(beam, 'ClassTags') || isempty(beam.ClassTags)
                return;
            end

            raw = double(beam.Values);
            if isvector(raw), raw = reshape(raw, 1, []); end
            classTags = double(beam.ClassTags(:));
            n = min(size(raw, 1), numel(classTags));
            values = zeros(n, 10);
            for i = 1:n
                values(i, :) = plotter.utils.FEMModelAdapter.beamLoadRow( ...
                    raw(i, :), classTags(i));
            end
            loads.Element.Beam.Values = values;
            loads.Element.Beam.Types = { ...
                'wya','wyb','wza','wzb','wxa','wxb', ...
                'xa','xb','classTag','rawColumnCount'};
        end
    end

    methods (Static, Access = private)
        function out = beamLoadRow(raw, classTag)
            raw = double(raw(:).');
            wya = 0; wyb = 0; wza = 0; wzb = 0;
            wxa = 0; wxb = 0; xa = 0; xb = 1;

            switch classTag
                case 3   % Beam2dUniformLoad: [wy, wx]
                    wya = plotter.utils.FEMModelAdapter.value(raw, 1); wyb = wya;
                    wxa = plotter.utils.FEMModelAdapter.value(raw, 2); wxb = wxa;
                    count = 2;
                case 5   % Beam3dUniformLoad: [wy, wz, wx]
                    wya = plotter.utils.FEMModelAdapter.value(raw, 1); wyb = wya;
                    wza = plotter.utils.FEMModelAdapter.value(raw, 2); wzb = wza;
                    wxa = plotter.utils.FEMModelAdapter.value(raw, 3); wxb = wxa;
                    count = 3;
                case 4   % Beam2dPointLoad: [Py, x/L, Px]
                    wya = plotter.utils.FEMModelAdapter.value(raw, 1);
                    xa = plotter.utils.FEMModelAdapter.value(raw, 2);
                    wxa = plotter.utils.FEMModelAdapter.value(raw, 3);
                    xb = -10000; count = 3;
                case 6   % Beam3dPointLoad: [Py, Pz, x/L, Px]
                    wya = plotter.utils.FEMModelAdapter.value(raw, 1);
                    wza = plotter.utils.FEMModelAdapter.value(raw, 2);
                    xa = plotter.utils.FEMModelAdapter.value(raw, 3);
                    wxa = plotter.utils.FEMModelAdapter.value(raw, 4);
                    xb = -10000; count = 4;
                case 12  % Beam2dPartialUniformLoad
                    wya = plotter.utils.FEMModelAdapter.value(raw, 1);
                    wyb = plotter.utils.FEMModelAdapter.value(raw, 2);
                    wxa = plotter.utils.FEMModelAdapter.value(raw, 3);
                    wxb = plotter.utils.FEMModelAdapter.value(raw, 4);
                    xa = plotter.utils.FEMModelAdapter.value(raw, 5);
                    xb = plotter.utils.FEMModelAdapter.value(raw, 6);
                    count = 6;
                case 121 % Beam3dPartialUniformLoad
                    wya = plotter.utils.FEMModelAdapter.value(raw, 1);
                    wza = plotter.utils.FEMModelAdapter.value(raw, 2);
                    wxa = plotter.utils.FEMModelAdapter.value(raw, 3);
                    xa = plotter.utils.FEMModelAdapter.value(raw, 4);
                    xb = plotter.utils.FEMModelAdapter.value(raw, 5);
                    wyb = plotter.utils.FEMModelAdapter.value(raw, 6);
                    wzb = plotter.utils.FEMModelAdapter.value(raw, 7);
                    wxb = plotter.utils.FEMModelAdapter.value(raw, 8);
                    count = 8;
                otherwise
                    count = nnz(isfinite(raw));
            end
            out = [wya, wyb, wza, wzb, wxa, wxb, xa, xb, classTag, count];
        end

        function out = value(values, index)
            if index <= numel(values) && isfinite(values(index))
                out = values(index);
            else
                out = 0;
            end
        end
    end
end
