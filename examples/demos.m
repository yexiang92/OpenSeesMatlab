% =========================================================================
% Task definition: [category, example_name]
% Each .mlx file will be exported to markdown and organized by category
% =========================================================================
tasks = [ 
    "post",         "post_quick_plot";
    "post",         "post_get_model_data";
    "post",         "post_2d_Portal_Frame";
    "post",         "post_get_resp_odb";
    "post",         "post_soil_structure_interaction_2d_portal_frame";
    "post",         "post_excavation";
    "post",         "post_plot_fiber_section";
    "post",         "post_getMCK";
    "post",         "post_loads";
    "post",         "post_Smart_Analysis";
    "post",         "post_unitsystem";
    "post",         "post_Gmsh2OPS_solid";
    "structural",   "structural_nonlinear_truss";
    "structural",   "structural_steel_frame2d";
    "structural",   "structural_parfor_truss";
    "earthquake",   "earthquake_frame3D_transient";
    "earthquake",   "earthquake_RC_FRAME_EQ1";
    "geotechnical", "geotechnical_PM4Sand";
    "geotechnical", "geotechnical_PressureDependMultiYield6";
    "thermal",      "thermal_restrained_beam_under_thermal_expansion";
    "sensitivity",  "sensitivity_sensitivity_analysis";
    "verify",       "verify_Bracket";
    "verify",       "verify_stress_concentration_plate";
    "verify",       "verify_quad_beam";
    "verify",       "verify_quad_shell";
    "verify",       "verify_stdBrick";
    "verify",       "verify_beam";
    % add here
    % [category, example_name], if new category, please modify function localFolderMeta
];

% Root directory for generated documentation
rootDir = "../docs/examples";

% Force rebuild flag (true = rebuild everything)
forceRebuild = false;

% Create root directory if it does not exist
if ~exist(rootDir, "dir")
    mkdir(rootDir);
end

% =========================================================================
% Copy utils folder (shared helper scripts for examples)
% =========================================================================
srcUtilsDir = "utils";
dstUtilsDir = fullfile(rootDir, "utils");

if exist(srcUtilsDir, "dir")
    if localNeedCopyFolder(srcUtilsDir, dstUtilsDir, forceRebuild)
        if exist(dstUtilsDir, "dir")
            rmdir(dstUtilsDir, "s");
        end
        copyfile(srcUtilsDir, dstUtilsDir);
    end
else
    warning("Source utils folder does not exist: %s", srcUtilsDir);
end

% =========================================================================
% Export .mlx files to Markdown in parallel
% =========================================================================
parfor i = 1:size(tasks, 1)
    subdir = tasks(i, 1);
    name   = tasks(i, 2);

    outDir = fullfile(rootDir, subdir);
    if ~exist(outDir, "dir")
        mkdir(outDir);
    end

    mlxFile = name + ".mlx";
    outFile = fullfile(outDir, name + ".md");

    if localNeedExport(mlxFile, outFile, forceRebuild)

        % Export MATLAB live script to Markdown
        export( ...
            mlxFile, ...
            outFile, ...
            Format="markdown", ...
            EmbedImages=true, ...
            AcceptHTML=true);

        % Post-process Markdown (clean syntax and format output blocks)
        localPostProcessMarkdown(outFile);

        fprintf("Exported: %s -> %s\n", mlxFile, outFile);
    else
        fprintf("Skipped : %s\n", mlxFile);
    end
end

% =========================================================================
% Generate index.md for each category
% =========================================================================
subdirs = unique(tasks(:, 1), "stable");

for i = 1:numel(subdirs)
    subdir = subdirs(i);
    names = tasks(tasks(:, 1) == subdir, 2);

    outDir = fullfile(rootDir, subdir);
    if ~exist(outDir, "dir")
        mkdir(outDir);
    end

    outFile = fullfile(outDir, "index.md");
    fid = fopen(outFile, "w");
    if fid == -1
        error("Cannot open file for writing: %s", outFile);
    end

    cleaner = onCleanup(@() fclose(fid));

    % Get title and introduction text
    [titleStr, introStr] = localFolderMeta(subdir);

    % Write title
    fprintf(fid, "# %s\n\n", titleStr);

    % Write introduction paragraph
    if strlength(introStr) > 0
        fprintf(fid, "%s\n\n", introStr);
    end

    % fprintf(fid, "## Examples\n\n");

    % Generate list of example links
    for j = 1:numel(names)
        name = names(j);
        mdFile = fullfile(outDir, name + ".md");

        % Extract title from each markdown file
        title = localExtractMdTitle(mdFile);

        fprintf(fid, "- [%s](./%s.md)\n", title, name);
    end
end

% =========================================================================
% Generate root index.md for examples
% =========================================================================
rootIndexFile = fullfile(rootDir, "index.md");
fid = fopen(rootIndexFile, "w");
if fid == -1
    error("Cannot open file for writing: %s", rootIndexFile);
end

cleaner = onCleanup(@() fclose(fid));

fprintf(fid, '# Examples\n\n');

introText = ['This section collects the example documentation for ``OpenSeesMatlab``. ' ...
             'The examples are grouped by topic so that users can quickly find representative ' ...
             'workflows for preprocessing, structural analysis, earthquake simulation, ' ...
             'geotechnical modeling, thermal analysis, sensitivity analysis, verification, ' ...
             'and post-processing.' newline newline];

fprintf(fid, '%s', introText);
fprintf(fid, '## Categories\n\n');

