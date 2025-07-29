//
//  main.swift
//  imagextract
//
//  Created by Karie Moorman on 7/22/25.
//

import Vision
import Cocoa
import Foundation
import CoreGraphics
import CoreML


// Function that executes all tasks: face extraction, YOLO, OCR, RESNET classification
func processImageAndSaveResults(from imagePath: String, saveTo subdirPath: URL) {
    guard let image = loadImage(from: imagePath) else {
        print("[ERROR] Failed to load image at \(imagePath)")
        return
    }
    
    guard let cgImage = getCGImage(from: image) else {
        print("[ERROR] Failed to convert image to CGImage")
        return
    }
    
    let fileName = (imagePath as NSString).lastPathComponent
    saveImageToSubdir(image, to: subdirPath, with: fileName)
    
    let checked = "✅"
    
    // Perform OCR on image using Apple Vision model (VNRecognizeTextRequest)
    performOCR(on: cgImage, saveTo: subdirPath)
    print("\nOCR: \(checked)")

    // Perform face extraction on image using Apple Vision model (VNFaceObservation)
    performFaceDetection(on: cgImage, saveTo: subdirPath)
    print("Face Detection: \(checked)")

    // Perform object classification on image using YOLO model
    performYOLOObjectClassification(on: cgImage, saveTo: subdirPath)
    print("YOLO Object Detection: \(checked)")
    
    // Perform object classification on using RESNET model
    performRESNETObjectClassification(on: cgImage, saveTo: subdirPath)
    print("RESNET Object Detection: \(checked)")
}


// Function to perform face extraction using VNFaceObservation
func performFaceDetection(on cgImage: CGImage, saveTo subdirPath: URL) {
    let faceDetectionRequest = VNDetectFaceRectanglesRequest { request, error in
        if let error = error {
            print("[ERROR] Error detecting faces: \(error)")
            return
        }
        
        guard let results = request.results as? [VNFaceObservation] else { return }
        
        var faceCount = 0
        for face in results {

            let boundingBox = face.boundingBox
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            let faceRect = CGRect(x: boundingBox.origin.x * width,
                                  y: (1 - boundingBox.origin.y - boundingBox.height) * height,
                                  width: boundingBox.width * width,
                                  height: boundingBox.height * height)

            let enlargementFactor: CGFloat = 1.25
            
            let expandedFaceRect = faceRect.insetBy(dx: -faceRect.width * (enlargementFactor - 1) / 2,
                                                    dy: -faceRect.height * (enlargementFactor - 1) / 2)
            
            let safeExpandedRect = expandedFaceRect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
            
            if let croppedFace = cropImage(cgImage: cgImage, toRect: safeExpandedRect) {
                saveCroppedFace(croppedFace, count: &faceCount, to: subdirPath)
            }
        }
    }
    
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([faceDetectionRequest])
    
}


// Function to perform OCR using VNRecognizeTextRequest
func performOCR(on cgImage: CGImage, saveTo subdirPath: URL) {
    let ocrRequest = VNRecognizeTextRequest { request, error in
        if let error = error {
            print("[ERROR] Error recognizing text: \(error)")
            return
        }
        
        guard let results = request.results as? [VNRecognizedTextObservation] else { return }
        
        var recognizedText = ""
        for observation in results {
            if let topCandidate = observation.topCandidates(1).first {
                recognizedText += topCandidate.string + "\n"
            }
        }
        
        if !recognizedText.isEmpty {
            saveRecognizedText(recognizedText, to: subdirPath)
        }
    }

    ocrRequest.recognitionLevel = .accurate 
    //ocrRequest.recognitionLanguages = ["en"]
    ocrRequest.usesLanguageCorrection = true 
    
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([ocrRequest])
}


// Function to load ML model for object detection task
func createImageClassifier(modelpath: String) -> VNCoreMLModel? {
    let executableURL = resolveExecutablePath()
    let executableDir = executableURL.deletingLastPathComponent()
    let modelURL = executableDir.appendingPathComponent(modelpath)

    guard let model = try? MLModel(contentsOf: modelURL) else {
    fatalError("[ERROR] Could not load the model. Please verify model path and retry.")
    }

    do {
        let visionModel = try VNCoreMLModel(for: model)
        return visionModel
    } catch {
        print("[ERROR] Failed to load the model: \(error.localizedDescription)")
        return nil
    }
}


