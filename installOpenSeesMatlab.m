function installOpenSeesMatlab(toolboxFile)
%INSTALL_OPENSEESMATLAB Uninstall old version and install new version.

    if nargin < 1
        toolboxFile = "OpenSeesMatlab.mltbx";
    end

    tbxs = matlab.addons.toolbox.installedToolboxes;

    % Match by Name or Guid
    targetName = "OpenSeesMatlab";

    for i = 1:numel(tbxs)
        if strcmp(string(tbxs(i).Name), targetName)
            fprintf("Uninstalling old version: %s %s\n", tbxs(i).Name, tbxs(i).Version);
            matlab.addons.toolbox.uninstallToolbox(tbxs(i));
        end
    end

    fprintf("Installing new toolbox from: %s\n", toolboxFile);
    info = matlab.addons.toolbox.installToolbox(toolboxFile, true);

    fprintf("Installed toolbox: %s %s\n", info.Name, info.Version);
end