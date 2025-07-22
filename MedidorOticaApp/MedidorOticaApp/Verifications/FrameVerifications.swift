//
//  FrameVerifications.swift
//  MedidorOticaApp
//
//  Implementações das verificações relacionadas à armação de óculos
//

import Foundation
import Vision
import CoreGraphics

// Extensão do VerificationManager para as verificações de armação
extension VerificationManager {

    // MARK: - Parâmetros de Detecção
    private enum FrameConfig {
        static let minConfidence: VNConfidence = 0.6
        static let maxTiltDegrees: CGFloat = 10
    }

    // MARK: - Verificação 5: Detecção de Armação
    /// Utiliza o `VNRecognizeObjectsRequest` para identificar se o usuário está usando
    /// algum tipo de armação de óculos.
    func checkFrameDetection(in image: CVPixelBuffer) -> Bool {
        var detected = false

        let request = VNRecognizeObjectsRequest { request, _ in
            if let results = request.results as? [VNRecognizedObjectObservation] {
                for observation in results {
                    guard let label = observation.labels.first else { continue }
                    let name = label.identifier.lowercased()
                    if (name.contains("glass") || name.contains("sunglass")) &&
                        label.confidence >= FrameConfig.minConfidence {
                        detected = true
                        break
                    }
                }
            }
        }

        request.usesCPUOnly = true
        let handler = VNImageRequestHandler(cvPixelBuffer: image,
                                            orientation: currentCGOrientation(),
                                            options: [:])
        do { try handler.perform([request]) } catch {
            print("ERRO ao detectar armação: \(error)")
        }

        // Mantém histórico para reduzir falsos positivos
        frameDetectionHistory.append(detected)
        if frameDetectionHistory.count > frameHistoryLimit {
            frameDetectionHistory.removeFirst(frameDetectionHistory.count - frameHistoryLimit)
        }

        let positives = frameDetectionHistory.filter { $0 }.count
        return positives * 2 >= frameDetectionHistory.count
    }

    // MARK: - Verificação 6: Alinhamento da Armação
    /// Analisa a inclinação entre os olhos para determinar se a armação está alinhada.
    func checkFrameAlignment(in image: CVPixelBuffer) -> Bool {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: image,
                                            orientation: currentCGOrientation(),
                                            options: [:])

        do {
            try handler.perform([request])
            guard let face = request.results?.first,
                  let left = face.landmarks?.leftEye?.normalizedPoints.first,
                  let right = face.landmarks?.rightEye?.normalizedPoints.last else {
                return false
            }

            let deltaY = right.y - left.y
            let deltaX = right.x - left.x
            let angle = abs(atan2(deltaY, deltaX)) * 180 / .pi
            return angle <= FrameConfig.maxTiltDegrees
        } catch {
            print("ERRO ao verificar alinhamento da armação: \(error)")
            return false
        }
    }
}
