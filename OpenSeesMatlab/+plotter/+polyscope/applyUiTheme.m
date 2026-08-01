function applyUiTheme(theme)
%APPLYUITHEME Apply the shared modern ImGui/ImPlot panel theme.

    theme = lower(char(string(theme)));
    isDark = strcmp(theme, 'dark');
    try
        if isDark
            polyscope.ImGui.StyleColorsDark();
        else
            polyscope.ImGui.StyleColorsLight();
        end

        style = polyscope.ImGui.GetStyle();
        style.WindowPadding = [12, 10];
        style.WindowRounding = 8;
        style.ChildRounding = 6;
        style.PopupRounding = 6;
        style.FramePadding = [8, 4];
        style.FrameRounding = 5;
        style.ItemSpacing = [8, 6];
        style.ItemInnerSpacing = [6, 4];
        style.IndentSpacing = 18;
        style.ScrollbarSize = 13;
        style.ScrollbarRounding = 7;
        style.GrabMinSize = 10;
        style.GrabRounding = 5;
        style.TabRounding = 5;
        style.SeparatorTextPadding = [10, 4];

        if isDark
            accent = [0.43, 0.48, 1.00, 1.00];
            hover = [0.50, 0.55, 1.00, 1.00];
            active = [0.34, 0.39, 0.90, 1.00];
            button = accent;
            buttonHover = hover;
            buttonActive = active;
            selected = accent;
            frame = [0.12, 0.13, 0.18, 1.00];
            panel = [0.075, 0.08, 0.11, 0.98];
            header = [0.25, 0.28, 0.58, 0.72];
            border = [0.30, 0.32, 0.42, 0.62];
        else
            % Airy neutral surfaces with restrained blue feedback. Stronger
            % blue is reserved for small indicators instead of large fills.
            accent = [0.30, 0.59, 0.84, 1.00];
            hover = [0.80, 0.90, 0.975, 1.00];
            active = [0.68, 0.83, 0.95, 1.00];
            button = [0.90, 0.95, 0.99, 1.00];
            buttonHover = [0.82, 0.91, 0.98, 1.00];
            buttonActive = [0.72, 0.85, 0.96, 1.00];
            selected = [0.78, 0.89, 0.975, 1.00];
            frame = [0.965, 0.972, 0.982, 1.00];
            panel = [0.995, 0.997, 1.00, 0.985];
            header = [0.91, 0.95, 0.985, 0.92];
            border = [0.82, 0.85, 0.89, 0.62];
        end

        setColor_('ImGuiCol_WindowBg', panel);
        setColor_('ImGuiCol_ChildBg', panel);
        setColor_('ImGuiCol_PopupBg', panel);
        setColor_('ImGuiCol_Border', border);
        setColor_('ImGuiCol_FrameBg', frame);
        setColor_('ImGuiCol_FrameBgHovered', header);
        setColor_('ImGuiCol_FrameBgActive', accent);
        setColor_('ImGuiCol_CheckMark', accent);
        setColor_('ImGuiCol_SliderGrab', accent);
        setColor_('ImGuiCol_SliderGrabActive', hover);
        setColor_('ImGuiCol_Button', button);
        setColor_('ImGuiCol_ButtonHovered', buttonHover);
        setColor_('ImGuiCol_ButtonActive', buttonActive);
        setColor_('ImGuiCol_Header', header);
        setColor_('ImGuiCol_HeaderHovered', hover);
        setColor_('ImGuiCol_HeaderActive', active);
        setColor_('ImGuiCol_ResizeGrip', [accent(1:3), 0.35]);
        setColor_('ImGuiCol_ResizeGripHovered', hover);
        setColor_('ImGuiCol_ResizeGripActive', active);
        setColor_('ImGuiCol_TabHovered', hover);
        setColor_('ImGuiCol_TabSelected', selected);
        setColor_('ImGuiCol_NavCursor', accent);

        if isDark
            polyscope.ImPlot.StyleColorsDark();
        else
            polyscope.ImPlot.StyleColorsLight();
        end
    catch
        % Keep compatibility with older MEX builds during staged upgrades.
    end
end

function setColor_(name, rgba)
    try
        idx = polyscope.ImGui.get_constant(name);
        polyscope.ImGui.SetStyleColor(idx, rgba);
    catch
    end
end
