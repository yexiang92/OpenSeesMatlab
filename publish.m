%% Package the toolbox for the current operating system
%
% Place each OpenSeesMATLAB native bundle under
% OpenSeesMatlab/+ops/+core/derived/<platform>, then run this script. It creates exactly one
% platform package under release/<version>/.

clc;

%% Project paths and host platform
projectRoot = fileparts(mfilename("fullpath"));
toolboxRootDir = fullfile(projectRoot, "OpenSeesMatlab");
opsPackageDir = fullfile(toolboxRootDir, "+ops");
opsCoreDir = fullfile(opsPackageDir, "+core");
polyscopePrivateDir = fullfile(toolboxRootDir, "+plotter", "+polyscope", ...
    "vendor", "+polyscope", "private");
srcExamplesDir = fullfile(projectRoot, "examples");
srcUtilsDir = fullfile(srcExamplesDir, "utils");
srcInstallScript = fullfile(projectRoot, "installOpenSeesMatlab.m");

[platformTag, nativePlatform, mexExtension, minimumRelease] = currentPackagePlatform();
nativeDir = fullfile(opsCoreDir, "derived", nativePlatform);
mexFile = fullfile(nativeDir, "OpenSeesMATLAB." + mexExtension);
polyscopeMexFile = fullfile(polyscopePrivateDir, ...
    "polyscope_mex." + mexExtension);
opsFoundationFiles = [ ...
    "Commands.m", ...
    "Runtime.m", ...
    "SparseFactorizationCache.m", ...
    fullfile("+internal", "matrixOperator.m")];

assert(isfolder(toolboxRootDir), "Toolbox folder does not exist: %s", toolboxRootDir);
assert(isfolder(srcExamplesDir), "Examples folder does not exist: %s", srcExamplesDir);
assert(isfile(srcInstallScript), "Install script does not exist: %s", srcInstallScript);
assert(isfile(mexFile), "The %s native module is missing: %s", platformTag, mexFile);
assert(isfile(polyscopeMexFile), ...
    "The %s Polyscope module is missing: %s", platformTag, polyscopeMexFile);
assert(isfolder(opsPackageDir), ...
    "The ops MATLAB foundation is missing: %s", opsPackageDir);
assert(isfolder(opsCoreDir), ...
    "The replaceable ops.core binding layer is missing: %s", opsCoreDir);
for i = 1:numel(opsFoundationFiles)
    helperFile = fullfile(opsCoreDir, opsFoundationFiles(i));
    assert(isfile(helperFile), ...
        "The ops MATLAB foundation file is missing: %s", helperFile);
end

%% Read the product version from the native interface
addpath(nativeDir);
nativePathCleanup = onCleanup(@() rmpath(nativeDir));
version = string(OpenSeesMATLAB("matlabversion"));
assert(strlength(version) > 0, "The native interface returned an empty version.");

%% Locate the toolbox project
prjFiles = dir(fullfile(toolboxRootDir, "*.prj"));
assert(isscalar(prjFiles), ...
    "Exactly one toolbox .prj file is required in: %s", toolboxRootDir);
prjFile = fullfile(prjFiles(1).folder, prjFiles(1).name);

%% Configure one platform-specific toolbox package
releaseVersionDir = fullfile(projectRoot, "release", version);
ensureDir(releaseVersionDir);

packageName = "OpenSeesMatlab-" + version + "-" + platformTag + ".mltbx";
packageFile = fullfile(releaseVersionDir, packageName);
if isfile(packageFile)
    delete(packageFile);
end

opts = matlab.addons.toolbox.ToolboxOptions(prjFile);
opts.ToolboxVersion = version;
opts.MinimumMatlabRelease = minimumRelease;
opts.MaximumMatlabRelease = "";
opts.OutputFile = packageFile;
opts.SupportedPlatforms = supportedPlatformsFor(opts.SupportedPlatforms, platformTag);

% A project can remember binaries from a previous host. Add the complete
% current native bundle, then remove linker products and foreign binaries.
projectFiles = string(opts.ToolboxFiles(:));
nativeFiles = filesInFolder(nativeDir);
opsFiles = filesInFolder(opsPackageDir);
polyscopeNativeFiles = filesInFolder(polyscopePrivateDir);
opts.ToolboxFiles = filterPackageFiles( ...
    unique([projectFiles; nativeFiles; opsFiles; polyscopeNativeFiles]), platformTag);

fprintf("Packaging OpenSeesMatlab %s for %s...\n", version, platformTag);
matlab.addons.toolbox.packageToolbox(opts);
assert(isfile(packageFile), "Failed to generate toolbox package: %s", packageFile);

