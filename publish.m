%% Package the toolbox for all supported operating systems
%
% OpenSeesNexus and Polyscope are already embedded in the toolbox tree. This
% script leaves those files untouched and creates one self-contained toolbox
% for Windows x86-64 and one for macOS Apple silicon.

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

prjFiles = dir(fullfile(toolboxRootDir, "*.prj"));
assert(isscalar(prjFiles), ...
    "Exactly one toolbox .prj file is required in: %s", toolboxRootDir);
prjFile = fullfile(prjFiles(1).folder, prjFiles(1).name);
projectOptions = matlab.addons.toolbox.ToolboxOptions(prjFile);
version = string(projectOptions.ToolboxVersion);
assert(strlength(version) > 0, ...
    "The OpenSeesMatlab toolbox project has no version.");

platforms = [ ...
    struct("tag", "win64", "native", "windows-x86_64", ...
        "mex", "mexw64", "minimumRelease", "R2023a"), ...
    struct("tag", "maca64", "native", "macos-aarch64", ...
        "mex", "mexmaca64", "minimumRelease", "R2023b")];

nexusLibraryDir = fullfile(opsPackageDir, "OpenSeesNexus");
implementationDir = fullfile(nexusLibraryDir, "+nexus");
opsFoundationFiles = [ ...
    "Commands.m", ...
    "Runtime.m", ...
    "getBackend.m", ...
    "setBackend.m", ...
    "SparseFactorizationCache.m", ...
    fullfile("+internal", "matrixOperator.m")];

assert(isfolder(toolboxRootDir), "Toolbox folder does not exist: %s", toolboxRootDir);
assert(isfolder(srcExamplesDir), "Examples folder does not exist: %s", srcExamplesDir);
assert(isfile(srcInstallScript), "Install script does not exist: %s", srcInstallScript);
assert(isfolder(opsPackageDir), ...
    "The ops MATLAB package is missing: %s", opsPackageDir);
assert(isfolder(implementationDir), ...
    "The embedded OpenSeesNexus implementation is missing: %s", implementationDir);
for i = 1:numel(opsFoundationFiles)
    helperFile = fullfile(implementationDir, opsFoundationFiles(i));
    assert(isfile(helperFile), ...
        "The OpenSeesNexus file is missing: %s", helperFile);
end

%% Package the complete project once for each native platform
allToolboxFiles = filesInFolder(toolboxRootDir);
commonSourceFiles = allToolboxFiles(endsWith(lower(allToolboxFiles), ".m"));

for p = 1:numel(platforms)
    platform = platforms(p);
    platformTag = string(platform.tag);
    nativePlatform = string(platform.native);
    mexExtension = string(platform.mex);
    minimumRelease = string(platform.minimumRelease);
    nativeDir = fullfile(nexusLibraryDir, "derived", nativePlatform);
    mexFile = fullfile(nativeDir, "OpenSeesMATLAB." + mexExtension);
    polyscopeMexFile = fullfile(polyscopePrivateDir, ...
        "polyscope_mex." + mexExtension);

    assert(isfile(mexFile), "The %s OpenSeesNexus module is missing: %s", ...
        platformTag, mexFile);
    assert(isfile(polyscopeMexFile), ...
        "The %s Polyscope module is missing: %s", platformTag, polyscopeMexFile);

    if platformTag == "win64"
        spLauncherFiles = fullfile(nexusLibraryDir, [ ...
            "OpenSeesSPMatlab.cmd"; ...
            "OpenSeesSPMatlab.ps1"]);
    else
        spLauncherFiles = fullfile(nexusLibraryDir, "OpenSeesSPMatlab.sh");
    end
    for i = 1:numel(spLauncherFiles)
        assert(isfile(spLauncherFiles(i)), ...
            "The OpenSeesSP launcher is missing: %s", spLauncherFiles(i));
    end

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
    opts.SupportedPlatforms = supportedPlatformsFor( ...
        opts.SupportedPlatforms, platformTag);

    % Start from the complete toolbox tree rather than the project's cached
    % file list. filterPackageFiles removes only generated project metadata,
    % linker products, and native files belonging to the other platform.
    packageFiles = filterPackageFiles(allToolboxFiles, platformTag);
    assert(all(ismember(commonSourceFiles, packageFiles)), ...
        "The %s package would omit one or more MATLAB source files.", platformTag);
    opts.ToolboxFiles = packageFiles;

    fprintf("Packaging OpenSeesMatlab %s for %s (%d files)...\n", ...
        version, platformTag, numel(packageFiles));
    matlab.addons.toolbox.packageToolbox(opts);
    assert(isfile(packageFile), ...
        "Failed to generate toolbox package: %s", packageFile);

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
    copyfile(srcInstallScript, ...
        fullfile(releasePlatformDir, "installOpenSeesMatlab.m"));

    fprintf("Created: %s\n", packageFile);
    fprintf("Platform release directory: %s\n", releasePlatformDir);
end

%% Local functions
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

    normalized = replace(lowerFiles, "\", "/");
    excluded = contains(normalized, "/resources/") | ...
        contains(normalized, "/release/") | ...
        endsWith(normalized, ["/openseesmatlab.prj", "/toolbox.ignore", ...
            "/deploymentlog.html", "/.gitignore", "/.gitattributes"]) | ...
        endsWith(lowerFiles, ...
        [".exp", ".lib", ".pdb", ".ilk", ".obj", ".o", ".a"]);
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
