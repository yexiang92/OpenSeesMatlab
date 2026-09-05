%% Package the toolbox for the current operating system
%
% OpenSeesNexus is embedded as +ops/OpenSeesNexus. This script refreshes that
% complete sublibrary, then packages only the current native platform together
% with the higher-level OpenSeesMatlab features.

clc;

%% Project paths and host platform
projectRoot = fileparts(mfilename("fullpath"));
toolboxRootDir = fullfile(projectRoot, "OpenSeesMatlab");
opsPackageDir = fullfile(toolboxRootDir, "+ops");
polyscopePrivateDir = fullfile(toolboxRootDir, "+plotter", "+polyscope", ...
    "vendor", "+polyscope", "private");
srcExamplesDir = fullfile(projectRoot, "examples");
srcUtilsDir = fullfile(srcExamplesDir, "utils");
srcInstallScript = fullfile(projectRoot, "installOpenSeesMatlab.m");

[platformTag, nativePlatform, mexExtension, minimumRelease] = currentPackagePlatform();
bindingsPackageDir = locateBindingsPackage(projectRoot);
syncBindingsPackage(bindingsPackageDir, toolboxRootDir, nativePlatform);
nexusLibraryDir = fullfile(opsPackageDir, "OpenSeesNexus");
ops.connectOpenSeesNexus();
implementationDir = fullfile(nexusLibraryDir, "+nexus");
nativeDir = fullfile(nexusLibraryDir, "derived", nativePlatform);
mexFile = fullfile(nativeDir, "OpenSeesMATLAB." + mexExtension);
polyscopeMexFile = fullfile(polyscopePrivateDir, ...
    "polyscope_mex." + mexExtension);
opsFoundationFiles = [ ...
    "Commands.m", ...
    "Runtime.m", ...
    "getBackend.m", ...
    "setBackend.m", ...
    "SparseFactorizationCache.m", ...
    fullfile("+internal", "matrixOperator.m")];
if platformTag == "win64"
    spLauncherFiles = fullfile(nexusLibraryDir, [ ...
        "OpenSeesSPMatlab.cmd"; ...
        "OpenSeesSPMatlab.ps1"]);
else
    spLauncherFiles = fullfile(nexusLibraryDir, "OpenSeesSPMatlab.sh");
end

assert(isfolder(toolboxRootDir), "Toolbox folder does not exist: %s", toolboxRootDir);
assert(isfolder(srcExamplesDir), "Examples folder does not exist: %s", srcExamplesDir);
assert(isfile(srcInstallScript), "Install script does not exist: %s", srcInstallScript);
assert(isfile(mexFile), "The %s OpenSeesNexus module is missing: %s", ...
    platformTag, mexFile);
assert(isfile(polyscopeMexFile), ...
    "The %s Polyscope module is missing: %s", platformTag, polyscopeMexFile);
assert(isfolder(opsPackageDir), ...
    "The ops MATLAB package is missing: %s", opsPackageDir);
assert(isfolder(implementationDir), ...
    "The embedded OpenSeesNexus implementation is missing: %s", implementationDir);
for i = 1:numel(opsFoundationFiles)
    helperFile = fullfile(implementationDir, opsFoundationFiles(i));
    assert(isfile(helperFile), ...
        "The OpenSeesNexus file is missing: %s", helperFile);
end
for i = 1:numel(spLauncherFiles)
    assert(isfile(spLauncherFiles(i)), ...
        "The OpenSeesSP launcher is missing: %s", spLauncherFiles(i));
end

%% Read the product version from the embedded OpenSeesNexus interface
nexus = OpenSeesNexus();
version = string(nexus.matlabversion());
assert(strlength(version) > 0, "The native interface returned an empty version.");

%% Locate the toolbox project
prjFiles = dir(fullfile(toolboxRootDir, "*.prj"));
assert(isscalar(prjFiles), ...
    "Exactly one toolbox .prj file is required in: %s", toolboxRootDir);
prjFile = fullfile(prjFiles(1).folder, prjFiles(1).name);

%% Configure one self-contained platform release
releasePlatformDir = fullfile(projectRoot, "release", version, nativePlatform);
ensureDir(releasePlatformDir);

