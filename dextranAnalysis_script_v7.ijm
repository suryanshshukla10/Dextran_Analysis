close("*");
run("Clear Results");
roiManager("reset");

setBatchMode(true); // << Turn ON batch mode here

// === Define main paths ===
// TODO: Update these paths based on your system
mainFolder = "C:/Path/To/Your/Input/Images/";
outputFolder = "C:/Path/To/Your/Output/Folder/";


// Create the results table
Table.create("Combined Results");

// Get list of all subfolders (e.g., FOV1, FOV2...)
subfolders = getFileList(mainFolder);

// === Loop through each FOV folder ===

for (f = 0; f < subfolders.length; f++) {
	
    subfolderName = subfolders[f];
    subfolderPath = mainFolder + subfolderName;
    
    // Skip files, process only folders
    if (File.isDirectory(subfolderPath)) {
        // Make output subfolder (if doesn't exist)
        outputSubfolder = outputFolder + subfolderName;
        File.makeDirectory(outputSubfolder);
        
        fileList = getFileList(subfolderPath);

        for (i = 0; i < fileList.length; i++) {
            currentFile = subfolderPath + fileList[i];
            if (endsWith(currentFile, ".jpg")) {
            	print("Processing: " + subfolderName + "/" + fileList[i]); // progress bar
                dextranMask(currentFile, fileList[i], outputSubfolder, subfolderName); // use subfolder output
                close("*");
//                break; 
            }
    
        }

    }
//    break; 
}

// Save the final combined results table

//saveAs("Results", outputFolder + "Combined_Area_Results.csv");

setBatchMode(false); // Turn OFF batch mode


selectWindow("Combined Results");
saveAs("Combined Results", outputFolder + "Combined_Area_Results.csv");


// === Functions ===

function dextranMask(currentFOV, fileName, OUTPUT_folder_path, folderName) {
    loadFile(currentFOV, fileName);
    renameSplitChannels(fileName);

    endomucin_threshold = 30;
    dextran_threshold = 25;
    dapi_threshold = 25;

    createEndomucinROIs(endomucin_threshold);
    createDextranROI(dextran_threshold);
    createExtravascularDextranROI();

    dapiArea        = calculateDAPIarea(fileName, dapi_threshold, OUTPUT_folder_path);
    endomucin_area  = measureAreaByName("BV");
    dextran_area    = measureAreaByName("DEX");
    overlap_area    = measureAreaByName("EX-DEX");
	
//	print("dapiArea", dapiArea);
//	print("endomucin_area", endomucin_area);
//	print("dextran_area", dextran_area);
//	print("overlap_area", overlap_area);
	
    drawDextranOverlay("Dextran", "Dextran Overlay", OUTPUT_folder_path, fileName); // save mask files

    // Append to Combined Results table
    row = Table.size("Combined Results");
    Table.set("Sample", row, folderName);
    Table.set("FOV", row, replace(fileName, ".jpg", ""));
    Table.set("DAPI Area", row, dapiArea);
    Table.set("Endomucin Area", row, endomucin_area);
    Table.set("Dextran Area", row, dextran_area);
    Table.set("EX-DEX Area", row, overlap_area);


}

function loadFile(fovPath, baseName) {
    open(fovPath);
    run("Split Channels");
}

function renameSplitChannels(baseName) {
    selectImage(baseName + " (red)");   rename("Endomucin");
    selectImage(baseName + " (green)"); rename("Dextran");
    selectImage(baseName + " (blue)");  rename("DAPI");
}

function createEndomucinROIs(thresh) {
    selectImage("Endomucin");
    run("8-bit");
    setAutoThreshold("Default dark no-reset");
    setThreshold(thresh, 255);
    run("Convert to Mask");
    run("Fill Holes");
    run("Create Selection");

    roiManager("reset");
    roiManager("Add"); roiManager("Select", 0); roiManager("Rename", "BV");

    selectImage("Endomucin");
    run("Make Inverse");

    roiManager("Add"); roiManager("Select", 1); roiManager("Rename", "EX-BV");
}

function createDextranROI(thresh) {
    selectImage("Dextran");
    run("8-bit");
    setAutoThreshold("Default dark no-reset");
    setThreshold(thresh, 255);
    run("Convert to Mask");
    run("Create Selection");
    roiManager("Add");
    roiManager("Select", 2);
    roiManager("Rename", "DEX");
}

function createExtravascularDextranROI() {
    roiManager("Select", newArray(1, 2));
    roiManager("AND");
    roiManager("Add");
    roiManager("Select", 3);
    roiManager("Rename", "EX-DEX");
}

function calculateDAPIarea(fileName, thresh, save_dir) {
    // --- Clear previous measurements ---
    run("Clear Results");

    // --- Prepare DAPI channel ---
    selectWindow("DAPI");
    run("8-bit");
    setAutoThreshold("Default dark no-reset");
    setThreshold(thresh, 255);
    run("Convert to Mask");

    // --- Save DAPI mask ---
    base     = replace(fileName, ".jpg", "");
    saveName = base + "_DAPI_mask.tif";
    savePath = save_dir + saveName;
    saveAs("Tiff", savePath);

    // --- Analyze particles ---
    run("Analyze Particles...", "size=0-Infinity exclude display clear summarize");

    // --- Sum all areas in Results table ---
    n         = nResults();
    totalArea = 0;
    for (i = 0; i < n; i++) {
        totalArea += getResult("Area", i);
    }

    return totalArea;
}

function measureAreaByName(roi_name) {
    run("Clear Results");

    if (roi_name == "BV")      { roiManager("Select", 0); roiManager("Measure"); return getResult("Area", 0); }
    if (roi_name == "EX-BV")   { roiManager("Select", 1); roiManager("Measure"); return getResult("Area", 0); }
    if (roi_name == "DEX")     { roiManager("Select", 2); roiManager("Measure"); return getResult("Area", 0); }
    if (roi_name == "EX-DEX")  { roiManager("Select", 3); roiManager("Measure"); return getResult("Area", 0); }

    print("ROI not found: " + roi_name);
    return -1;
}

function drawDextranOverlay(referenceWindow, overlayName, saveDir, baseFilename) {
    if (isOpen(overlayName)) close(overlayName);
    roiManager("deselect");

    selectWindow(referenceWindow);
    width = getWidth(); height = getHeight();
    newImage(overlayName, "RGB black", width, height, 1);

    selectWindow(overlayName);
    roiManager("Select", 0); setColor(255, 0, 0);     run("Fill", "slice"); // Red = BV
    roiManager("Select", 3); setColor(255, 255, 0);   run("Fill", "slice"); // Yellow = EX-DEX

    cleanBase = replace(baseFilename, ".jpg", "");
    savePath = saveDir + cleanBase + "_DextranOverlay.tif";
    saveAs("Tiff", savePath);
}
