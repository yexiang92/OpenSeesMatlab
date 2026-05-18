% =========================================================================
% Task definition: [category, subgroup, example_name]
% Only "post" examples use subgroup. Other categories use "".
% =========================================================================
tasks = [
    "post", "basic",         "post_quick_plot";
    "post", "basic",         "post_get_model_data";
    "post", "basic",         "post_get_resp_odb";
    "post", "visualization", "post_2d_Portal_Frame";
    "post", "visualization", "post_soil_structure_interaction_2d_portal_frame";
    "post", "visualization", "post_excavation";
    "post", "preprocess",    "post_getMCK";
    "post", "preprocess",    "post_loads";
    "post", "preprocess",    "post_unitsystem";
    "post", "preprocess",    "post_Gmsh2OPS_solid";
    "post", "section",       "post_plot_fiber_section";
    "post", "section",       "post_section_mesh";
    "post", "analysis",      "post_Smart_Analysis";
    "post", "analysis",      "post_mphi_analysis";

    "structural",   "", "structural_nonlinear_truss";
    "structural",   "", "structural_steel_frame2d";
    "structural",   "", "structural_parfor_truss";
    "earthquake",   "", "earthquake_frame3D_transient";
    "earthquake",   "", "earthquake_RC_FRAME_EQ1";
    "geotechnical", "", "geotechnical_PM4Sand";
    "geotechnical", "", "geotechnical_PressureDependMultiYield6";
    "thermal",      "", "thermal_restrained_beam_under_thermal_expansion";
    "sensitivity",  "", "sensitivity_sensitivity_analysis";
    "verify",       "", "verify_Bracket";
    "verify",       "", "verify_stress_concentration_plate";
    "verify",       "", "verify_quad_beam";
    "verify",       "", "verify_quad_shell";
    "verify",       "", "verify_stdBrick";
    "verify",       "", "verify_beam";
];

rootDir = "../docs/examples";
forceRebuild = false;

if ~exist(rootDir, "dir")
    mkdir(rootDir);
end

% =========================================================================
% Copy utils folder
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
% Create all export folders before parfor
% =========================================================================
for i = 1:size(tasks, 1)
    category = tasks(i, 1);
    subgroup = tasks(i, 2);

    if strlength(subgroup) > 0
        outDir = fullfile(rootDir, category, subgroup);
    else
        outDir = fullfile(rootDir, category);
    end

    if ~isfolder(outDir)
        mkdir(outDir);
    end
end

% =========================================================================
% Export .mlx files to Markdown
% =========================================================================
parfor i = 1:size(tasks, 1)
    category = tasks(i, 1);
    subgroup = tasks(i, 2);
    name     = tasks(i, 3);

    if strlength(subgroup) > 0
        outDir = fullfile(rootDir, category, subgroup);
    else
        outDir = fullfile(rootDir, category);
    end

    mlxFile = name + ".mlx";
    outFile = fullfile(outDir, name + ".md");

    if localNeedExport(mlxFile, outFile, forceRebuild)
        export(mlxFile, outFile, ...
            Format="markdown", ...
            EmbedImages=true, ...
            AcceptHTML=true);

        localPostProcessMarkdown(outFile);

        fprintf("Exported: %s -> %s\n", mlxFile, outFile);
    else
        fprintf("Skipped : %s\n", mlxFile);
    end
end

% =========================================================================
% Generate index.md for each category
% =========================================================================
categories = unique(tasks(:, 1), "stable");

for i = 1:numel(categories)
    category = categories(i);
    rows = tasks(tasks(:, 1) == category, :);

    outDir = fullfile(rootDir, category);
    if ~exist(outDir, "dir")
        mkdir(outDir);
    end

    outFile = fullfile(outDir, "index.md");
    fid = fopen(outFile, "w");
    if fid == -1
        error("Cannot open file for writing: %s", outFile);
    end
    cleaner = onCleanup(@() fclose(fid));

    [titleStr, introStr] = localFolderMeta(category);

    fprintf(fid, "# %s\n\n", titleStr);

    if strlength(introStr) > 0
        fprintf(fid, "%s\n\n", introStr);
    end

    subgroups = unique(rows(:, 2), "stable");

    if numel(subgroups) == 1 && strlength(subgroups(1)) == 0
        names = rows(:, 3);

        for j = 1:numel(names)
            name = names(j);
            mdFile = fullfile(outDir, name + ".md");
            title = localExtractMdTitle(mdFile);

            fprintf(fid, "- [%s](./%s.md)\n", title, name);
        end

    else
        for j = 1:numel(subgroups)
            subgroup = subgroups(j);

            if strlength(subgroup) == 0
                subgroupRows = rows(strlength(rows(:, 2)) == 0, :);
                fprintf(fid, "## Examples\n\n");

                for k = 1:size(subgroupRows, 1)
                    name = subgroupRows(k, 3);
                    mdFile = fullfile(outDir, name + ".md");
                    title = localExtractMdTitle(mdFile);

                    fprintf(fid, "- [%s](./%s.md)\n", title, name);
                end

            else
                subgroupRows = rows(rows(:, 2) == subgroup, :);
                subgroupTitle = localSubgroupTitle(category, subgroup);

                fprintf(fid, "## %s\n\n", subgroupTitle);

                for k = 1:size(subgroupRows, 1)
                    name = subgroupRows(k, 3);
                    mdFile = fullfile(outDir, subgroup, name + ".md");
                    title = localExtractMdTitle(mdFile);

                    fprintf(fid, "- [%s](./%s/%s.md)\n", title, subgroup, name);
                end
            end

            fprintf(fid, "\n");
        end
    end
