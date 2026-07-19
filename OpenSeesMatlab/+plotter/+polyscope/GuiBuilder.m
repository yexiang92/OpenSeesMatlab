classdef GuiBuilder
    %GUIBUILDER Minimal helper for in-window ImGui controls in Polyscope.
    %
    %   Wraps the low-level bundled ImGui calls used by the viewer
    %   enableGui() callbacks. The helper is intentionally small; add more
    %   widgets as needed.

    methods (Static)

        function begin(name, pos, size)
            cond = int32(polyscope.ImGui.get_constant('ImGuiCond_Always'));
            if nargin >= 2 && ~isempty(pos)
                polyscope.ImGui.SetNextWindowPos(pos, cond);
            end
            if nargin >= 3 && ~isempty(size)
                polyscope.ImGui.SetNextWindowSize(size, cond);
            end
            polyscope.ImGui.Begin(name);
        end

        function finish()
            polyscope.ImGui.End();
        end

        function header(title)
            %HEADER Draw the shared viewer panel heading.
            polyscope.ImGui.Text(['OpenSeesMatlab | ' char(string(title))]);
            polyscope.ImGui.Separator();
        end

        function val = sliderInt(label, val, vMin, vMax)
            [~, val] = polyscope.ImGui.SliderInt(label, val, vMin, vMax);
        end

        function val = sliderFloat(label, val, vMin, vMax)
            [~, val] = polyscope.ImGui.SliderFloat(label, val, vMin, vMax);
        end

        function val = checkbox(label, val)
            [~, val] = polyscope.ImGui.Checkbox(label, val);
        end

        function clicked = button(label)
            clicked = polyscope.ImGui.Button(label);
        end

        function clicked = smallButton(label)
            clicked = polyscope.ImGui.SmallButton(label);
        end

        function val = combo(label, val, items)
            if isstring(items), items = cellstr(items); end
            val = max(1, min(numel(items), val));
            preview = items{val};
            if polyscope.ImGui.BeginCombo(label, preview)
                for i = 1:numel(items)
                    selected = (i == val);
                    [clicked, ~] = polyscope.ImGui.Selectable(items{i}, selected);
                    if clicked
                        val = i;
                    end
                end
                polyscope.ImGui.EndCombo();
            end
        end

        function [changed, col] = colorEdit3(label, col)
            if nargin < 2 || isempty(col)
                col = [1, 1, 1];
            end
            [changed, col] = polyscope.ImGui.ColorEdit3(label, col);
        end

        function val = inputText(label, val)
            [~, val] = polyscope.ImGui.InputText(label, val);
        end

        function val = inputInt(label, val, step, stepFast)
            if nargin < 3, step = 1; end
            if nargin < 4, stepFast = 100; end
            [~, val] = polyscope.ImGui.InputInt(label, val, step, stepFast);
        end

        function val = inputFloat3(label, val)
            if nargin < 2 || isempty(val)
                val = [0, 0, 0];
            end
            [~, val] = polyscope.ImGui.InputFloat3(label, double(val(:)).');
        end

        function open = collapsingHeader(label, flags)
            if nargin < 2, flags = 0; end
            open = polyscope.ImGui.CollapsingHeader(label, flags);
        end

        function open = treeNode(label, flags)
            if nargin < 2, flags = 0; end
            open = polyscope.ImGui.TreeNode(label, flags);
        end

        function treePop()
            polyscope.ImGui.TreePop();
        end

        function separator()
            polyscope.ImGui.Separator();
        end

        function subtitle(txt)
            try
                polyscope.ImGui.SeparatorText(txt);
            catch
                polyscope.ImGui.Spacing();
                polyscope.ImGui.TextDisabled(txt);
                polyscope.ImGui.Separator();
            end
        end

        function label(txt)
            polyscope.ImGui.Text(txt);
        end

        function labelDisabled(txt)
            polyscope.ImGui.TextDisabled(txt);
        end

        function sameLine()
            polyscope.ImGui.SameLine();
        end

        function newLine()
            polyscope.ImGui.NewLine();
        end

    end
end
