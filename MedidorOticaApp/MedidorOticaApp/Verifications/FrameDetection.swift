//
//  FrameDetection.swift
//  MedidorOticaApp
//
//  Detecção em tempo real de armações de óculos usando Vision.
//

import Vision
import ARKit

extension VerificationManager {
    // MARK: - Verificação de Armação
    /// Analisa o buffer atual e retorna `true` caso a imagem apresente
    /// contornos suficientes para indicar uma possível armação.
    func checkFrameDetection(in buffer: CVPixelBuffer) -> Bool {
        let orientation = currentCGOrientation()
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 1.0
        request.detectsDarkOnLight = true

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer,
                                            orientation: orientation)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return false }
            // Heurística simples: considera presença de armação quando há
            // muitos contornos detectados na região do rosto
            return observation.topLevelContours.count > 8
        } catch {
            print("Falha na detecção de armação: \(error)")
            return false
        }
    }
}
