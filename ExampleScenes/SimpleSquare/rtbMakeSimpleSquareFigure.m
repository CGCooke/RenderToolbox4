%%% RenderToolbox4 Copyright (c) 2012-2016 The RenderToolbox4 Team.
%%% About Us://github.com/DavidBrainard/RenderToolbox4/wiki/About-Us
%%% RenderToolbox4 is released under the MIT License.  See LICENSE.txt.
%
%% Make figure comparing rendered colors with expected colors.

%% Render the scene.
rtbMakeSimpleSquare();

%% Get the scene illuminant spectrum.
%   used for predicted pixel data
mappingsFile = 'SimpleSquareMappings.json';
mappings = rtbLoadJsonMappings(mappingsFile);
lightIndex = find(strcmp('lights', {mappings.broadType}), 1);
lightSpectrum = mappings(lightIndex).properties(1).value;
[lightWls, lightMags] = rtbReadSpectrum(lightSpectrum);


%% Get multi-spectral data for images and pixels of interest.
% choose how far to inset the pixel of interest
poiInset = 12;

% look in the conditions file for image names
conditionsFile = 'SimpleSquareConditions.txt';
[names, values] = rtbParseConditions(conditionsFile);
squareSpectrums = values(:, strcmp('squareColor', names));
nImages = numel(squareSpectrums);

% allocate structs of data and computations
pbrt = struct( ...
    'spectrum', squareSpectrums, ...
    'imageSpectral', [], ...
    'scaleSpectral', [], ...
    'imageSRGB', [], ...
    'S', [], ...
    'poiWls', [], ...
    'poiSpd', [], ...
    'poiXYZ', [], ...
    'poiSRGB', [], ...
    'poiLAB', [], ...
    'poiDiff', []);
mitsuba = pbrt;
predicted = pbrt;

% fill in multi-spectral data for each Color Checker condition.
hints.recipeName = 'rtbMakeSimpleSquare';
for ii = 1:nImages
    % seatch for data files by condition number
    imageNum = sprintf('scene-%03d', ii);
    
    % read PBRT square data from file
    hints.renderer = 'PBRT';
    dataFolder = rtbWorkingFolder(...
        'folderName', 'renderings', ...
        'rendererSpecific', true, ...
        'hints', hints);
    file = rtbFindFiles('root', dataFolder, 'filter', [imageNum '\.mat']);
    data = load(file{1});
    pbrt(ii).imageSpectral = data.multispectralImage;
    pbrt(ii).S = data.S;
    [pbrt(ii).poiWls, pbrt(ii).poiSpd] = rtbGetPixelSpectrum( ...
        data.multispectralImage, data.S, poiInset, poiInset);
    
    % read Mitsuba square data from file
    hints.renderer = 'Mitsuba';
    dataFolder = rtbWorkingFolder(...
        'folderName', 'renderings', ...
        'rendererSpecific', true, ...
        'hints', hints);
    file = rtbFindFiles('root', dataFolder, 'filter', [imageNum '.mat']);
    data = load(file{1});
    mitsuba(ii).imageSpectral = data.multispectralImage;
    mitsuba(ii).S = data.S;
    [mitsuba(ii).poiWls, mitsuba(ii).poiSpd] = rtbGetPixelSpectrum( ...
        data.multispectralImage, data.S, poiInset, poiInset);
    
    % compute predicted pixel of interest
    %   get the square's reflectance spectrum
    %   multiply reflectance with the light spectrum
    %   resample as needed
    predicted(ii).S = pbrt(ii).S;
    predicted(ii).poiWls = MakeItWls(predicted(ii).S);
    [squareWls, squareSrf] = rtbReadSpectrum(squareSpectrums{ii});
    squareSrfResampled = SplineSrf(squareWls, squareSrf, lightWls);
    predictedSpectrum = lightMags .* squareSrfResampled;
    predicted(ii).poiSpd = SplineSpd(lightWls, predictedSpectrum, predicted(ii).S);
end

%% Determine scaling to match renderers with predicted multi-spectral data.
pbrtDump = [pbrt.poiSpd];
mitsubaDump = [mitsuba.poiSpd];
predictedDump = [predicted.poiSpd];

