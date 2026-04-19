%% Build a versioned release package from the toolbox project file

% Notes
% -----
% - The toolbox project file is assumed to be located in:
%       OpenSeesMatlab/*.prj
% - The packaged .mltbx file is generated as:
%       OpenSeesMatlab/release/OpenSeesMatlab.mltbx
% - The copied toolbox file in the release folder is also named:
%       OpenSeesMatlab.mltbx

clc;

%% =========================
% User-specified version
% =========================
version = "3.8.0.0";   % <-- manually set toolbox version here

%% Project root
% Assume this script is placed under the project root directory.
projectRoot = fileparts(mfilename("fullpath"));

%% Source paths
srcExamplesDir = fullfile(projectRoot, "examples");
srcUtilsDir    = fullfile(srcExamplesDir, "utils");

toolboxRootDir   = fullfile(projectRoot, "OpenSeesMatlab");
srcMltbxDir      = fullfile(toolboxRootDir, "release");
srcInstallScript = fullfile(projectRoot, "installOpenSeesMatlab.m");

%% Create release root folder if needed
if ~exist(srcMltbxDir, "dir")
    mkdir(srcMltbxDir);
end

%% Locate toolbox project file
prjFiles = dir(fullfile(toolboxRootDir, "*.prj"));

if isempty(prjFiles)
    error("No toolbox .prj file was found in: %s", toolboxRootDir);
end

if numel(prjFiles) > 1
    error("Multiple .prj files were found in: %s. Please keep only one.", toolboxRootDir);
end

prjFile = fullfile(prjFiles(1).folder, prjFiles(1).name);

fprintf("Toolbox project file: %s\n", prjFile);
fprintf("Specified version   : %s\n", version);

%% Validate source paths
if ~exist(srcExamplesDir, "dir")
    error("Examples folder does not exist: %s", srcExamplesDir);
end

if ~exist(toolboxRootDir, "dir")
    error("Toolbox root folder does not exist: %s", toolboxRootDir);
end

if ~exist(srcInstallScript, "file")
    error("Install script does not exist: %s", srcInstallScript);
end

%% Ensure toolbox release folder exists
if ~exist(srcMltbxDir, "dir")
    mkdir(srcMltbxDir);
end

%% =========================
% Package toolbox from .prj
% =========================
fprintf("\nUpdating toolbox version in project...\n");
matlab.addons.toolbox.toolboxVersion(prjFile, version);

generatedMltbxFile = fullfile(srcMltbxDir, "OpenSeesMatlab.mltbx");

% Remove old generated toolbox file if it exists
if exist(generatedMltbxFile, "file")
    delete(generatedMltbxFile);
    fprintf("Removed existing toolbox package: %s\n", generatedMltbxFile);
end

fprintf("Packaging toolbox from project...\n");
matlab.addons.toolbox.packageToolbox(prjFile, generatedMltbxFile);

if ~exist(generatedMltbxFile, "file")
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

%% Create release root folder if needed
if ~exist(releaseRootDir, "dir")
    mkdir(releaseRootDir);
end

%% Rebuild the version folder
if exist(targetVerDir, "dir")
    fprintf("Removing existing folder: %s\n", targetVerDir);
    rmdir(targetVerDir, "s");
end

fprintf("Creating version folder: %s\n", targetVerDir);
mkdir(targetVerDir);
mkdir(targetExDir);

%% Copy all .mlx files directly under examples/
mlxFiles = dir(fullfile(srcExamplesDir, "*.mlx"));

for i = 1:numel(mlxFiles)
    srcFile = fullfile(mlxFiles(i).folder, mlxFiles(i).name);
    dstFile = fullfile(targetExDir, mlxFiles(i).name);
    copyfile(srcFile, dstFile);
    % fprintf("Copied MLX: %s\n", mlxFiles(i).name);
end
fprintf("Copy MLX done!\n");

%% Copy utils subfolder
if exist(srcUtilsDir, "dir")
    copyfile(srcUtilsDir, targetUtilsDir);
    fprintf("Copied utils folder.\n");
else
    warning("Utils folder does not exist: %s", srcUtilsDir);
end

%% Create empty output_data folder
if ~exist(targetOutDir, "dir")
    mkdir(targetOutDir);
    fprintf("Created empty folder: %s\n", targetOutDir);
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