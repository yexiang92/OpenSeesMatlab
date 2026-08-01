classdef GuiBuilder
    %GUIBUILDER Minimal helper for in-window ImGui controls in Polyscope.
    %
    %   Wraps the low-level bundled ImGui calls used by the viewer
    %   enableGui() callbacks. The helper is intentionally small; add more
    %   widgets as needed.

    methods (Static)

        function begin(name, pos, size)
            % Position and size are defaults, not per-frame constraints.
            % Using Always here resets a resized right-hand panel on every
            % frame and makes its resize handle appear ineffective.
            cond = int32(polyscope.ImGui.get_constant('ImGuiCond_FirstUseEver'));
            if nargin >= 2 && ~isempty(pos)
                polyscope.ImGui.SetNextWindowPos(pos, cond);
            end
            if nargin >= 3 && ~isempty(size)
                polyscope.ImGui.SetNextWindowSize(size, cond);
            end
            polyscope.ImGui.Begin(name);
        end

        function beginDockedRight(name, rightTop, size)
            % Keep the main control window attached to the viewport's right
            % edge while leaving its left resize handle fully interactive.
            always = int32(polyscope.ImGui.get_constant('ImGuiCond_Always'));
            firstUse = int32(polyscope.ImGui.get_constant('ImGuiCond_FirstUseEver'));
            polyscope.ImGui.SetNextWindowPos(rightTop, always, [1, 0]);
            if nargin >= 3 && ~isempty(size)
                polyscope.ImGui.SetNextWindowSize(size, firstUse);
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

        function colorKey(label, col, idSuffix, inlineBefore)
            % Compact, read-only color swatch followed by its meaning.
            if nargin < 3 || isempty(idSuffix)
                idSuffix = regexprep(char(string(label)), '\W+', '_');
            end
            if nargin < 4, inlineBefore = false; end
            col = double(col(:)).';
            if numel(col) == 3, col(4) = 1; end
            if inlineBefore
                polyscope.ImGui.SameLine(0, 10);
            end
            polyscope.ImGui.ColorButton(['##color_key_' char(string(idSuffix))], ...
                col, int32(0), [16, 16]);
            polyscope.ImGui.SameLine(0, 5);
            polyscope.ImGui.AlignTextToFramePadding();
            polyscope.ImGui.Text(char(string(label)));
        end

        function val = inputText(label, val)
            [~, val] = polyscope.ImGui.InputText(label, val);
        end

        function val = inputInt(label, val, step, stepFast)
            if nargin < 3, step = 1; end
            if nargin < 4, stepFast = 100; end
            [~, val] = polyscope.ImGui.InputInt(label, val, step, stepFast);
        end

        function [changed, val] = editableIntChoice(label, val, choices, choiceLabel)
            % Numeric entry plus a dropdown of IDs which actually exist.
            % A value not present in choices is retained when typed manually.
            if nargin < 4 || isempty(choiceLabel), choiceLabel = 'Existing IDs'; end
            oldVal = double(val);
            [inputChanged, raw] = polyscope.ImGui.InputInt(label, ...
                int32(round(oldVal)), int32(1), int32(100));
            val = double(raw);
            changed = logical(inputChanged);

            choices = unique(double(choices(:)), 'stable');
            choices = choices(isfinite(choices));
            if isempty(choices), return; end
            marker = strfind(char(label), '##');
            if isempty(marker)
                suffix = regexprep(char(label), '\W+', '_');
            else
                suffix = char(label(marker(1) + 2:end));
            end
            comboId = [char(choiceLabel) '##existing_' suffix];
            preview = sprintf('%g', val);
            if polyscope.ImGui.BeginCombo(comboId, preview)
                for i = 1:numel(choices)
                    selected = (choices(i) == val);
                    [clicked, ~] = polyscope.ImGui.Selectable(sprintf('%g', choices(i)), selected);
                    if clicked
                        val = choices(i);
                        changed = true;
                    end
                end
                polyscope.ImGui.EndCombo();
            end
        end

        function val = inputFloat3(label, val)
            if nargin < 2 || isempty(val)
                val = [0, 0, 0];
            end
            [~, val] = polyscope.ImGui.InputFloat3(label, double(val(:)).');
        end

        function open = collapsingHeader(label, flags)
            if nargin < 2, flags = 0; end
            firstUse = int32(polyscope.ImGui.get_constant('ImGuiCond_FirstUseEver'));
            polyscope.ImGui.SetNextItemOpen(false, firstUse);
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
            txt = char(string(txt));
            try
                % A small colored glyph is clearer and lighter than ImGui's
                % trailing SeparatorText rule. Geometric Unicode glyphs are
                % more reliable than color emoji in the bundled font atlas.
                accentIdx = polyscope.ImGui.get_constant('ImGuiCol_CheckMark');
                accent = polyscope.ImGui.GetStyleColorVec4(accentIdx);
                polyscope.ImGui.TextColored(accent, char(9670)); % ◆
                polyscope.ImGui.SameLine(0, 6);
                polyscope.ImGui.Text(txt);
            catch
                % Never fall back to SeparatorText: it adds the unwanted
                % heavy rule on the right-hand side of the caption.
                polyscope.ImGui.Text(['>  ' txt]);
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