// Function to perform object classification using a RESNET Core ML model
func performRESNETObjectClassification(on cgImage: CGImage, saveTo subdirPath: URL) {
    do {
        guard let visionModel = createImageClassifier(modelpath: "models/Resnet50.mlmodelc") else {
        print("[ERROR] Vision model could not be created.")
        return
    }

        let classificationRequest = VNCoreMLRequest(model: visionModel) { request, error in
            if let error = error {
                print("[ERROR] Error classifying objects: \(error)")
                return
            }
            
            guard let results = request.results as? [VNClassificationObservation] else { return }
            
            var classificationResults = ""
            for classification in results {
                classificationResults += "Class: \(classification.identifier), Confidence: \(classification.confidence * 100)%\n"
            }
            
            if !classificationResults.isEmpty {
                saveRESNETClassificationResults(classificationResults, to: subdirPath)
            }
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([classificationRequest])
        
    } catch {
        print("[ERROR] Failed to load Core ML model: \(error)")
    }
}


//Function to save object classification results to a file
func saveRESNETClassificationResults(_ results: String, to directory: URL) {
    let fileName = "RESNET_ObjectClassificationResults.txt"
    let filePath = directory.appendingPathComponent(fileName)
    do {
        try results.write(to: filePath, atomically: true, encoding: .utf8)
    } catch {
        print("[ERROR] Error saving classification results: \(error)")
    }
}


// Function to perform object classification using a YOLO Core ML model
func performYOLOObjectClassification(on cgImage: CGImage, saveTo subdirPath: URL) {
    do {
        guard let visionModel = createImageClassifier(modelpath: "models/yolov5m.mlmodelc") else {
        print("[ERROR] Vision model could not be created.")
        return
        }

        let classificationRequest = VNCoreMLRequest(model: visionModel) { request, error in
            if let error = error {
                print("[ERROR] Error performing object detection: \(error)")
                return
            }
            
            guard let results = request.results as? [VNRecognizedObjectObservation] else { return }

            var detectionResults: [YOLOClassificationResult] = []
            var objectCount = 0

            for observation in results {
                if let topLabel = observation.labels.first {
                    let classIdentifier = topLabel.identifier
                    let confidence = topLabel.confidence * 100
                    let boundingBox = observation.boundingBox
                    
                    let result = YOLOClassificationResult(
                        objectNumber: objectCount,
                        className: classIdentifier,
                        confidence: confidence,
                        boundingBox: [boundingBox.origin.x, boundingBox.origin.y, boundingBox.width, boundingBox.height],
                        imageFileName: "Object\(objectCount).png"
                    )
                    
                    detectionResults.append(result)
                    
                    let width = CGFloat(cgImage.width)
                    let height = CGFloat(cgImage.height)
                    let rect = CGRect(
                        x: boundingBox.origin.x * width,
                        y: (1 - boundingBox.origin.y - boundingBox.height) * height,
                        width: boundingBox.width * width,
                        height: boundingBox.height * height
                    )
                    
                    if let croppedImage = cropYOLOImage(cgImage: cgImage, toRect: rect) {
                        saveYOLOObjectScreenshot(croppedImage, objectCount: &objectCount, to: subdirPath)
                    }
                }
            }
            
            if !detectionResults.isEmpty {
                saveYOLOClassificationResults(detectionResults, to: subdirPath)
            }
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([classificationRequest])

    } catch {
        print("[ERROR] Failed to load YOLO model: \(error)")
    }
}


struct YOLOClassificationResult: Codable {
    let objectNumber: Int
    let className: String
    let confidence: Float
    let boundingBox: [Double]
    let imageFileName: String
}


// Function to save the classification results to a JSON file
func saveYOLOClassificationResults(_ results: [YOLOClassificationResult], to directory: URL) {
    let fileName = "YOLO_ObjectClassificationResults.json"
    let filePath = directory.appendingPathComponent(fileName)
    
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let jsonData = try encoder.encode(results)
        
        try jsonData.write(to: filePath, options: .atomic)
    } catch {
        print("[ERROR] Error saving classification results: \(error)")
    }
}


// Function to crop the YOLO image based on a bounding box
func cropYOLOImage(cgImage: CGImage, toRect rect: CGRect) -> CGImage? {
    
    let scaledRect = CGRect(
        x: rect.origin.x,
        y: rect.origin.y,
        width: rect.width,
        height: rect.height
    )

    guard let croppedCGImage = cgImage.cropping(to: scaledRect) else {
        print("[ERROR] Failed to crop image at \(scaledRect)")
        return nil
    }
    
    return croppedCGImage
}


// Function to save the YOLO cropped object as a screenshot
func saveYOLOObjectScreenshot(_ croppedImage: CGImage, objectCount: inout Int, to directory: URL) {
    
    let fileName = "Object\(objectCount).png"
    let croppedNSImage = NSImage(cgImage: croppedImage, size: CGSize(width: CGFloat(croppedImage.width), height: CGFloat(croppedImage.height)))
    
    saveImageToSubdir(croppedNSImage, to: directory, with: fileName)
    
    objectCount += 1
}


// Function to save recognized text to a file
func saveRecognizedText(_ text: String, to directory: URL) {
    let fileName = "OCR_RecognizedText.txt"
    let filePath = directory.appendingPathComponent(fileName)
    
    do {
        try text.write(to: filePath, atomically: true, encoding: .utf8)
    } catch {
        print("[ERROR] Error saving recognized text: \(error)")
    }
    
}


// Function to load an image from the file system
func loadImage(from path: String) -> NSImage? {
    let url = URL(fileURLWithPath: path)
    return NSImage(contentsOf: url)
}


// Function to convert NSImage to CGImage
func getCGImage(from nsImage: NSImage) -> CGImage? {
    guard let tiffData = nsImage.tiffRepresentation else {
        print("[ERROR] Failed to get TIFF representation of image.")
        return nil
    }
    
    guard let bitmapRep = NSBitmapImageRep(data: tiffData) else {
        print("[ERROR] Failed to create bitmap representation of image.")
        return nil
    }
    
    return bitmapRep.cgImage
}


// Function to crop face images based on a bounding box
func cropImage(cgImage: CGImage, toRect rect: CGRect) -> NSImage? {
    guard let croppedCGImage = cgImage.cropping(to: rect) else {
        print("[ERROR] Failed to crop image.")
        return nil
    }
    return NSImage(cgImage: croppedCGImage, size: rect.size)
}


// Function to save cropped faces as PNG files
func saveCroppedFace(_ faceImage: NSImage, count: inout Int, to directory: URL) {
    let fileName = "Face\(count).png"
    
    saveImageToSubdir(faceImage, to: directory, with: fileName)
    count += 1
}


// Function to create a subdirectory in the user's Documents directory
func createSubdirectory(subdirectoryName: String) -> URL? {
    let documentsDirectory = getDocumentsDirectory()
    let subdirectoryPath = documentsDirectory.appendingPathComponent(subdirectoryName)
    
    do {
        if !FileManager.default.fileExists(atPath: subdirectoryPath.path) {
            try FileManager.default.createDirectory(at: subdirectoryPath, withIntermediateDirectories: true, attributes: nil)
            print("\n[INFO] Subdirectory created at: \(subdirectoryPath.path)")
        } else {
            print("\n[WARNING] Subdirectory already exists at: \(subdirectoryPath.path)")
        }
        
        return subdirectoryPath
    } catch {
        print("\n[ERROR] Error creating subdirectory: \(error)")
        return nil
    }
}


// Function to save image data to a subdirectory
func saveImageToSubdir(_ image: NSImage, to subdirPath: URL, with fileName: String) {

    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: subdirPath.path) {
        do {
            try fileManager.createDirectory(at: subdirPath, withIntermediateDirectories: true, attributes: nil)
            print("[INFO] Created subdirectory at \(subdirPath.path)")
        } catch {
            print("[ERROR] Failed to create subdirectory: \(error)")
            return
        }
    }
    
    let filePath = subdirPath.appendingPathComponent(fileName)
    
    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("[ERROR] Failed to convert image to PNG.")
        return
    }

    do {
        try pngData.write(to: filePath)
    } catch {
        print("[ERROR] Failed to save image: \(error)")
    }
}