packageName = "OpenSeesMatlab-" + version + "-" + platformTag + ".mltbx";
packageFile = fullfile(releasePlatformDir, packageName);
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
    unique([projectFiles; nativeFiles; opsFiles; spLauncherFiles; polyscopeNativeFiles]), ...
    platformTag);

fprintf("Packaging OpenSeesMatlab %s for %s...\n", version, platformTag);
matlab.addons.toolbox.packageToolbox(opts);
assert(isfile(packageFile), "Failed to generate toolbox package: %s", packageFile);

%% Export example scripts beside the release asset
targetExamplesDir = fullfile(releasePlatformDir, "examples");
targetUtilsDir = fullfile(targetExamplesDir, "utils");
targetOutputDir = fullfile(targetExamplesDir, "output_data");
ensureDir(targetExamplesDir);
ensureDir(targetOutputDir);

exampleFiles = dir(fullfile(srcExamplesDir, "*.m"));
exampleFiles = exampleFiles(arrayfun(@(file) isPlainTextLiveCodeFile( ...
    fullfile(file.folder, file.name)), exampleFiles));
for i = 1:numel(exampleFiles)
    sourceFile = fullfile(exampleFiles(i).folder, exampleFiles(i).name);
    [~, baseName] = fileparts(exampleFiles(i).name);
    export(sourceFile, fullfile(targetExamplesDir, baseName + ".m"), ...
        Format="m");
end

if isfolder(srcUtilsDir)
    copyFolderExcludeExt(srcUtilsDir, targetUtilsDir, [".png", ".mp4"]);
end
copyfile(srcInstallScript, fullfile(releasePlatformDir, "installOpenSeesMatlab.m"));

fprintf("Created: %s\n", packageFile);
fprintf("Platform release directory: %s\n", releasePlatformDir);

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

function packageDir = locateBindingsPackage(projectRoot)
    packageDir = string(getenv("OPENSEES_NEXUS_MATLAB_ROOT"));
    if strlength(packageDir) == 0
        packageDir = fullfile(fileparts(projectRoot), ...
            "OpenSeesBindings", "packages", "matlab", "OpenSeesNexus");
    end
    assert(isfile(fullfile(packageDir, "OpenSeesNexus.m")), ...
        ["The OpenSeesNexus MATLAB package was not found at %s. Set " ...
         "OPENSEES_NEXUS_MATLAB_ROOT to its extracted package root."], ...
        packageDir);
end

function syncBindingsPackage(packageDir, toolboxRootDir, nativePlatform)
    sourceImplementation = fullfile(packageDir, "+nexus");
    sourceNative = fullfile(packageDir, "derived", nativePlatform);
    targetOps = fullfile(toolboxRootDir, "+ops");
    targetLibrary = fullfile(targetOps, "OpenSeesNexus");

    assert(isfile(fullfile(sourceImplementation, "Runtime.m")), ...
        "OpenSeesNexus does not contain +nexus/Runtime.m: %s", packageDir);
    assert(isfolder(sourceNative), ...
        "OpenSeesNexus does not contain native files for %s: %s", ...
        nativePlatform, sourceNative);
    assert(isfile(fullfile(targetOps, "OpenSeesMatlabCmds.m")), ...
        "Refusing to modify an unrecognized +ops directory: %s", targetOps);

    % OpenSeesNexus is a self-contained sublibrary. Replacing this one plain
    % directory preserves every high-level MATLAB file beside it in +ops.
    if isfolder(targetLibrary)
        clear mex;
        fileattrib(targetLibrary, "+w", "", "s");
        rmdir(targetLibrary, "s");
    end
    [copied, message] = copyfile(packageDir, targetLibrary, "f");
    assert(copied, "Could not embed OpenSeesNexus: %s", message);
    fprintf("Embedded OpenSeesNexus from: %s\n", packageDir);
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
    normalized = replace(lowerFiles, "\", "/");
    if platformTag == "win64"
        excluded = excluded | ...
            contains(normalized, "/derived/macos-aarch64/") | ...
            endsWith(normalized, "/openseesspmatlab.sh");
    else
        excluded = excluded | ...
            contains(normalized, "/derived/windows-x86_64/") | ...
            endsWith(normalized, ...
                ["/openseesspmatlab.cmd", "/openseesspmatlab.ps1"]);
    end

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

function tf = isPlainTextLiveCodeFile(filePath)
    tf = contains(fileread(filePath), "%[appendix]");
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
