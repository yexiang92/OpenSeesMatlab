function installOpenSeesMatlab(toolboxFile)
%INSTALLOPENSEESMATLAB Install the toolbox package for this platform.

    if nargin < 1
        platformTag = string(computer("arch"));
        if ~any(platformTag == ["win64", "maca64"])
            error("OpenSeesMatlab:UnsupportedPlatform", ...
                "Only Windows x86-64 and macOS Apple silicon are supported.");
        end

        candidates = dir("OpenSeesMatlab-*-" + platformTag + ".mltbx");
        if numel(candidates) ~= 1
            error("OpenSeesMatlab:ToolboxPackageNotFound", ...
                "Expected exactly one OpenSeesMatlab-*-%s.mltbx file in %s.", ...
                platformTag, pwd);
        end
        toolboxFile = fullfile(candidates(1).folder, candidates(1).name);
    end

    toolboxFile = string(toolboxFile);
    assert(isfile(toolboxFile), "Toolbox package does not exist: %s", toolboxFile);

    tbxs = matlab.addons.toolbox.installedToolboxes;

    % Match by Name or Guid
    targetName = "OpenSeesMatlab";

    for i = 1:numel(tbxs)
        if strcmp(string(tbxs(i).Name), targetName)
            fprintf("Uninstalling old version: %s %s\n", tbxs(i).Name, tbxs(i).Version);
            matlab.addons.toolbox.uninstallToolbox(tbxs(i));
        end
    end

    fprintf("Installing toolbox from: %s\n", toolboxFile);
    info = matlab.addons.toolbox.installToolbox(toolboxFile, true);

    fprintf("Installed toolbox: %s %s\n", info.Name, info.Version);
end