[pbrt.scaleSpectral] = deal(pbrtDump(:) \ predictedDump(:));
[mitsuba.scaleSpectral] = deal(mitsubaDump(:) \ predictedDump(:));
[predicted.scaleSpectral] = deal(1);

%% Determine scaling to convert multi-spectral data to nice sRGB.
tinyImage = reshape(predicted(4).poiSpd, 1, 1, []);
[sRGB, XYZ, rawRGB] = rtbMultispectralToSRGB(tinyImage, predicted(4).S);
maxSRGB = .95;
scaleSRGB = maxSRGB / max(rawRGB(:));

%% Convert images and pixels of interest to XYZ, sRGB, and CIE LAB.
% use the predicted white pixel of interest as the LAB "standard white"
whiteSpd = predicted(4).poiSpd * predicted(ii).scaleSpectral * scaleSRGB;
[whiteSRGB, whiteXYZ] = rtbMultispectralToSRGB(reshape(whiteSpd, 1, 1, []), predicted(4).S);
whiteXYZ = squeeze(whiteXYZ);
for ii = 1:nImages
    % predicted pixel of interest
    spd = predicted(ii).poiSpd * predicted(ii).scaleSpectral * scaleSRGB;
    [sRGB, XYZ, rawRGB] = rtbMultispectralToSRGB(reshape(spd, 1, 1, []), predicted(ii).S);
    predicted(ii).poiSRGB = squeeze(sRGB);
    predicted(ii).poiXYZ = squeeze(XYZ);
    predicted(ii).poiLAB = XYZToLab(predicted(ii).poiXYZ, whiteXYZ);
    predicted(ii).poiDiff = 0;
    
    % PBRT image and pixel of interest
    imageSpectral = pbrt(ii).imageSpectral * pbrt(ii).scaleSpectral * scaleSRGB;
    pbrt(ii).imageSRGB = rtbMultispectralToSRGB(imageSpectral, pbrt(ii).S);
    spd = pbrt(ii).poiSpd * pbrt(ii).scaleSpectral * scaleSRGB;
    [sRGB, XYZ] = rtbMultispectralToSRGB(reshape(spd, 1, 1, []), pbrt(ii).S);
    pbrt(ii).poiSRGB = squeeze(sRGB);
    pbrt(ii).poiXYZ = squeeze(XYZ);
    pbrt(ii).poiLAB = XYZToLab(pbrt(ii).poiXYZ, whiteXYZ);
    pbrt(ii).poiDiff = ComputeDE(predicted(ii).poiLAB, pbrt(ii).poiLAB);
    
    % Mitsuba image and pixel of interest
    imageSpectral = mitsuba(ii).imageSpectral * mitsuba(ii).scaleSpectral * scaleSRGB;
    mitsuba(ii).imageSRGB = rtbMultispectralToSRGB(imageSpectral, mitsuba(ii).S);
    spd = mitsuba(ii).poiSpd * mitsuba(ii).scaleSpectral * scaleSRGB;
    [sRGB, XYZ] = rtbMultispectralToSRGB(reshape(spd, 1, 1, []), mitsuba(ii).S);
    mitsuba(ii).poiSRGB = squeeze(sRGB);
    mitsuba(ii).poiXYZ = squeeze(XYZ);
    mitsuba(ii).poiLAB = XYZToLab(mitsuba(ii).poiXYZ, whiteXYZ);
    mitsuba(ii).poiDiff = ComputeDE(predicted(ii).poiLAB, mitsuba(ii).poiLAB);
end

%% Create a Frankenstein montage from PBRT, Mitsuba, and predicted patches.
% choose dimensions and allocate montage matrix
tileWidth = size(pbrt(1).imageSpectral, 1);
tileRows = 4;
tileCols = 6;
frankensteinMontage = zeros(tileRows*tileWidth, tileCols*tileWidth, 3);

% choose how to assemble each tile from PBRT, Mitsuba, and predictions
patchWidth = floor(tileWidth/3);
splitPatch = floor((tileWidth - patchWidth) / 2) + (1:patchWidth);
splitPBRT = 1:floor((tileWidth-1) / 2);
splitMitsuba = ceil((tileWidth+1) / 2):tileWidth;

