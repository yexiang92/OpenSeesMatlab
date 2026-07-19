function initialize(ps, opts, varargin)
%INITIALIZE Apply shared Polyscope viewer defaults.
%
%   plotter.polyscope.initialize(ps, opts, is2D, phase) configures settings
%   common to all Polyscope views. Use phase="pre" before ps.init(), and
%   phase="post" after ps.init().

    if nargin < 2 || isempty(opts)
        opts = struct();
    end
    is2D = false;
    if nargin >= 3 && (islogical(varargin{1}) || isnumeric(varargin{1}))
        is2D = logical(varargin{1});
    end
    if nargin >= 4 && ~isempty(varargin{2})
        phase = varargin{2};
    elseif nargin >= 3 && ~isempty(varargin{1}) && ...
            (ischar(varargin{1}) || isstring(varargin{1}))
        phase = varargin{1};
    else
        phase = "post";
    end

    ssaa = 2;
    if isfield(opts, 'polyscope') && isfield(opts.polyscope, 'ssaaFactor')
        ssaa = opts.polyscope.ssaaFactor;
    end
    ssaa = max(1, min(4, round(double(ssaa))));
    programName = programName_(opts);
    psOpts = struct();
    if isfield(opts, 'polyscope') && isstruct(opts.polyscope)
        psOpts = opts.polyscope;
    end

    switch lower(char(string(phase)))
        case 'pre'
            tryCall_(ps, 'set_program_name', programName);
            tryCall_(ps, 'set_use_prefs_file', false);
            tryCall_(ps, 'set_allow_headless_backends', true);
            tryCall_(ps, 'set_print_prefix', '[OpenSeesMatlab] ');
            tryCall_(ps, 'set_errors_throw_exceptions', true);
            applyProgramOptions_(ps, psOpts);
            % tryCall_(ps, 'set_ground_plane_mode', 'shadow_only');
            tryCall_(ps, 'set_ground_plane_mode', 'none');
            tryCall_(ps, 'set_ui_scale', 1.2);
            tryCall_(ps, 'set_autocenter_structures', false);

        case 'post'
            tryCall_(ps, 'set_program_name', programName);
            tryCall_(ps, 'set_SSAA_factor', ssaa);
            tryCall_(ps, 'set_ssaa_factor', ssaa);
            applyProgramOptions_(ps, psOpts);
            applyUiStyle_();
            if ~is2D
                tryCall_(ps, 'set_up_dir', 'z_up', false);
            end
            if isfield(opts, 'polyscope')
                if isfield(opts.polyscope, 'backgroundColor')
                    tryCall_(ps, 'set_background_color', opts.polyscope.backgroundColor);
                end
                if ~isHeadless_(opts)
                    if isfield(opts.polyscope, 'maximize') && opts.polyscope.maximize
                        [w, h] = screenSize_();
                        tryCall_(ps, 'set_window_size', w, h);
                    elseif isfield(opts.polyscope, 'windowSize') && ...
                            numel(opts.polyscope.windowSize) >= 2 && ...
                            ~(isfield(opts.polyscope, 'maximize') && opts.polyscope.maximize)
                        tryCall_(ps, 'set_window_size', ...
                            opts.polyscope.windowSize(1), opts.polyscope.windowSize(2));
                    end
                end
            end
        case 'postupdate'
            tryCall_(ps, 'set_program_name', programName);
            applyProgramOptions_(ps, psOpts);
    end
end

function applyUiStyle_()
    % Apply one shared, compact visual language to every viewer. This runs
    % once after ImGui initialization rather than on every callback frame.
    try
        style = polyscope.ImGui.GetStyle();
        style.WindowPadding = [12, 10];
        style.WindowRounding = 7;
        style.ChildRounding = 5;
        style.PopupRounding = 5;
        style.FramePadding = [8, 4];
        style.FrameRounding = 4;
        style.ItemSpacing = [8, 6];
        style.ItemInnerSpacing = [6, 4];
        style.IndentSpacing = 18;
        style.ScrollbarSize = 13;
        style.ScrollbarRounding = 7;
        style.GrabMinSize = 10;
        style.GrabRounding = 4;
        style.TabRounding = 4;
        style.SeparatorTextPadding = [10, 4];
    catch
        % Older bundled MEX builds may not expose every style field.
    end
end

function applyProgramOptions_(ps, psOpts)
    if ~isstruct(psOpts), return; end
    if isfield(psOpts, 'maxFps')
        tryCall_(ps, 'set_max_fps', max(1, double(psOpts.maxFps)));
    end
    if isfield(psOpts, 'enableVsync')
        tryCall_(ps, 'set_enable_vsync', logical(psOpts.enableVsync));
    end
    if isfield(psOpts, 'alwaysRedraw')
        tryCall_(ps, 'set_always_redraw', logical(psOpts.alwaysRedraw));
    end
    if isfield(psOpts, 'frameTickLimitFpsMode')
        tryCall_(ps, 'set_frame_tick_limit_fps_mode', char(string(psOpts.frameTickLimitFpsMode)));
    end
end

function name = programName_(opts)
    authorStr = 'by Yexiang Yan';
    name = ['OpenSeesMatlab - ' authorStr];
    if isfield(opts, 'polyscope') && isfield(opts.polyscope, 'programName') && ...
            ~isempty(opts.polyscope.programName)
        name = char(string(opts.polyscope.programName));
        return;
    end
    if isfield(opts, 'general') && isfield(opts.general, 'title')
        titleStr = strtrim(char(string(opts.general.title)));
        if ~isempty(titleStr) && ~strcmpi(titleStr, 'auto')
            name = ['OpenSeesMatlab | ' titleStr ' - ' authorStr];
        end
    end
end

function tryCall_(obj, methodName, varargin)
    try
        obj.(methodName)(varargin{:});
    catch
    end
end

function tf = isHeadless_(opts)
    tf = false;
    if isfield(opts, 'polyscope') && isfield(opts.polyscope, 'headless')
        tf = logical(opts.polyscope.headless);
    end
end

function [w, h] = screenSize_()
    try
        monitors = get(0, 'MonitorPositions');
        if isempty(monitors)
            monitors = get(0, 'ScreenSize');
        end
        widths = monitors(:, 3);
        heights = monitors(:, 4);
        [~, idx] = max(widths .* heights);
        w = max(800, round(widths(idx)));
        h = max(600, round(heights(idx)));
    catch
        w = 1920;
        h = 1080;
    end
end
