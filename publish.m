%% Build a versioned release package from the toolbox project file
%
% Notes
% -----
% - The toolbox project file is assumed to be located in:
%       OpenSeesMatlab/*.prj
% - The packaged .mltbx file is generated as:
%       OpenSeesMatlab/release/OpenSeesMatlab.mltbx
% - The copied toolbox file in the release folder is also named:
%       OpenSeesMatlab.mltbx
% - All .mlx files directly under examples/ are exported to .m files
%   into the target release examples folder, instead of being copied.
% - The utils folder is copied recursively, but .png and .mp4 files are excluded.

clc;

%% =========================
% User-specified version
% =========================
version = "3.8.0.0";   % <-- manually set toolbox version here

%% Project root
projectRoot = fileparts(mfilename("fullpath"));

%% Source paths
srcExamplesDir    = fullfile(projectRoot, "examples");
srcUtilsDir       = fullfile(srcExamplesDir, "utils");
toolboxRootDir    = fullfile(projectRoot, "OpenSeesMatlab");
toolboxReleaseDir = fullfile(toolboxRootDir, "release");
srcInstallScript  = fullfile(projectRoot, "installOpenSeesMatlab.m");

%% Validate required paths
assert(isfolder(srcExamplesDir),    "Examples folder does not exist: %s", srcExamplesDir);
assert(isfolder(toolboxRootDir),    "Toolbox root folder does not exist: %s", toolboxRootDir);
assert(isfile(srcInstallScript),    "Install script does not exist: %s", srcInstallScript);

%% Locate toolbox project file
prjFiles = dir(fullfile(toolboxRootDir, "*.prj"));

if isempty(prjFiles)
    error("No toolbox .prj file was found in: %s", toolboxRootDir);
elseif numel(prjFiles) > 1
    error("Multiple .prj files were found in: %s. Please keep only one.", toolboxRootDir);
end

prjFile = fullfile(prjFiles(1).folder, prjFiles(1).name);

fprintf("Toolbox project file: %s\n", prjFile);
fprintf("Specified version   : %s\n", version);

%% Ensure toolbox internal release folder exists
ensureDir(toolboxReleaseDir);

%% =========================
% Package toolbox from .prj
% =========================
fprintf("\nUpdating toolbox version in project...\n");
matlab.addons.toolbox.toolboxVersion(prjFile, version);

generatedMltbxFile = fullfile(toolboxReleaseDir, "OpenSeesMatlab.mltbx");
if isfile(generatedMltbxFile)
    delete(generatedMltbxFile);
    fprintf("Removed existing toolbox package: %s\n", generatedMltbxFile);
end

fprintf("Packaging toolbox from project...\n");
matlab.addons.toolbox.packageToolbox(prjFile, generatedMltbxFile);

if ~isfile(generatedMltbxFile)
    error("Failed to generate toolbox package: %s", generatedMltbxFile);
end

fprintf("Generated toolbox package: %s\n", generatedMltbxFile);

%% Target paths
releaseRootDir    = fullfile(projectRoot, "release");
targetVerDir      = fullfile(releaseRootDir, version);
targetExDir       = fullfile(targetVerDir, "examples");
targetUtilsDir    = fullfile(targetExDir, "utils");
targetOutDir      = fullfile(targetExDir, "output_data");
targetMltbxFile   = fullfile(targetVerDir, "OpenSeesMatlab.mltbx");
targetInstallFile = fullfile(targetVerDir, "installOpenSeesMatlab.m");

%% Rebuild target release directory
ensureDir(releaseRootDir);

if isfolder(targetVerDir)
    fprintf("Removing existing folder: %s\n", targetVerDir);
    rmdir(targetVerDir, "s");
end

fprintf("Creating version folder: %s\n", targetVerDir);
mkdir(targetExDir);
mkdir(targetOutDir);

%% Export all .mlx files directly under examples/ to .m files
mlxFiles = dir(fullfile(srcExamplesDir, "*.mlx"));

for i = 1:numel(mlxFiles)
    srcFile = fullfile(mlxFiles(i).folder, mlxFiles(i).name);
    [~, baseName] = fileparts(mlxFiles(i).name);
    dstFile = fullfile(targetExDir, baseName + ".m");

    export(srcFile, dstFile);
end
fprintf("Export MLX to M done! (%d files)\n", numel(mlxFiles));

%% Copy utils subfolder recursively, excluding .png and .mp4
if isfolder(srcUtilsDir)
    nCopied = copyFolderExcludeExt(srcUtilsDir, targetUtilsDir, [".png", ".mp4"]);
    fprintf("Copied utils folder (excluding .png and .mp4): %d files\n", nCopied);
else
    warning("Utils folder does not exist: %s", srcUtilsDir);
end

%% Copy toolbox package into the version folder
copyfile(generatedMltbxFile, targetMltbxFile);
fprintf("Copied toolbox package: %s\n", targetMltbxFile);

%% Copy install script into the version folder
copyfile(srcInstallScript, targetInstallFile);
fprintf("Copied install script: %s\n", targetInstallFile);

%% Done
fprintf("\nRelease packaging completed successfully.\n");
fprintf("Version       : %s\n", version);
fprintf("Project file  : %s\n", prjFile);
fprintf("Toolbox file  : %s\n", generatedMltbxFile);
fprintf("Install script: %s\n", targetInstallFile);
fprintf("Release folder: %s\n", targetVerDir);

%% ========================================================================
% Local functions
% ========================================================================

function ensureDir(folderPath)
    if ~isfolder(folderPath)
        mkdir(folderPath);
    end
end

function nCopied = copyFolderExcludeExt(srcDir, dstDir, excludedExts)
% Recursively copy a folder while excluding files with specified extensions.
%
% Parameters
% ----------
% srcDir : char/string
%     Source directory.
% dstDir : char/string
%     Destination directory.
% excludedExts : string array
%     Extensions to exclude, e.g. [".png", ".mp4"].
%
% Returns
% -------
% nCopied : double
%     Number of copied files.

    ensureDir(dstDir);
    nCopied = 0;

    items = dir(srcDir);

    for k = 1:numel(items)
        name = items(k).name;

        if strcmp(name, ".") || strcmp(name, "..")
            continue;
        end

        srcPath = fullfile(srcDir, name);
        dstPath = fullfile(dstDir, name);

        if items(k).isdir
            nCopied = nCopied + copyFolderExcludeExt(srcPath, dstPath, excludedExts);
        else
            [~, ~, ext] = fileparts(name);
            ext = lower(string(ext));

            if any(ext == excludedExts)
                continue;
            end

            copyfile(srcPath, dstPath);
            nCopied = nCopied + 1;
        end
    end
end