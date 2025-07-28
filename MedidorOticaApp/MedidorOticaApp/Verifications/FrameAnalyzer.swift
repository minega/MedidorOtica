//
//  FrameAnalyzer.swift
//  MedidorOticaApp
//
//  Responsável por analisar a imagem capturada e detectar as linhas internas da armação.
//

import Vision
import UIKit

struct FrameAnalyzer {
    /// Analisa a imagem já capturada e retorna as linhas da armação
    static func analyze(image: UIImage) -> FrameLandmarks? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)

        do {
            try handler.perform([request])
            guard let face = request.results?.first,
                  let all = face.landmarks?.allPoints,
                  let leftEye = face.landmarks?.leftEye,
                  let rightEye = face.landmarks?.rightEye else { return nil }

            let (w, h) = orientedDimensions(for: cgImage, orientation: orientation)

            func pixelPoints(_ region: VNFaceLandmarkRegion2D) -> [CGPoint] {
                region.normalizedPoints.map { VNImagePointForNormalizedPoint($0, w, h) }
            }

            let allPixels = pixelPoints(all)
            let leftPixels = pixelPoints(leftEye)
            let rightPixels = pixelPoints(rightEye)

            guard let leftMax = leftPixels.map({ $0.x }).max(),
                  let rightMin = rightPixels.map({ $0.x }).min(),
                  let top = allPixels.map({ $0.y }).min(),
                  let bottom = allPixels.map({ $0.y }).max() else { return nil }

            let leftPupil = averagePoint(from: leftEye.normalizedPoints)
            let rightPupil = averagePoint(from: rightEye.normalizedPoints)

            let leftPx = VNImagePointForNormalizedPoint(leftPupil, w, h)
            let rightPx = VNImagePointForNormalizedPoint(rightPupil, w, h)

            return FrameLandmarks(
                leftLineX: leftMax / CGFloat(w),
                rightLineX: rightMin / CGFloat(w),
                topLineY: top / CGFloat(h),
                bottomLineY: bottom / CGFloat(h),
                leftPupil: normalizedPoint(leftPx, width: w, height: h, orientation: orientation),
                rightPupil: normalizedPoint(rightPx, width: w, height: h, orientation: orientation)
            )
        } catch {
            print("Erro na análise da armação: \(error)")
            return nil
        }
    }
}

// MARK: - Funções auxiliares
private extension FrameAnalyzer {
    static func averagePoint(from points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    static func orientedDimensions(for image: CGImage, orientation: CGImagePropertyOrientation) -> (Int, Int) {
        let width = image.width
        let height = image.height
        return orientation.isPortrait ? (height, width) : (width, height)
    }

    static func normalizedPoint(_ pixel: CGPoint, width: Int, height: Int, orientation: CGImagePropertyOrientation) -> CGPoint {
        var point = CGPoint(x: pixel.x / CGFloat(width), y: pixel.y / CGFloat(height))
        point.y = 1 - point.y
        if orientation.isMirrored { point.x = 1 - point.x }
        return point
    }
}

private extension CGImagePropertyOrientation {
    var isPortrait: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        default:
            return false
        }
    }

    var isMirrored: Bool {
        switch self {
        case .upMirrored, .downMirrored, .leftMirrored, .rightMirrored:
            return true
        default:
            return false
        }
    }
}
