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
    /// Identifica armações de óculos na imagem usando Vision.
    /// Dá preferência ao `VNRecognizeObjectsRequest` por maior precisão.
    func checkFrameDetection(in image: CVPixelBuffer) -> Bool {
        var detected = false

        let completion: VNRequestCompletionHandler = { request, _ in
            if let objects = request.results as? [VNRecognizedObjectObservation] {
                for obj in objects {
                    let label = obj.labels.first?.identifier.lowercased() ?? ""
                    if (label.contains("glass") || label.contains("sunglass")) &&
                        obj.confidence >= FrameConfig.minConfidence {
                        detected = true
                        break
                    }
                }
            } else if let classes = request.results as? [VNClassificationObservation] {
                for obs in classes {
                    let name = obs.identifier.lowercased()
                    if (name.contains("glass") || name.contains("sunglass")) &&
                        obs.confidence >= FrameConfig.minConfidence {
                        detected = true
                        break
                    }
                }
            }
        }

        let request: VNImageBasedRequest
        if #available(iOS 17, *) {
            let objRequest = VNRecognizeObjectsRequest(completionHandler: completion)
            objRequest.revision = VNRecognizeObjectsRequestRevision1
            objRequest.usesCPUOnly = true
            request = objRequest
        } else {
            let classify = VNClassifyImageRequest(completionHandler: completion)
            classify.preferBackgroundProcessing = true
            request = classify
        }
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
        let request = makeLandmarksRequest()
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
