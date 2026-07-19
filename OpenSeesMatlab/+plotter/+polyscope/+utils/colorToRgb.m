function rgb = colorToRgb(value)
%COLORTORGB Convert a MATLAB-style colour to an Nx3 RGB double in [0,1].
%
%   Supports:
%     - numeric [r g b] (0..1 or 0..255)
%     - hex string '#RRGGBB'
%     - named colours: black, white, red, green, blue, cyan, magenta, yellow
%     - single-letter shortcuts: k, w, r, g, b, c, m, y

    if isnumeric(value) && numel(value) >= 3
        rgb = double(value(1:3));
        if any(rgb > 1)
            rgb = rgb / 255;
        end
        rgb = max(0, min(1, rgb(:).'));
        return;
    end

    txt = lower(strtrim(char(string(value))));
    named = struct( ...
        'black',   [0 0 0], ...
        'white',   [1 1 1], ...
        'red',     [1 0 0], ...
        'green',   [0 1 0], ...
        'blue',    [0 0 1], ...
        'cyan',    [0 1 1], ...
        'magenta', [1 0 1], ...
        'yellow',  [1 1 0]  ...
    );
    if isfield(named, txt)
        rgb = named.(txt);
        return;
    end

    shortNames = {'k','w','r','g','b','c','m','y'};
    longNames  = {'black','white','red','green','blue','cyan','magenta','yellow'};
    idx = find(strcmp(txt, shortNames), 1);
    if ~isempty(idx)
        rgb = named.(longNames{idx});
        return;
    end

    if startsWith(txt, '#') && strlength(txt) == 7
        vals = sscanf(txt(2:end), '%2x%2x%2x');
        if numel(vals) == 3
            rgb = double(vals(:).') / 255;
            return;
        end
    end

    % Fallback
    rgb = [0.5 0.5 0.5];
end
