//
//  DistanceVerification.swift
//  MedidorOticaApp
//
//  Verifica se o rosto está a 40-60 cm do dispositivo.
//

import ARKit

extension VerificationManager {
    private enum Distance {
        static let min: Float = 0.4
        static let max: Float = 0.6
    }

    /// Confere a distância entre o rosto e a câmera.
    func checkDistance(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> Bool {
        var distance: Float?

        if let faceAnchor = faceAnchor, ARFaceTrackingConfiguration.isSupported {
            distance = abs(faceAnchor.transform.columns.3.z)
        } else if #available(iOS 13.4, *),
                  let lidarDistance = depthFromLiDAR(frame) {
            distance = lidarDistance
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
    private func depthFromLiDAR(_ frame: ARFrame) -> Float? {
        guard let depthMap = frame.sceneDepth?.depthMap else { return nil }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let x = CVPixelBufferGetWidth(depthMap) / 2
        let y = CVPixelBufferGetHeight(depthMap) / 2
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let base = CVPixelBufferGetBaseAddress(depthMap)!
        let offset = y * bytesPerRow + x * MemoryLayout<Float>.size
        let value = base.load(fromByteOffset: offset, as: Float.self)
        return value.isFinite ? value : nil
    }
}