for i = 1:numel(subdirs)
    subdir = subdirs(i);
    [titleStr, introStr] = localFolderMeta(subdir);

    fprintf(fid, '- [%s](./%s/index.md)', titleStr, subdir);

    if strlength(introStr) > 0
        fprintf(fid, ' — %s', introStr);
    end
    fprintf(fid, '\n');
end

% =========================================================================
% Helper: check whether .mlx needs to be exported
% =========================================================================
function tf = localNeedExport(mlxFile, mdFile, forceRebuild)
    if forceRebuild
        tf = true;
        return;
    end

    if ~exist(mlxFile, "file")
        error("Source mlx file does not exist: %s", mlxFile);
    end

    if ~exist(mdFile, "file")
        tf = true;
        return;
    end

    % Compare timestamps
    srcInfo = dir(mlxFile);
    dstInfo = dir(mdFile);

    tf = srcInfo.datenum > dstInfo.datenum;
end

% =========================================================================
% Helper: check whether utils folder needs to be copied
% =========================================================================
function tf = localNeedCopyFolder(srcDir, dstDir, forceRebuild)
    if forceRebuild || ~exist(dstDir, "dir")
        tf = true;
        return;
    end

    srcLatest = localFolderLatestDatenum(srcDir);
    dstLatest = localFolderLatestDatenum(dstDir);

    tf = srcLatest > dstLatest;
end

% =========================================================================
% Helper: get latest modification time in a folder
% =========================================================================
function t = localFolderLatestDatenum(folder)
    files = dir(fullfile(folder, "**", "*"));
    files = files(~[files.isdir]);

    if isempty(files)
        t = 0;
    else
        t = max([files.datenum]);
    end
end

% =========================================================================
% Post-process Markdown output
% =========================================================================
function localPostProcessMarkdown(mdFile)
    txt = fileread(mdFile);

    % Fix escaped brackets
    txt = replace(txt, "\[", "[");
    txt = replace(txt, "\]", "]");

    % Replace MATLAB output blocks with styled HTML
    txt = localReplaceMatlabTextOutputBlocks(txt);

    fid = fopen(mdFile, "w");
    if fid == -1
        error("Cannot open markdown file for rewriting: %s", mdFile);
    end

    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, txt, "char");
end

% =========================================================================
% Replace MATLAB output code blocks with formatted HTML blocks
% =========================================================================
function txt = localReplaceMatlabTextOutputBlocks(txt)
    pattern = '```matlabTextOutput\s*\r?\n([\s\S]*?)\r?\n```';

    [starts, ends, tokens] = regexp(txt, pattern, 'start', 'end', 'tokens');

    if isempty(starts)
        return;
    end

    pieces = cell(numel(starts) * 2 + 1, 1);
    prevEnd = 0;
    p = 1;

    for i = 1:numel(starts)
        pieces{p} = txt(prevEnd + 1 : starts(i) - 1);
        p = p + 1;

        content = tokens{i}{1};
        pieces{p} = localFormatOutputBlock(content);
        p = p + 1;

        prevEnd = ends(i);
    end

    pieces{p} = txt(prevEnd + 1 : end);
    txt = [pieces{1:p}];
end

% =========================================================================
% Format output block into HTML
% =========================================================================
function out = localFormatOutputBlock(content)
    content = regexprep(content, '^\s+|\s+$', '');
    content = replace(content, "&", "&amp;");
    content = replace(content, "<", "&lt;");
    content = replace(content, ">", "&gt;");

    out = [
        '<div style="font-size:0.85em; color:#87ae73;">' newline ...
        '<div style="font-weight:600;">Output</div>' newline ...
        '<div style="white-space:pre-wrap; font-family:Consolas;">' newline ...
        content newline ...
        '</div>' newline ...
        '</div>'
    ];
end

% =========================================================================
% Extract title from markdown file
% =========================================================================
function title = localExtractMdTitle(mdFile)
    fid = fopen(mdFile, "r");
    if fid == -1
        [~, name, ~] = fileparts(mdFile);
        title = string(name);
        return;
    end

    cleaner = onCleanup(@() fclose(fid));
    title = "";

    while true
        line = fgetl(fid);
        if ~ischar(line)
            break;
        end

        line = strtrim(string(line));
        if startsWith(line, "# ")
            title = strtrim(extractAfter(line, 2));
            return;
        end
    end

    [~, name, ~] = fileparts(mdFile);
    title = string(name);
end

% =========================================================================
% Define title and introduction for each category
% =========================================================================
function [titleStr, introStr] = localFolderMeta(subdir)
    switch char(subdir)
        case 'post'
            titleStr = "Pre, Post-processing and Visualization Examples";
            introStr = "Examples for additional preprocessing, post-processing, and visualization features provided by ``OpenSeesMatlab``.";

        case 'structural'
            titleStr = "Structural Examples";
            introStr = "Examples of structural modeling and analysis.";

        case 'earthquake'
            titleStr = "Earthquake Examples";
            introStr = "Examples of seismic and dynamic analysis.";

        case 'geotechnical'
            titleStr = "Geotechnical Examples";
            introStr = "Examples involving soil models and soil-structure interaction.";

        case 'thermal'
            titleStr = "Thermal Examples";
            introStr = "Examples of thermal and thermo-mechanical analysis.";

        case 'sensitivity'
            titleStr = "Sensitivity Examples";
            introStr = "Examples of sensitivity and parameter analysis.";
        
        case 'verify'
            titleStr = "Verification Examples";
            introStr = "Examples of verification by reliable third-party software.";

        otherwise
            titleStr = string(subdir) + " Examples";
            introStr = "";
    end
end