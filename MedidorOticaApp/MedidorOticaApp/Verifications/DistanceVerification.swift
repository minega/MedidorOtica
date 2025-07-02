//
//  DistanceVerification.swift
//  MedidorOticaApp
//
//  Verifica se o rosto está a 40-60 cm do dispositivo.
//

import ARKit
import Vision

extension VerificationManager {
    private enum Distance {
        static let min: Float = 0.4
        static let max: Float = 0.6
    }

    /// Confere se o rosto está entre 40 e 60 cm da câmera.
    /// Utiliza a distância média dos olhos no TrueDepth ou,
    /// caso indisponível, a profundidade do LiDAR na região do rosto.
    func checkDistance(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> Bool {
        var distance: Float?

        if let anchor = faceAnchor {
            // Distância média dos olhos em relação à câmera
            let left = abs(anchor.leftEyeTransform.columns.3.z)
            let right = abs(anchor.rightEyeTransform.columns.3.z)
            distance = (left + right) / 2
        } else if #available(iOS 13.4, *),
                  let observation = detectFaceObservation(in: frame.capturedImage),
                  let lidar = depthFromLiDAR(frame, at: observation.boundingBox.midPoint) {
            distance = lidar
        }

        guard let value = distance else { return false }
        let inRange = value >= Distance.min && value <= Distance.max

        DispatchQueue.main.async { [weak self] in
            self?.lastMeasuredDistance = value * 100
            self?.distanceCorrect = inRange
            self?.updateAllVerifications()
        }

        return inRange
    }

    @available(iOS 13.4, *)
    private func depthFromLiDAR(_ frame: ARFrame, at point: CGPoint) -> Float? {
        guard let depthMap = frame.sceneDepth?.depthMap else { return nil }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let x = Int(point.x * CGFloat(width))
        let y = Int((1 - point.y) * CGFloat(height))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let base = CVPixelBufferGetBaseAddress(depthMap)!
        let offset = y * bytesPerRow + x * MemoryLayout<Float>.size
        let value = base.load(fromByteOffset: offset, as: Float.self)
        return value.isFinite ? value : nil
    }

    @available(iOS 13.0, *)
    private func detectFaceObservation(in pixelBuffer: CVPixelBuffer) -> VNFaceObservation? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
        return request.results?.first as? VNFaceObservation
    }

    @available(iOS 13.0, *)
    private func detectFaceBox(in pixelBuffer: CVPixelBuffer) -> CGRect? {
        return detectFaceObservation(in: pixelBuffer)?.boundingBox
    }

}

private extension CGRect {
    /// Retorna o ponto central normalizado da caixa
    var midPoint: CGPoint { CGPoint(x: midX, y: midY) }
}
