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
    % "post", "analysis",      "post_Smart_Analysis";
    "post", "analysis",      "post_mphi_analysis";

    "opscmds",  "structural",  "structural_nonlinear_truss";
    "opscmds",  "structural",  "structural_steel_frame2d";
    "opscmds",  "structural",  "structural_mvlem3d_force_controlled";
    "opscmds",  "earthquake",  "earthquake_NLSMRF";
    "opscmds",  "earthquake",  "earthquake_frame3D_transient";
    "opscmds",  "earthquake",  "earthquake_RC_FRAME_EQ1";
    "opscmds",  "earthquake",  "earthquake_Two_Story_Steel_MRF";
    "opscmds",  "geotechnical", "geotechnical_PM4Sand";
    "opscmds",  "geotechnical", "geotechnical_PressureDependMultiYield6";
    "opscmds",  "thermal",      "thermal_restrained_beam_under_thermal_expansion";
    "opscmds",  "sensitivity",  "sensitivity_sensitivity_analysis";

    "opscmds",  "parallel",     "parallel_openseessp_plane_100k";
    "opscmds",  "parallel",     "parallel_openseessp_nonlinear_pushover";
    "opscmds",  "parallel",     "parallel_structural_parfor_truss";

    "verify",       "", "verify_Bracket";
    "verify",       "", "verify_stress_concentration_plate";
    "verify",       "", "verify_quad_beam";
    "verify",       "", "verify_quad_shell";
    "verify",       "", "verify_stdBrick";
    "verify",       "", "verify_beam";

    "extension", "substruct",      "extension_substructure_linear";
    "extension", "substruct",      "extension_substructure_nonlinear_dynamic";
    "extension", "system",         "extension_gpu_CuDSS_test";
    "extension", "material",       "extension_MatlabUniaxialMaterial_linear";
    "extension", "material",       "extension_MatlabUniaxialMaterial_nonlinear";
    "extension", "adaptiveAnalyze",  "extension_adaptiveAnalyze_static";
    "extension", "adaptiveAnalyze",  "extension_adaptiveAnalyze_dynamic";
    "extension", "algorithm", "extension_KINSOL_steel_frame_benchmark";
    "extension", "algorithm", "extension_TrustRegion_steel_frame_benchmark";
];

examplesDir = string(fileparts(mfilename("fullpath")));
projectDir = string(fileparts(examplesDir));
rootDir = fullfile(projectDir, "docs", "examples");
forceRebuild = false;
% Set false to export examples serially without starting a parallel pool.
useParallel = false;

if ~exist(rootDir, "dir")
    mkdir(rootDir);
end

