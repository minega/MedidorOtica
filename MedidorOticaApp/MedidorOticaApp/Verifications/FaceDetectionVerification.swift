//
//  FaceDetectionVerification.swift
//  MedidorOticaApp
//
//  Verificação de detecção de rosto usando ARKit e Vision
//

import ARKit
import Vision

extension VerificationManager {
    /// Verifica a presença de um rosto com TrueDepth ou LiDAR
    func checkFaceDetection(using frame: ARFrame) -> Bool {
        if ARFaceTrackingConfiguration.isSupported {
            return !frame.anchors.filter { $0 is ARFaceAnchor }.isEmpty
        }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage,
                                             orientation: .right,
                                             options: [:])
        do {
            try handler.perform([request])
            return !(request.results?.isEmpty ?? true)
        } catch {
            print("Erro na detecção de rosto: \(error)")
            return false
        }
    }
}