end

% =========================================================================
% Generate root index.md
% =========================================================================
rootIndexFile = fullfile(rootDir, "index.md");
fid = fopen(rootIndexFile, "w");
if fid == -1
    error("Cannot open file for writing: %s", rootIndexFile);
end
cleaner = onCleanup(@() fclose(fid));

fprintf(fid, "# Examples\n\n");

introText = ['This section collects the example documentation for ``OpenSeesMatlab``. ' ...
             'The examples are grouped by topic so that users can quickly find representative ' ...
             'workflows for preprocessing, structural analysis, earthquake simulation, ' ...
             'geotechnical modeling, thermal analysis, sensitivity analysis, verification, ' ...
             'and post-processing.' newline newline];

fprintf(fid, "%s", introText);
fprintf(fid, "## Categories\n\n");

for i = 1:numel(categories)
    category = categories(i);
    [titleStr, introStr] = localFolderMeta(category);

    fprintf(fid, "- [%s](./%s/index.md)", titleStr, category);

    if strlength(introStr) > 0
        fprintf(fid, " — %s", introStr);
    end

    fprintf(fid, "\n");
end

% =========================================================================
% Helper functions
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

    srcInfo = dir(mlxFile);
    dstInfo = dir(mdFile);

    tf = srcInfo.datenum > dstInfo.datenum;
end

function tf = localNeedCopyFolder(srcDir, dstDir, forceRebuild)
    if forceRebuild || ~exist(dstDir, "dir")
        tf = true;
        return;
    end

    srcLatest = localFolderLatestDatenum(srcDir);
    dstLatest = localFolderLatestDatenum(dstDir);

    tf = srcLatest > dstLatest;
end

function t = localFolderLatestDatenum(folder)
    files = dir(fullfile(folder, "**", "*"));
    files = files(~[files.isdir]);

    if isempty(files)
        t = 0;
    else
        t = max([files.datenum]);
    end
end

function localPostProcessMarkdown(mdFile)
    txt = fileread(mdFile);

    txt = replace(txt, "\[", "[");
    txt = replace(txt, "\]", "]");

    txt = localReplaceMatlabTextOutputBlocks(txt);

    fid = fopen(mdFile, "w");
    if fid == -1
        error("Cannot open markdown file for rewriting: %s", mdFile);
    end

    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, txt, "char");
end

function txt = localReplaceMatlabTextOutputBlocks(txt)
    pattern = '```matlabTextOutput\s*\r?\n([\s\S]*?)\r?\n```';

    [starts, ends, tokens] = regexp(txt, pattern, "start", "end", "tokens");

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

function out = localFormatOutputBlock(content)
    content = regexprep(content, "^\s+|\s+$", "");
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

function [titleStr, introStr] = localFolderMeta(subdir)
    switch char(subdir)
        case "post"
            titleStr = "Pre, Post-processing and Visualization Examples";
            introStr = "Examples for additional preprocessing, post-processing, and visualization features provided by ``OpenSeesMatlab``.";

        case "structural"
            titleStr = "Structural Examples";
            introStr = "Examples of structural modeling and analysis.";

        case "earthquake"
            titleStr = "Earthquake Examples";
            introStr = "Examples of seismic and dynamic analysis.";

        case "geotechnical"
            titleStr = "Geotechnical Examples";
            introStr = "Examples involving soil models and soil-structure interaction.";

        case "thermal"
            titleStr = "Thermal Examples";
            introStr = "Examples of thermal and thermo-mechanical analysis.";

        case "sensitivity"
            titleStr = "Sensitivity Examples";
            introStr = "Examples of sensitivity and parameter analysis.";

        case "verify"
            titleStr = "Verification Examples";
            introStr = "Examples of verification by reliable third-party software.";

        otherwise
            titleStr = string(subdir) + " Examples";
            introStr = "";
    end
end

function titleStr = localSubgroupTitle(category, subgroup)
    switch char(category)
        case "post"
            switch char(subgroup)
                case "basic"
                    titleStr = "Basic Utilities";
                case "model-data"
                    titleStr = "Model Data Extraction";
                case "visualization"
                    titleStr = "Visualization";
                case "odb"
                    titleStr = "Output Database";
                case "loads"
                    titleStr = "Loads";
                case "analysis"
                    titleStr = "Analysis Utilities";
                case "preprocess"
                    titleStr = "Preprocessing";
                case "section"
                    titleStr = "Fiber Sections";
                otherwise
                    titleStr = localPrettyTitle(subgroup);
            end

        otherwise
            titleStr = localPrettyTitle(subgroup);
    end
end

function titleStr = localPrettyTitle(name)
    titleStr = replace(string(name), ["-", "_"], " ");
    words = split(titleStr);
    for i = 1:numel(words)
        if strlength(words(i)) > 0
            words(i) = upper(extractBefore(words(i), 2)) + extractAfter(words(i), 1);
        end
    end
    titleStr = strjoin(words, " ");
end