% =========================================================================
% Copy utils folder
% =========================================================================
srcUtilsDir = fullfile(examplesDir, "utils");
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
% Export plain-text Live Code .m files to Markdown
% =========================================================================
localExportTasks(tasks, examplesDir, rootDir, forceRebuild, useParallel);
localUpgradeLegacyExampleOutputs(rootDir);

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
    fid = localOpenTextFileForWriting(outFile);
    cleaner = onCleanup(@() fclose(fid));

    [titleStr, introStr] = localFolderMeta(category);

    fprintf(fid, "# %s\n\n", titleStr);

    if strlength(introStr) > 0
        fprintf(fid, "%s\n\n", introStr);
    end

    subgroups = unique(rows(:, 2), "stable");

    if numel(subgroups) == 1 && strlength(subgroups(1)) == 0
        names = rows(:, 3);
        fprintf(fid, '<div class="example-gallery">\n');

        for j = 1:numel(names)
            name = names(j);
            mdFile = fullfile(outDir, name + ".md");
            title = localExtractMdTitle(mdFile);
            localWriteExampleCard(fid, mdFile, title, ...
                "./" + name + ".md", "./" + name);
        end
        fprintf(fid, '</div>\n');

    else
        for j = 1:numel(subgroups)
            subgroup = subgroups(j);

            if strlength(subgroup) == 0
                subgroupRows = rows(strlength(rows(:, 2)) == 0, :);
                fprintf(fid, "## Examples\n\n");
                fprintf(fid, '<div class="example-gallery">\n');

                for k = 1:size(subgroupRows, 1)
                    name = subgroupRows(k, 3);
                    mdFile = fullfile(outDir, name + ".md");
                    title = localExtractMdTitle(mdFile);
                    localWriteExampleCard(fid, mdFile, title, ...
                        "./" + name + ".md", "./" + name);
                end
                fprintf(fid, '</div>\n');

            else
                subgroupRows = rows(rows(:, 2) == subgroup, :);
                subgroupTitle = localSubgroupTitle(category, subgroup);

                fprintf(fid, "## %s\n\n", subgroupTitle);
                fprintf(fid, '<div class="example-gallery">\n');

                for k = 1:size(subgroupRows, 1)
                    name = subgroupRows(k, 3);
                    mdFile = fullfile(outDir, subgroup, name + ".md");
                    title = localExtractMdTitle(mdFile);
                    localWriteExampleCard(fid, mdFile, title, ...
                        "./" + subgroup + "/" + name + ".md", ...
                        "./" + subgroup + "/" + name);
                end
                fprintf(fid, '</div>\n');
            end

            fprintf(fid, "\n");
        end
    end
end

% =========================================================================
% Generate root index.md
% =========================================================================
rootIndexFile = fullfile(rootDir, "index.md");
fid = localOpenTextFileForWriting(rootIndexFile);
cleaner = onCleanup(@() fclose(fid));

fprintf(fid, "# Examples\n\n");

introText = ['This section collects the example documentation for ``OpenSeesMatlab``. ' ...
             'The examples are grouped by topic so that users can quickly find representative ' ...
             'workflows for preprocessing, structural analysis, earthquake simulation, ' ...
             'geotechnical modeling, thermal analysis, sensitivity analysis, verification, ' ...
             'and post-processing.' newline newline];

fprintf(fid, "%s", introText);
fprintf(fid, "**Categories**\n\n");

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
function fid = localOpenTextFileForWriting(fileName)
    maximumAttempts = 40;
    openMessage = "";
    for attempt = 1:maximumAttempts
        [fid, openMessage] = fopen(fileName, "w", "n", "UTF-8");
        if fid ~= -1
            return;
        end
        pause(0.1);
    end

    error("Cannot open file for writing after %.1f seconds: %s\n%s", ...
        maximumAttempts * 0.1, fileName, openMessage);
end

function localExportTasks(tasks, examplesDir, rootDir, forceRebuild, useParallel)
    if useParallel
        parfor i = 1:size(tasks, 1)
            localExportTask(tasks(i, :), examplesDir, rootDir, forceRebuild);
        end
    else
        for i = 1:size(tasks, 1)
            localExportTask(tasks(i, :), examplesDir, rootDir, forceRebuild);
        end
    end
end

function localExportTask(task, examplesDir, rootDir, forceRebuild)
    category = task(1);
    subgroup = task(2);
    name = task(3);

    if strlength(subgroup) > 0
        outDir = fullfile(rootDir, category, subgroup);
        logoHref = "../../../static/images/matlab.svg";
    else
        outDir = fullfile(rootDir, category);
        logoHref = "../../static/images/matlab.svg";
    end

    liveCodeFile = fullfile(examplesDir, name + ".m");
    outFile = fullfile(outDir, name + ".md");
    mFile = fullfile(outDir, name + ".m");

    if ~isfolder(outDir)
        mkdir(outDir);
    end

    if localNeedExport(liveCodeFile, outFile, forceRebuild)
        localExportLiveCode(liveCodeFile, outFile, "markdown");
        fprintf("Exported: %s -> %s\n", liveCodeFile, outFile);
    else
        fprintf("Updated : %s\n", outFile);
    end

    % Export a plain MATLAB script beside the Markdown file. Check it
    % independently so an existing/up-to-date Markdown file does not prevent
    % a missing or stale .m download from being generated.
    if localNeedExport(liveCodeFile, mFile, forceRebuild)
        localExportLiveCode(liveCodeFile, mFile, "m");
        fprintf("Exported: %s -> %s\n", liveCodeFile, mFile);
    end

    % The exporter may already be up to date while the post-processing rules
    % in this script have changed. Always run the inexpensive normalization,
    % including insertion of the script download link.
    localPostProcessMarkdown(outFile, name + ".m", logoHref);
