import Flutter
import Foundation
import libtesseract

#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#else
import onnxruntime_objc
#endif

public final class KhmerIdCardOcrPlugin: NSObject, FlutterPlugin {
    private let queue = DispatchQueue(label: "dev.khmerocr.ocr", qos: .userInitiated)
    private let modelPath: String?
    private let nameModelPath: String?
    private var nameRecognizer: KhmerNameRecognizer?

    private init(modelPath: String?, nameModelPath: String?) {
        self.modelPath = modelPath
        self.nameModelPath = nameModelPath
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        func assetPath(_ path: String) -> String? {
            let key = registrar.lookupKey(forAsset: path, fromPackage: "khmer_id_card_ocr")
            return Bundle.main.path(forResource: key, ofType: nil)
        }

        let modelPath = assetPath("assets/tessdata/khm.traineddata").map {
            URL(fileURLWithPath: $0).deletingLastPathComponent().path
        }
        let plugin = KhmerIdCardOcrPlugin(
            modelPath: modelPath,
            nameModelPath: assetPath("assets/recognition/khmer-name-svtrv2-v4-int8.onnx")
        )
        let channel = FlutterMethodChannel(
            name: "khmer_id_card_ocr",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(plugin, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "recognize" else {
            result(FlutterMethodNotImplemented)
            return
        }
        guard let images = call.arguments as? [String: Any],
              let mrz = images["mrz"] as? FlutterStandardTypedData,
              let printed = images["printed"] as? FlutterStandardTypedData,
              let id = images["id"] as? FlutterStandardTypedData,
              let englishName = images["nameEn"] as? FlutterStandardTypedData,
              let name = TextTensor(images["nameInput"], images["nameWidth"], images["nameHeight"]) else {
            result(FlutterError(code: "INVALID_IMAGE", message: "The OCR image regions are missing or invalid.", details: nil))
            return
        }
        let nameLine = (images["nameLine"] as? [String: Any]).flatMap(TextTensor.init)
        let mrzWide = images["mrzWide"] as? FlutterStandardTypedData
        let mrzCheck = images["mrzCheck"] as? FlutterStandardTypedData
        let latinNameLine = (images["latinNameLine"] as? [String: Any]).flatMap(TextTensor.init)
        let validityLine = (images["validityLine"] as? [String: Any]).flatMap(TextTensor.init)
        let addressDetail = (images["addressDetailLine"] as? [String: Any]).flatMap(TextTensor.init)
        let addressLines = (images["addressLines"] as? [[String: Any]] ?? [])
            .prefix(2).compactMap(TextTensor.init)
        queue.async {
            do {
                guard let modelPath = self.modelPath, let nameModelPath = self.nameModelPath else {
                    throw OcrError.missingModels
                }
                let latin = try Engine(modelPath: modelPath, language: "eng")
                let mixed = try Engine(modelPath: modelPath, language: "khm+eng")
                let recognizer = try self.nameRecognizer ?? KhmerNameRecognizer(path: nameModelPath)
                self.nameRecognizer = recognizer
                let mrzWhitelist = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<"
                var output: [String: Any] = [
                    "mrz": try latin.read(mrz.data, mode: PSM_SINGLE_BLOCK,
                                          whitelist: mrzWhitelist),
                    "printed": try mixed.read(printed.data, mode: PSM_SPARSE_TEXT),
                    "id": try latin.read(id.data, mode: PSM_SINGLE_LINE, whitelist: "0123456789"),
                    "nameEn": try latin.read(englishName.data, mode: PSM_SINGLE_LINE),
                    "nameScores": try recognizer.read(name.input, width: name.width, height: name.height),
                ]
                if let mrzWide {
                    output["mrzWide"] = try latin.read(
                        mrzWide.data, mode: PSM_SINGLE_BLOCK, whitelist: mrzWhitelist
                    )
                }
                if let mrzCheck {
                    output["mrzCheck"] = try latin.read(
                        mrzCheck.data, mode: PSM_SINGLE_CHAR, whitelist: "0123456789"
                    )
                }
                if let nameLine {
                    output["nameLineScores"] = try recognizer.read(
                        nameLine.input, width: nameLine.width, height: nameLine.height
                    )
                }
                if let latinNameLine {
                    output["latinNameLineScores"] = try recognizer.read(
                        latinNameLine.input, width: latinNameLine.width, height: latinNameLine.height
                    )
                }
                if !addressLines.isEmpty {
                    output["addressLineScores"] = try addressLines.map { line in
                        try recognizer.read(line.input, width: line.width, height: line.height)
                    }
                }
                if let validityLine {
                    output["validityLineScores"] = try recognizer.read(
                        validityLine.input, width: validityLine.width, height: validityLine.height
                    )
                }
                if let addressDetail {
                    output["addressDetailLineScores"] = try recognizer.read(
                        addressDetail.input, width: addressDetail.width, height: addressDetail.height
                    )
                }
                DispatchQueue.main.async { [output] in result(output) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "OCR_FAILED", message: "Could not read the card on this device.", details: nil))
                }
            }
        }
    }
}