for ii = 1:nImages
    % locate the current montage tile
    row = mod(ii-1, tileRows);
    col = floor((ii-1) / tileRows);
    xCorner = col*tileWidth;
    yCorner = row*tileWidth;
    
    % insert the PBRT sRGB image
    x = xCorner + (1:tileWidth);
    y = yCorner + splitPBRT;
    frankensteinMontage(y, x, :) = pbrt(ii).imageSRGB(splitPBRT, :, :);
    
    % insert the Mitsuba sRGB image
    x = xCorner + (1:tileWidth);
    y = yCorner + splitMitsuba;
    frankensteinMontage(y, x, :) = mitsuba(ii).imageSRGB(splitMitsuba, :, :);
    
    % insert a patch of the predicted color
    %   with a black border
    tinyImage = reshape(predicted(ii).poiSRGB, 1, 1, 3);
    predictedPatch = repmat(tinyImage, patchWidth, patchWidth);
    predictedPatch([1 patchWidth], :, :) = 0;
    predictedPatch(:, [1 patchWidth], :) = 0;
    x = xCorner + splitPatch;
    y = yCorner + splitPatch;
    frankensteinMontage(y, x, :) = predictedPatch;
end


%% Show the montage in a figure.
fig = figure();
clf(fig);
set(fig, 'Name', 'SimpleSquare');
labelSize = 14;

% show the Frankenstein montage!
axMontage = subplot(2, 1, 1, 'Parent', fig);
image(uint8(frankensteinMontage), 'Parent', axMontage);

% label components of the top left tile
yTick = [poiInset tileWidth/2 tileWidth-poiInset];
yTickLabel = {'PBRT', 'predicted', 'Mitsuba'};
set(axMontage, ...
    'YTick', yTick, ...
    'YTickLabel', yTickLabel, ...
    'XTick', [], ...
    'DataAspectRatio', [1 1 1], ...
    'TickLength', [0 0]);

% label the pixels of interest
pbrtColor = [1 0.5 0];
pbrtMarker = 'square';
mitsubaColor = [0 0 1];
mitsubaMarker = '+';
line(poiInset, poiInset, ...
    'Parent', axMontage, ...
    'Color', pbrtColor, ...
    'Marker', pbrtMarker, ...
    'MarkerSize', 7, ...
    'LineWidth', 1, ...
    'LineStyle', 'none');
line(tileWidth-poiInset, tileWidth-poiInset, ...
    'Parent', axMontage, ...
    'Color', mitsubaColor, ...
    'Marker', mitsubaMarker, ...
    'MarkerSize', 12, ...
    'LineWidth', 1, ...
    'LineStyle', 'none');

%% Add a plot of pixel of interest spectral data.
wMin = 400;
wMax = 700;
axSpectra = subplot(2, 2, 3, ...
    'Parent', fig, ...
    'XTick', wMin:100:wMax, ...
    'XLim', [wMin wMax] + [-10 +10], ...
    'YLim', [0 1.1], ...
    'YTick', [0 1], ...
    'YTickLabel', {'0', 'max'});
ylabel(axSpectra, 'SPD', 'FontSize', labelSize);
xlabel(axSpectra, 'wavelength (nm)', 'FontSize', labelSize);

% choose representative colors
representatives = [24 3 7 11];
for ii = representatives
    poiSpd = predicted(ii).poiSpd * predicted(ii).scaleSpectral;
    predictedMax = max(poiSpd);
    line(predicted(ii).poiWls, poiSpd / predictedMax, ...
        'Parent', axSpectra, ...
        'Color', predicted(ii).poiSRGB/255, ...
        'Marker', 'none', ...
        'LineStyle', '-', ...
        'LineWidth', 1, ...
        'HandleVisibility', 'off');
    poiSpd = pbrt(ii).poiSpd * pbrt(ii).scaleSpectral;
    line(pbrt(ii).poiWls, poiSpd / predictedMax, ...
        'Parent', axSpectra, ...
        'Color', pbrt(ii).poiSRGB/255, ...
        'Marker', pbrtMarker, ...
        'MarkerSize', 7, ...
        'LineStyle', 'none', ...
        'HandleVisibility', 'off');
    poiSpd = mitsuba(ii).poiSpd * mitsuba(ii).scaleSpectral;
    line(mitsuba(ii).poiWls, poiSpd / predictedMax, ...
        'Parent', axSpectra, ...
        'Color', mitsuba(ii).poiSRGB/255, ...
        'Marker', mitsubaMarker, ...
        'MarkerSize', 12, ...
        'LineStyle', 'none', ...
        'HandleVisibility', 'off');
