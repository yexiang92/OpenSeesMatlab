classdef ResponseSchema
    %RESPONSESCHEMA Internal FEMData response dimension definitions.
    % Keep these rules aligned with OpenSeesMEX FEMDataCollector/Reader.

    methods (Static)
        function [dims, outCoords] = dimensions(path, value, coords, dofs)
            path = string(path);
            sz = size(value);
            dims = strings(1, ndims(value));
            outCoords = struct();

            [head, tail] = post.utils.ResponseSchema.layout(path);
            labels = [head, tail];
            % Conservative fallback for custom recorder fields: response
            % arrays are time-major and their second dimension is tagged.
            if numel(labels) < 2 && numel(sz) >= 2
                if isfield(coords, 'element') && numel(coords.element) == sz(2)
                    labels(2) = "element";
                elseif isfield(coords, 'node') && numel(coords.node) == sz(2)
                    labels(2) = "node";
                end
            end
            if numel(labels) < numel(sz) && numel(sz) >= 3
                labels(end+1:numel(sz)) = "component";
                for k = 4:numel(sz)
                    labels(k) = "location" + k;
                end
            end
            for d = 1:numel(dims)
                if d <= numel(labels)
                    label = labels(d);
                else
                    label = "dim" + d;
                end
                dims(d) = label;
                field = char(matlab.lang.makeValidName(label));
                if isfield(coords, field) && numel(coords.(field)) == sz(d)
                    outCoords.(field) = coords.(field)(:);
                elseif label == "component" && ~isempty(dofs) && numel(dofs) == sz(d)
                    outCoords.(field) = string(dofs(:));
                else
                    outCoords.(field) = (1:sz(d)).';
                end
            end
        end

        function [head, tail] = layout(path)
            p = lower(replace(string(path), "_", ""));
            head = "time";
            tail = strings(1, 0);

            if contains(p, "fibers.geometry")
                head = ["sectionGeometry", "fiber"];
                return
            end
            if contains(p, "fibers.elementsectionmap")
                head = ["element", "section"];
                return
            end

            if contains(p,"interpolatedisp")
                head=["time","interpolationPoint","component"];
                return
            end
            if contains(p,"interpolatecoords") || contains(p,"interpolatepoints")
                head=["interpolationPoint","component"];
                return
            end
            if contains(p,"interpolatecells")
                head=["interpolationCell","cellEntry"];
                return
            end

            if contains(p, "atnode")
                head = ["time", "node"];
                if contains(p, "shell") && ...
                        (contains(p, "stressatnode") || contains(p, "strainatnode"))
                    tail = "fiber";
                end
                return
            end
            if contains(p, "atgp")
                head = ["time", "element"];
                tail = "gaussPoint";
                if contains(p, "shell") && ...
                        (contains(p, "stressatgp") || contains(p, "strainatgp"))
                    tail = ["gaussPoint", "fiber"];
                end
                return
            end
            if contains(p, "nodalresponses") || ...
                    ~isempty(regexp(p, '(^|\.)(disp|vel|accel|reaction|reactionincinertia|pressure)(\.|$)', 'once'))
                head = ["time", "node"];
                return
            end
            if contains(p, "fibers.stress") || contains(p, "fibers.strain")
                head = ["time", "element"];
                tail = ["section", "fiber"];
                return
            end
            if contains(p, "sectionforces") || contains(p, "sectiondeformations")
                head = ["time", "element"];
                tail = "section";
                return
            end
            if contains(p, "sectionlocs")
                head = ["time", "element"];
                tail = ["section", "sectionLocationComponent"];
                return
            end
            if contains(p, "mvlemresponses")
                head = ["time", "element"];
                if contains(p, "fiber")
                    tail = "fiber";
                elseif contains(p, "globalforces") || contains(p, "localforces")
                    tail = "component";
                elseif contains(p, "shearforcedeformation")
                    tail = "component";
                end
                return
            end
            if contains(p, "frameresponses") || contains(p, "trussresponses") || ...
                    contains(p, "linkresponses") || contains(p, "contactresponses") || ...
                    contains(p, "elementresponses")
                head = ["time", "element"];
                return
            end

            % getElementResponse returns the selected group without its
            % FEMData container name. These response names remain unambiguous.
            if ~isempty(regexp(p, '(^|\.)(axialforce|axialdefo|stress|strain|basicforce|basicdeformation)(\.|$)', 'once'))
                head = ["time", "element"];
            end
        end
    end
end