private struct TextTensor {
    let input: Data
    let width: Int
    let height: Int

    init?(_ line: [String: Any]) {
        self.init(line["input"], line["width"], line["height"])
    }

    init?(_ bytes: Any?, _ w: Any?, _ h: Any?) {
        guard let bytes = bytes as? FlutterStandardTypedData,
              let w = w as? Int, let h = h as? Int,
              (48...960).contains(w), (48...64).contains(h),
              bytes.data.count == 3 * w * h * MemoryLayout<Float>.stride else { return nil }
        input = bytes.data
        width = w
        height = h
    }
}

private enum OcrError: Error {
    case missingModels
    case initialization
    case unreadableImage
    case missingOutput
}

private final class Engine {
    private let handle: OpaquePointer

    init(modelPath: String, language: String) throws {
        guard let handle = TessBaseAPICreate() else { throw OcrError.initialization }
        guard TessBaseAPIInit2(handle, modelPath, language, OEM_LSTM_ONLY) == 0 else {
            TessBaseAPIDelete(handle)
            throw OcrError.initialization
        }
        self.handle = handle
    }

    deinit {
        TessBaseAPIDelete(handle)
    }

    func read(_ bytes: Data, mode: TessPageSegMode, whitelist: String = "") throws -> String {
        var image = bytes.withUnsafeBytes { buffer in
            pixReadMem(buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count)
        }
        guard image != nil else { throw OcrError.unreadableImage }
        defer { pixDestroy(&image) }
        TessBaseAPISetPageSegMode(handle, mode)
        TessBaseAPISetVariable(handle, "tessedit_char_whitelist", whitelist)
        TessBaseAPISetImage2(handle, image)
        defer { TessBaseAPIClear(handle) }
        guard let text = TessBaseAPIGetUTF8Text(handle) else { return "" }
        defer { TessDeleteText(text) }
        return String(cString: text)
    }
}


// Called only on the plugin's serial OCR queue.
private final class KhmerNameRecognizer {
    private let environment: ORTEnv
    private let session: ORTSession

    init(path: String) throws {
        let environment = try ORTEnv(loggingLevel: .error)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(2)
        session = try ORTSession(env: environment, modelPath: path, sessionOptions: options)
        self.environment = environment
    }

    func read(_ data: Data, width: Int, height: Int) throws -> FlutterStandardTypedData {
        let tensor = try ORTValue(
            tensorData: NSMutableData(data: data),
            elementType: .float,
            shape: [1, 3, NSNumber(value: height), NSNumber(value: width)]
        )
        let outputs = try session.run(withInputs: ["image": tensor], outputNames: ["probs"], runOptions: nil)
        guard let output = outputs["probs"] else { throw OcrError.missingOutput }
        let values = try output.tensorData()
        return FlutterStandardTypedData(float32: Data(bytes: values.bytes, count: values.length))
    }
}
