%% Build a versioned release package from a versioned .mltbx file
% This script:
% 1. Detects the version from the toolbox file name
%    (expected format: OpenSeesMatlab_<version>.mltbx)
% 2. Rebuilds release/<version>
% 3. Copies all .mlx files under examples/ and the utils subfolder
%    into release/<version>/examples
% 4. Creates an empty output_data folder under examples
% 5. Copies the .mltbx file into release/<version>

clc;

%% Project root
% Assume this script is placed under the project root directory.
projectRoot = fileparts(mfilename("fullpath"));

%% Source paths
srcExamplesDir = fullfile(projectRoot, "examples");
srcUtilsDir    = fullfile(srcExamplesDir, "utils");
srcMltbxDir    = fullfile(projectRoot, "OpenSeesMatlab", "release");

%% Find versioned toolbox package
mltbxFiles = dir(fullfile(srcMltbxDir, "OpenSeesMatlab_*.mltbx"));

if isempty(mltbxFiles)
    error("No versioned .mltbx file was found in: %s", srcMltbxDir);
end

if numel(mltbxFiles) > 1
    error("Multiple versioned .mltbx files were found in: %s. Please keep only one.", srcMltbxDir);
end

srcMltbxFile = fullfile(mltbxFiles(1).folder, mltbxFiles(1).name);

%% Extract version from toolbox file name
% Expected file name format:
%   OpenSeesMatlab_<version>.mltbx
[~, baseName, ~] = fileparts(mltbxFiles(1).name);

prefix = "OpenSeesMatlab_";
if ~startsWith(string(baseName), prefix)
    error("Unexpected toolbox file name: %s", mltbxFiles(1).name);
end

version = extractAfter(string(baseName), strlength(prefix));

if strlength(version) == 0
    error("Failed to extract version from toolbox file name: %s", mltbxFiles(1).name);
end

fprintf("Detected version: %s\n", version);

%% Target paths
releaseRootDir = fullfile(projectRoot, "release");
targetVerDir   = fullfile(releaseRootDir, version);
targetExDir    = fullfile(targetVerDir, "examples");
targetUtilsDir = fullfile(targetExDir, "utils");
targetOutDir   = fullfile(targetExDir, "output_data");

% Keep the same versioned toolbox file name in the target folder
targetMltbxFile = fullfile(targetVerDir, mltbxFiles(1).name);

%% Validate source paths
if ~exist(srcExamplesDir, "dir")
    error("Examples folder does not exist: %s", srcExamplesDir);
end

if ~exist(srcMltbxFile, "file")
    error("Toolbox file does not exist: %s", srcMltbxFile);
end

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
    fprintf("Copied MLX: %s\n", mlxFiles(i).name);
end

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
copyfile(srcMltbxFile, targetMltbxFile);
fprintf("Copied toolbox package: %s\n", targetMltbxFile);

%% Done
fprintf("\nRelease packaging completed successfully.\n");
fprintf("Version       : %s\n", version);
fprintf("Release folder: %s\n", targetVerDir);