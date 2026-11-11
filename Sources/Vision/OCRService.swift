import AppKit
import Vision

enum OCRServiceError: LocalizedError {
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .recognitionFailed(let message):
            return L10n.t("识别失败：", "Recognition failed: ") + message
        }
    }
}

enum OCRService {
    /// 识别图片中的文字，按阅读顺序返回，保留换行。
    static func recognizeText(
        in image: CGImage,
        languages: [String] = ["zh-Hans", "en-US"]
    ) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRServiceError.recognitionFailed(error.localizedDescription)
        }

        let observations = (request.results ?? []).filter { !$0.topCandidates(1).isEmpty }
        let sorted = observations.sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.01 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        return sorted
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// 解码图片中的 QR / 条形码。
    static func recognizeBarcodes(in image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr, .code128, .code39, .ean13, .ean8, .pdf417, .aztec, .dataMatrix, .itf14]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRServiceError.recognitionFailed(error.localizedDescription)
        }

        let payloads = (request.results ?? [])
            .compactMap { $0.payloadStringValue }
            .filter { !$0.isEmpty }
        return Array(Set(payloads)).sorted()
    }
}
