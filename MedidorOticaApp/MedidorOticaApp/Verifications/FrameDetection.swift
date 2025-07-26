//
//  FrameDetection.swift
//  MedidorOticaApp
//
//  Detecção em tempo real de armações de óculos usando Vision.
//

import Vision
import ARKit

extension VerificationManager {
    // MARK: - Parâmetros de Detecção
    private enum FrameDetectionConfig {
        static let minConfidence: VNConfidence = 0.6
    }

    // MARK: - Verificação de Armação
    /// Retorna `true` se uma armação for detectada no buffer atual.
    func checkFrameDetection(in buffer: CVPixelBuffer) -> Bool {
        let request = VNRecognizeObjectsRequest()
        request.revision = 1
        request.recognitionLevel = .accurate

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer,
                                            orientation: currentCGOrientation())
        do {
            try handler.perform([request])
            guard let objects = request.results else { return false }
            return objects.contains { obs in
                obs.labels.first?.identifier.lowercased().contains("glass") == true &&
                obs.confidence >= FrameDetectionConfig.minConfidence
            }
        } catch {
            print("Falha na detecção de armação: \(error)")
            return false
        }
    }
}
*** End of File ***