%% Export example scripts beside the release asset
targetExamplesDir = fullfile(releaseVersionDir, "examples");
targetUtilsDir = fullfile(targetExamplesDir, "utils");
targetOutputDir = fullfile(targetExamplesDir, "output_data");
ensureDir(targetExamplesDir);
ensureDir(targetOutputDir);

mlxFiles = dir(fullfile(srcExamplesDir, "*.mlx"));
for i = 1:numel(mlxFiles)
    sourceFile = fullfile(mlxFiles(i).folder, mlxFiles(i).name);
    [~, baseName] = fileparts(mlxFiles(i).name);
    export(sourceFile, fullfile(targetExamplesDir, baseName + ".m"));
end

if isfolder(srcUtilsDir)
    copyFolderExcludeExt(srcUtilsDir, targetUtilsDir, [".png", ".mp4"]);
end
copyfile(srcInstallScript, fullfile(releaseVersionDir, "installOpenSeesMatlab.m"));

fprintf("Created: %s\n", packageFile);
fprintf("Attach this %s package as one release asset.\n", platformTag);

%% Local functions
function [platformTag, nativePlatform, mexExtension, minimumRelease] = currentPackagePlatform()
    arch = string(computer("arch"));
    switch arch
        case "win64"
            platformTag = "win64";
            nativePlatform = "windows-x86_64";
            mexExtension = "mexw64";
            minimumRelease = "R2023a";
        case "maca64"
            platformTag = "maca64";
            nativePlatform = "macos-aarch64";
            mexExtension = "mexmaca64";
            minimumRelease = "R2023b";
        otherwise
            error("OpenSeesMatlab:UnsupportedPackagingPlatform", ...
                "Packaging supports Windows x86-64 and macOS Apple silicon; current architecture is %s.", ...
                arch);
    end
end

function supported = supportedPlatformsFor(supported, platformTag)
    names = string(fieldnames(supported));
    for i = 1:numel(names)
        supported.(names(i)) = false;
    end

    if platformTag == "win64"
        supported.Win64 = true;
    elseif isfield(supported, "Mac")
        % MATLAB R2026a and newer.
        supported.Mac = true;
    elseif isfield(supported, "Maci64")
        % MATLAB R2023b--R2025b use the legacy macOS field name.
        supported.Maci64 = true;
    else
        error("The installed MATLAB release cannot describe macOS toolbox support.");
    end
end

function files = filesInFolder(folderPath)
    entries = dir(fullfile(folderPath, "**", "*"));
    entries = entries(~[entries.isdir]);
    files = strings(numel(entries), 1);
    for i = 1:numel(entries)
        files(i) = string(fullfile(entries(i).folder, entries(i).name));
    end
end

function files = filterPackageFiles(files, platformTag)
    files = files(isfile(files));
    lowerFiles = lower(files);
    [~, ~, extensions] = arrayfun(@fileparts, lowerFiles, ...
        "UniformOutput", false);
    extensions = string(extensions);

    excluded = endsWith(lowerFiles, ...
        [".exp", ".lib", ".pdb", ".ilk", ".obj", ".o", ".a"]);

    if platformTag == "win64"
        excluded = excluded | ...
            (startsWith(extensions, ".mex") & extensions ~= ".mexw64") | ...
            endsWith(lowerFiles, [".dylib", ".so"]);
    else
        excluded = excluded | ...
            (startsWith(extensions, ".mex") & extensions ~= ".mexmaca64") | ...
            endsWith(lowerFiles, [".dll", ".so"]);
    end

    files = files(~excluded);
end

function ensureDir(folderPath)
    if ~isfolder(folderPath)
        mkdir(folderPath);
    end
end

function nCopied = copyFolderExcludeExt(srcDir, dstDir, excludedExts)
    ensureDir(dstDir);
    nCopied = 0;
    items = dir(srcDir);

    for k = 1:numel(items)
        name = string(items(k).name);
        if name == "." || name == ".."
            continue;
        end

        srcPath = fullfile(srcDir, name);
        dstPath = fullfile(dstDir, name);
        if items(k).isdir
            nCopied = nCopied + copyFolderExcludeExt(srcPath, dstPath, excludedExts);
        else
            [~, ~, extension] = fileparts(name);
            if any(lower(string(extension)) == excludedExts)
                continue;
            end
            copyfile(srcPath, dstPath);
            nCopied = nCopied + 1;
        end
    end
end
