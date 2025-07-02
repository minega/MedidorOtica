//
//  FaceDetectionVerification.swift
//  MedidorOticaApp
//
//  Verificação de detecção de rosto usando ARKit e Vision
//

import ARKit
import Vision

extension VerificationManager {
    /// Verifica a presença de um rosto usando ARKit ou Vision.
    /// A detecção funciona tanto na câmera frontal (TrueDepth) quanto
    /// na traseira (LiDAR).
    func checkFaceDetection(using frame: ARFrame) -> Bool {
        // Primeiro tenta detectar ancoras faciais fornecidas pelo ARKit
        if frame.anchors.contains(where: { $0 is ARFaceAnchor }) {
            return true
        }

        // Caso não haja ancoras, utiliza o Vision para detectar no frame atual
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: frame.capturedImage,
            orientation: .right,
            options: [:]
        )

        do {
            try handler.perform([request])
            return !(request.results?.isEmpty ?? true)
        } catch {
            print("Erro na detecção de rosto: \(error)")
            return false
        }
    }
}