end

function tf = localNeedExport(liveCodeFile, outputFile, forceRebuild)
    if forceRebuild
        tf = true;
        return;
    end

    if ~exist(liveCodeFile, "file")
        error("Source Live Code file does not exist: %s", liveCodeFile);
    end

    if ~exist(outputFile, "file")
        tf = true;
        return;
    end

    srcInfo = dir(liveCodeFile);
    dstInfo = dir(outputFile);

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

function localPostProcessMarkdown(mdFile, mFileName, logoHref)
    txt = fileread(mdFile);

    % Keep exactly one download link at the very beginning of the page. The
    % relative link works because the Markdown and MATLAB files are exported
    % to the same directory.
    downloadMarker = '<!-- matlab-script-download -->';
    downloadPattern = ['(?m)^' regexptranslate('escape', downloadMarker) ...
        '\r?\n[^\r\n]*\r?\n(?:\r?\n)?'];
    txt = regexprep(txt, downloadPattern, '');
    downloadBlock = sprintf([ ...
        '%s\n' ...
        '[:material-download: Download MATLAB script](./%s)' ...
        '{ .md-button .md-button--primary }\n\n'], ...
        downloadMarker, char(mFileName));
    txt = [downloadBlock char(txt)];

    txt = replace(txt, "\[", "[");
    txt = replace(txt, "\]", "]");
    txt = replace(txt, "\$", "$");
    txt = replace(txt, "\\", "\");
    txt = replace(txt, "\*", "*");
    txt = regexprep(txt, '[ \t]+(?=\r?\n)', '');

    % Replace colors explicitly embedded by the Live Editor with the theme's
    % primary color. Match only the CSS color property (not background-color)
    % so the result adapts automatically to the active light/dark palette.
    explicitColorPattern = ['(?i)(?<![-\w])color\s*:\s*' ...
        '(?:#[0-9a-f]{3,8}\b|' ...
        'rgba?\([^)]*\)|hsla?\([^)]*\))'];
    txt = regexprep(txt, explicitColorPattern, ...
        'color:var(--md-accent-fg-color)');

    % Normalize display equations exported by the Live Editor without
    % changing ordinary Markdown prose or inline math.
    txt = localNormalizeDisplayMathBlocks(txt);

    % MATLAB Live Editor export may duplicate blank lines inside code fences.
    % Normalize only fenced code blocks so normal Markdown paragraph spacing is
    % not affected.
    txt = localNormalizeBlankLinesInCodeFences(txt);

    % Keep the post-processed Markdown as a char vector before regexp-based
    % positional slicing. MATLAB string scalars use element indexing, not
    % character indexing, which can trigger "Index exceeds the number of array
    % elements" when start/end positions from regexp are used.
    txt = char(txt);

    txt = localReplaceLegacyOutputBlocks(txt, logoHref);
    txt = localReplaceMatlabTextOutputBlocks(txt, logoHref);

    % Run the fence normalization once more after output-block replacement.
    % This makes the final Markdown invariant explicit: ordinary code fences
    % never contain more than one consecutive blank line.
    txt = localNormalizeBlankLinesInCodeFences(txt);

    % Live Editor can retain a short-lived handle to a newly exported file on
    % Windows. Write the complete result beside the target and then replace it
    % with retries. This also prevents an interrupted rewrite from leaving a
    % truncated Markdown page.
    localReplaceTextFile(mdFile, txt);
end

function localExportLiveCode(sourceFile, targetFile, format)
    targetDir = fileparts(targetFile);
    [~, ~, targetExtension] = fileparts(targetFile);
    temporaryFile = string(tempname(targetDir)) + targetExtension;
    temporaryCleaner = onCleanup( ...
        @() localDeleteFileIfPresent(temporaryFile));

    if format == "markdown"
        export(sourceFile, temporaryFile, ...
            Format="markdown", ...
            EmbedImages=true, ...
            AcceptHTML=true);
    else
        export(sourceFile, temporaryFile, Format="m");
    end

    localMoveFileWithRetries(temporaryFile, targetFile);
    clear temporaryCleaner;
end

function localUpgradeLegacyExampleOutputs(rootDir)
    % Include older generated pages that are no longer in the active task list.
    markdownFiles = dir(fullfile(rootDir, "**", "*.md"));
    legacyMarker = '<div style="font-size:0.85em; color:var(--md-accent-fg-color);">';

    for i = 1:numel(markdownFiles)
        mdFile = fullfile(markdownFiles(i).folder, markdownFiles(i).name);
        txt = fileread(mdFile);
        if ~contains(txt, legacyMarker)
            continue;
        end

        relativeFolder = erase(string(markdownFiles(i).folder), string(rootDir));
        relativeParts = split(relativeFolder, filesep);
        relativeParts(relativeParts == "") = [];
        logoPrefix = repmat('../', 1, numel(relativeParts) + 1);
        logoHref = string(logoPrefix) + "static/images/matlab.svg";
        txt = localReplaceLegacyOutputBlocks(txt, logoHref);
        localReplaceTextFile(mdFile, txt);
    end
end

function localReplaceTextFile(targetFile, txt)
    targetDir = fileparts(targetFile);
    temporaryFile = string(tempname(targetDir)) + ".md";
    temporaryCleaner = onCleanup( ...
        @() localDeleteFileIfPresent(temporaryFile));

    [fid, openMessage] = fopen(temporaryFile, "w", "n", "UTF-8");
    if fid == -1
        error("Cannot create temporary Markdown file %s: %s", ...
            temporaryFile, openMessage);
    end

    fileCleaner = onCleanup(@() fclose(fid));
    writtenCount = fwrite(fid, txt, "char");
    clear fileCleaner; % Close the temporary file before replacing the target.

    if writtenCount ~= numel(txt)
        error("Incomplete Markdown write for %s (%d of %d characters).", ...
            targetFile, writtenCount, numel(txt));
    end

    localMoveFileWithRetries(temporaryFile, targetFile);
    clear temporaryCleaner;
end

function localMoveFileWithRetries(sourceFile, targetFile)
    maximumAttempts = 40;
    moveMessage = "";
    for attempt = 1:maximumAttempts
        [moveSucceeded, moveMessage] = movefile( ...
            sourceFile, targetFile, "f");
        if moveSucceeded
            return;
        end
        pause(0.1);
    end

    error("Cannot replace file after %.1f seconds: %s\n%s", ...
        maximumAttempts * 0.1, targetFile, moveMessage);
end

function localDeleteFileIfPresent(fileName)
    if exist(fileName, "file")
        try
            delete(fileName);
        catch
            % Preserve the original build error if temporary cleanup fails.
        end
    end
end

function txt = localNormalizeDisplayMathBlocks(txt)
    % Live Editor exports display math as "$$", a blank line, the formula,
    % another blank line, and "$$". It can also add Markdown escapes that are
    % not appropriate inside TeX math. Compact and repair only these blocks.
    txt = char(txt);
    pattern = '(?m)^\$\$[ \t]*\r?\n([\s\S]*?)\r?\n[ \t]*\$\$[ \t]*$';
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

        body = tokens{i}{1};
        body = regexprep(body, '^(?:[ \t]*\r?\n)+', '');
        body = regexprep(body, '(?:\r?\n[ \t]*)+$', '');
        body = strrep(body, '\*', '*');
        body = strrep(body, '\_', '_');

        pieces{p} = ['$$' newline body newline '$$'];
        p = p + 1;
        prevEnd = ends(i);
    end

    pieces{p} = txt(prevEnd + 1 : end);
    txt = [pieces{1:p}];
end

function txt = localNormalizeBlankLinesInCodeFences(txt)
    % Collapse duplicated blank lines only inside fenced code blocks.
    %
    % Problem:
    % MATLAB export(..., Format="markdown") can convert one blank line in a
    % source code cell into two blank lines in the generated Markdown code
    % fence. This function fixes that by changing two or more consecutive
    % blank lines inside normal fenced code blocks into one blank line.
    %
    % Important:
    % - This function does not change text outside code fences.
    % - matlabTextOutput fences are skipped because they are handled later by
    %   localReplaceMatlabTextOutputBlocks().
    % - The fence delimiter line itself is preserved.

    lines = splitlines(string(txt));
    outLines = strings(0, 1);

    inFence = false;
    currentFenceInfo = "";
    fenceBuffer = strings(0, 1);

    for i = 1:numel(lines)
        line = lines(i);
        trimmed = strtrim(line);

        isFenceLine = startsWith(trimmed, "```");

        if ~inFence
            if isFenceLine
                inFence = true;
                currentFenceInfo = extractAfter(trimmed, 3);
                fenceBuffer = line;
            else
                outLines(end + 1, 1) = line;
            end
        else
            fenceBuffer(end + 1, 1) = line;

            if isFenceLine
                % Close fence and normalize the buffered fence block.
                normalizedFence = localNormalizeOneFenceBlock( ...
                    fenceBuffer, currentFenceInfo);

                outLines = [outLines; normalizedFence]; %#ok<AGROW>

                inFence = false;
                currentFenceInfo = "";
                fenceBuffer = strings(0, 1);
            end
        end
    end

    % If the file has an unclosed fence, keep it safely and normalize it.
    if inFence && ~isempty(fenceBuffer)
        normalizedFence = localNormalizeOneFenceBlock( ...
            fenceBuffer, currentFenceInfo);
        outLines = [outLines; normalizedFence]; %#ok<AGROW>
    end

    txt = char(strjoin(outLines, newline));
end

function block = localNormalizeOneFenceBlock(block, fenceInfo)
    % Keep matlabTextOutput unchanged. These blocks are converted separately.
    if startsWith(strtrim(fenceInfo), "matlabTextOutput")
        return;
    end

    if numel(block) <= 2
        return;
    end

    firstLine = block(1);
    lastLine = block(end);
    body = block(2:end-1);

    normalizedBody = strings(0, 1);
    blankRun = 0;

    for i = 1:numel(body)
        line = body(i);

        if strlength(strtrim(line)) == 0
            blankRun = blankRun + 1;

            % Keep only one blank line for each blank-line run.
            if blankRun == 1
                normalizedBody(end + 1, 1) = "";
            end
        else
            blankRun = 0;
            normalizedBody(end + 1, 1) = line;
        end
    end

    block = [firstLine; normalizedBody; lastLine];
end

function txt = localReplaceMatlabTextOutputBlocks(txt, logoHref)
    % This function uses regexp start/end indices for slicing, so txt must be
    % a char vector. If txt is a MATLAB string scalar, txt(a:b) indexes string
    % array elements rather than characters.
    txt = char(txt);

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
        pieces{p} = localFormatOutputBlock(content, logoHref);
        p = p + 1;

        prevEnd = ends(i);
    end

    pieces{p} = txt(prevEnd + 1 : end);
    txt = [pieces{1:p}];
end

function txt = localReplaceLegacyOutputBlocks(txt, logoHref)
    % Upgrade output blocks generated by earlier versions of this script.
    % Keeping this migration here makes style changes effective without a
    % forced Live Editor export of every example.
    txt = char(txt);
    pattern = ['<div style="font-size:0\.85em; color:var\(--md-accent-fg-color\);">' ...
        '\s*<div style="font-weight:600;">Output</div>' ...
        '\s*<div style="white-space:pre-wrap; font-family:Consolas;">' ...
        '\s*([\s\S]*?)\s*</div>\s*</div>'];
    [starts, ends, tokens] = regexp(txt, pattern, "start", "end", "tokens");

    if isempty(starts)
        return;
    end

    pieces = cell(numel(starts) * 2 + 1, 1);
    previousEnd = 0;
    pieceIndex = 1;
    for i = 1:numel(starts)
        pieces{pieceIndex} = txt(previousEnd + 1 : starts(i) - 1);
        pieceIndex = pieceIndex + 1;

        content = localDecodeLegacyHtml(tokens{i}{1});
        pieces{pieceIndex} = localFormatOutputBlock(content, logoHref);
        pieceIndex = pieceIndex + 1;
        previousEnd = ends(i);
    end

    pieces{pieceIndex} = txt(previousEnd + 1 : end);
    txt = [pieces{1:pieceIndex}];
end

function value = localDecodeLegacyHtml(value)
    value = replace(string(value), "&lt;", "<");
    value = replace(value, "&gt;", ">");
    value = replace(value, "&amp;", "&");
end

function out = localFormatOutputBlock(content, logoHref)
    content = strip(string(content), "right");

    if strlength(content) == 0
        lines = strings(0, 1);
    else
        lines = splitlines(content);
    end

    lineCount = numel(lines);
    if lineCount == 1
        lineLabel = "line";
    else
        lineLabel = "lines";
    end
    visibleContent = localEscapeHtml(strjoin(lines, newline));

    block = "<div class=""example-output"">" + newline + ...
        "<div class=""example-output__header""><img class=""example-component__logo"" src=""" + ...
        logoHref + """ alt=""""><span>Run output</span><span class=""example-output__count"">" + ...
        lineCount + " " + lineLabel + "</span></div>" + newline + ...
        "<pre>" + visibleContent + "</pre>";

    out = char(block + newline + "</div>");
end

function localWriteExampleCard(fid, mdFile, title, pageHref, imageStem)
    [thumbnailHref, hasThumbnail] = localCreateGalleryThumbnail( ...
        mdFile, imageStem);
    plainTitle = localPlainTitle(title);
    htmlTitle = localEscapeHtml(plainTitle);

    if hasThumbnail
        mediaClass = "example-gallery__media";
    else
        mediaClass = "example-gallery__media example-gallery__media--placeholder";
    end

    fprintf(fid, '  <a class="example-gallery__card" href="%s">\n', ...
        pageHref);
    fprintf(fid, '    <span class="%s"><img src="%s" alt="%s preview" loading="lazy"></span>\n', ...
        mediaClass, thumbnailHref, htmlTitle);
    fprintf(fid, '    <span class="example-gallery__body"><strong>%s</strong>', ...
        htmlTitle);
    fprintf(fid, '<span class="example-gallery__interface">');
    fprintf(fid, '<img src="../../static/images/matlab.svg" alt=""><span>MATLAB</span>');
    fprintf(fid, '</span></span>\n  </a>\n');
end

function [thumbnailHref, hasThumbnail] = localCreateGalleryThumbnail( ...
        mdFile, imageStem)
    % Reuse the final rendered figure as the card preview without duplicating
    % its base64 data in index.md.
    txt = fileread(mdFile);
    sourceMarker = 'src="data:image/';
    sourceStarts = strfind(txt, sourceMarker);

    if isempty(sourceStarts)
        thumbnailHref = "../../static/images/matlab.svg";
        hasThumbnail = false;
        return;
    end

    sourceStart = sourceStarts(end) + strlength('src="');
    sourceTail = txt(sourceStart:end);
    sourceEnd = find(sourceTail == '"', 1) - 1;
    if isempty(sourceEnd)
        thumbnailHref = "../../static/images/matlab.svg";
        hasThumbnail = false;
        return;
    end

    dataUri = sourceTail(1:sourceEnd);
    imageParts = regexp(dataUri, ...
        '^data:image/([^;]+);base64,(.+)$', "tokens", "once");
    if isempty(imageParts)
        thumbnailHref = "../../static/images/matlab.svg";
        hasThumbnail = false;
        return;
    end

    mimeSubtype = lower(string(imageParts{1}));
    switch mimeSubtype
        case "jpeg"
            extension = ".jpg";
        case "svg+xml"
            extension = ".svg";
        case {"png", "gif", "webp"}
            extension = "." + mimeSubtype;
        otherwise
            thumbnailHref = "../../static/images/matlab.svg";
            hasThumbnail = false;
            return;
    end

    imageBytes = matlab.net.base64decode(imageParts{2});
    [mdDir, mdName] = fileparts(mdFile);
    thumbnailFile = fullfile(mdDir, mdName + "-thumbnail" + extension);
    [imageFile, openMessage] = fopen(thumbnailFile, "w");
    if imageFile == -1
        error("Cannot create gallery thumbnail %s: %s", ...
            thumbnailFile, openMessage);
    end
    imageCleaner = onCleanup(@() fclose(imageFile));
    writtenCount = fwrite(imageFile, imageBytes, "uint8");
    clear imageCleaner;

    if writtenCount ~= numel(imageBytes)
        error("Incomplete gallery thumbnail write for %s.", thumbnailFile);
    end

    thumbnailHref = imageStem + "-thumbnail" + extension;
    hasThumbnail = true;
end

function title = localPlainTitle(title)
    title = regexprep(string(title), '<[^>]+>', '');
    title = replace(title, ["**", "__", "`", "\"], "");
    title = strtrim(title);
end

function value = localEscapeHtml(value)
    value = replace(string(value), "&", "&amp;");
    value = replace(value, "<", "&lt;");
    value = replace(value, ">", "&gt;");
    value = replace(value, '"', "&quot;");
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

        case "opscmds"
            titleStr = "OpenSees command examples";
            introStr = "These examples demonstrate how to use the encapsulated OpenSees module for modeling and analysis.";

        case "verify"
            titleStr = "Verification Examples";
            introStr = "Examples of verification by reliable third-party software.";

        case "extension"
            titleStr = "Extended functionality by OpenSeesMatlab";
            introStr = "OpenSeesMatlab extends a range of functionalities, including *numerical substructure analysis* and a *GPU-based linear equation solver*.";

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

        case "extension"
            switch char(subgroup)
                case "substruct"
                    titleStr = "MATLAB Numerical Substructure Analysis";
                case "system"
                    titleStr = "Solver of equations for linear systems";
                case "material"
                    titleStr = "Connecting MATLAB's custom materials to the OpenSees domain";
                case "adaptiveAnalyze"
                    titleStr = "Adaptive Analysis";
                case "algorithm"
                    titleStr = "Nonlinear iterative algorithm";
                otherwise
                    titleStr = localPrettyTitle(subgroup);
            end

        case "opscmds"
            switch char(subgroup)
                case "structural"
                    titleStr = "Structural Examples";

                case "earthquake"
                    titleStr = "Earthquake Examples";

                case "geotechnical"
                    titleStr = "Geotechnical Examples";

                case "thermal"
                    titleStr = "Thermal Examples";

                case "sensitivity"
                    titleStr = "Sensitivity Examples";

                case "parallel"
                    titleStr = "Parallel Examples";
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