// Function to get the filename without extension
func getFilenameWithoutExtension(from filePath: String) -> String {
    let url = URL(fileURLWithPath: filePath)
    return url.deletingPathExtension().lastPathComponent
}


// Function to get the user's Documents directory
func getDocumentsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    return paths[0]
}

// Function to validate image file extension
func isValidExtension(for file: String, for allowedExtensions: Set<String>) -> Bool {
    let fileURL = URL(fileURLWithPath: file)
    let fileExtension = fileURL.pathExtension.lowercased()
    return allowedExtensions.contains(".\(fileExtension)")
}

func resolveExecutablePath() -> URL {
    let argv0 = CommandLine.arguments[0]
    let fileManager = FileManager.default

    if argv0.hasPrefix("/") {
        return URL(fileURLWithPath: argv0)
    } else if argv0.contains("/") {
        let cwd = fileManager.currentDirectoryPath
        return URL(fileURLWithPath: cwd).appendingPathComponent(argv0)
    } else {
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in envPath.split(separator: ":") {
            let fullPath = "\(dir)/\(argv0)"
            if fileManager.isExecutableFile(atPath: fullPath) {
                return URL(fileURLWithPath: fullPath)
            }
        }
    }

    fatalError("[ERROR] Could not resolve executable path.")
}



func main() {
    
    let arguments = CommandLine.arguments
    guard arguments.count == 2 else {
        print("\n[ERROR] Usage: \(arguments[0]) <image_path>")
        return
    }
    
    let imagePath = arguments[1]
    let allowedExtensions = Set([".jpg", ".jpeg", ".png", ".tiff", ".pdf"])
    
    if !isValidExtension(for: imagePath, for: allowedExtensions) {
        print("\n[ERROR] The file \(imagePath) does not have a valid extension. Only the following extensions are allowed: \(allowedExtensions.joined(separator: ", "))")
        return
    }
        
    let subdirectoryName = getFilenameWithoutExtension(from: imagePath)
    
    if let subdirPath = createSubdirectory(subdirectoryName: subdirectoryName) {
        processImageAndSaveResults(from: imagePath, saveTo: subdirPath)
    }
    print("\n[INFO] Image Processing Task Complete.\n")
}


main()