end

% make a legend with ofscreen lines, to control colors
offScreen = -10;
line(offScreen, offScreen, ...
    'Parent', axSpectra, ...
    'Color', 0.3*[1 1 1], ...
    'Marker', 'none', ...
    'LineStyle', '-', ...
    'LineWidth', 1);
line(offScreen, offScreen, ...
    'Parent', axSpectra, ...
    'Color', pbrtColor, ...
    'Marker', pbrtMarker, ...
    'MarkerSize', 7, ...
    'LineStyle', 'none');
line(offScreen, offScreen, ...
    'Parent', axSpectra, ...
    'Color', mitsubaColor, ...
    'Marker', mitsubaMarker, ...
    'MarkerSize', 12, ...
    'LineStyle', 'none');
legend(axSpectra, 'predicted', 'PBRT', 'Mitsuba', 'Location', 'southwest')

%% Add a plot of CIE LAB distances.
axLAB = subplot(2, 2, 4, ...
    'Parent', fig, ...
    'YLim', [0 1.1], ...
    'YTick', [0 1], ...
    'XTick', [1 5:5:24 24], ...
    'XLim', [0 25]);
ylabel(axLAB, 'LAB distance', 'FontSize', labelSize);
xlabel(axLAB, 'tile number', 'FontSize', labelSize);
for ii = 1:nImages
    % make a non-white background for the white points
    if ii == 4
        bgColor = [0 0 0];
        bgWidth = 5;
        line(ii, pbrt(ii).poiDiff, ...
            'Parent', axLAB, ...
            'Color', bgColor, ...
            'Marker', pbrtMarker, ...
            'MarkerSize', 7, ...
            'LineStyle', 'none', ...
            'LineWidth', bgWidth, ...
            'HandleVisibility', 'off');
        line(ii, mitsuba(ii).poiDiff, ...
            'Parent', axLAB, ...
            'Color', bgColor, ...
            'Marker', mitsubaMarker, ...
            'MarkerSize', 12, ...
            'LineStyle', 'none', ...
            'LineWidth', bgWidth, ...
            'HandleVisibility', 'off');
    end
    
    color = predicted(ii).poiSRGB/255;
    width = 1;
    line(ii, pbrt(ii).poiDiff, ...
        'Parent', axLAB, ...
        'Color', color, ...
        'Marker', pbrtMarker, ...
        'MarkerSize', 7, ...
        'LineStyle', 'none', ...
        'LineWidth', width, ...
        'HandleVisibility', 'off');
    line(ii, mitsuba(ii).poiDiff, ...
        'Parent', axLAB, ...
        'Color', color, ...
        'Marker', mitsubaMarker, ...
        'MarkerSize', 12, ...
        'LineStyle', 'none', ...
        'LineWidth', width, ...
        'HandleVisibility', 'off');
end
% make a legend with ofscreen lines, to control colors
offScreen = -10;
line(offScreen, offScreen, ...
    'Parent', axLAB, ...
    'Color', pbrtColor, ...
    'Marker', pbrtMarker, ...
    'MarkerSize', 7, ...
    'LineStyle', 'none');
line(offScreen, offScreen, ...
    'Parent', axLAB, ...
    'Color', mitsubaColor, ...
    'Marker', mitsubaMarker, ...
    'MarkerSize', 12, ...
    'LineStyle', 'none');
legend(axLAB, 'PBRT', 'Mitsuba', 'Location', 'northeast')

%% Size the figure to show montage at native resolution.
w = 782;
h = 587;
p = get(fig, 'Position');
p(3:4) = [w h];
set(fig, 'Position', p);
