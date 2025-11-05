//
//  CameraManager+CapturaFoto.swift
//  MedidorOticaApp
//
//  Extensão que controla a captura de fotos utilizando exclusivamente o sensor TrueDepth.
//

import AVFoundation
import UIKit
import ARKit

extension CameraManager {
    // MARK: - Captura de Foto
    /// Captura uma foto garantindo o uso do TrueDepth para preservar as medições milimétricas.
    func capturePhoto(completion: @escaping (CapturedPhoto?) -> Void) {
        guard isUsingARSession, cameraPosition == .front, hasTrueDepth else {
            print("ERRO: Tentativa de captura sem sessão TrueDepth ativa")
            publishError(.missingTrueDepthData)
            DispatchQueue.main.async { completion(nil) }
            return
        }

        captureARPhoto(completion: completion)
    }

    /// Realiza a captura diretamente da ARSession validando a calibração recebida.
    private func captureARPhoto(completion: @escaping (CapturedPhoto?) -> Void) {
        guard let frame = arSession?.currentFrame else {
            print("ERRO: Não foi possível obter o frame atual da sessão AR")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        outputDelegate?(frame)

        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = photoProcessingContext
        // Reaproveita a orientação calculada pelo VerificationManager para alinhar a foto ao preview.
        let cgOrientation = VerificationManager.shared.currentCGOrientation()
        let uiOrientation = VerificationManager.shared.currentUIOrientation()
        let orientedCIImage = ciImage.oriented(forExifOrientation: cgOrientation.exifOrientation)

        guard let cgImageFull = context.createCGImage(orientedCIImage, from: orientedCIImage.extent) else {
            print("ERRO: Falha ao criar CGImage a partir do buffer de pixel")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let width = CGFloat(cgImageFull.width)
        let height = CGFloat(cgImageFull.height)
        let viewSize = UIScreen.main.bounds.size
        var cropRect = AVMakeRect(aspectRatio: viewSize, insideRect: CGRect(x: 0, y: 0, width: width, height: height))
        cropRect.origin.x = (width - cropRect.width) / 2
        cropRect.origin.y = (height - cropRect.height) / 2

        guard let croppedCG = cgImageFull.cropping(to: cropRect) else {
            print("ERRO: Falha ao recortar a imagem capturada")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let image = UIImage(cgImage: croppedCG, scale: 1.0, orientation: .up)
        guard let calibration = buildCalibration(from: frame,
                                                 cropRect: cropRect,
                                                 cgOrientation: cgOrientation,
                                                 uiOrientation: uiOrientation),
              calibration.isReliable else {
            print("ERRO: Calibração TrueDepth indisponível ou inválida")
            publishError(.missingTrueDepthData)
            DispatchQueue.main.async { completion(nil) }
            return
        }

        print("Imagem capturada da sessão AR com sucesso")
        DispatchQueue.main.async {
            completion(CapturedPhoto(image: image, calibration: calibration))
        }
    }

    /// Calcula a calibração da imagem utilizando dados do TrueDepth respeitando o recorte aplicado.
    private func buildCalibration(from frame: ARFrame,
                                  cropRect: CGRect,
                                  cgOrientation: CGImagePropertyOrientation,
                                  uiOrientation: UIInterfaceOrientation) -> PostCaptureCalibration? {
        if let refined = calibrationEstimator.refinedCalibration(for: frame,
                                                                 cropRect: cropRect,
                                                                 cgOrientation: cgOrientation,
                                                                 uiOrientation: uiOrientation) {
            logCalibration(refined, cropRect: cropRect, label: "✅ Calibração TrueDepth refinada")
            return refined
        }

        guard let fallback = calibrationEstimator.instantCalibration(for: frame,
                                                                     cropRect: cropRect,
                                                                     cgOrientation: cgOrientation,
                                                                     uiOrientation: uiOrientation) else {
            print("ERRO: Nenhuma calibração TrueDepth pôde ser derivada do frame atual")
            logDepthDiagnostics(reason: "sem calibração disponível")
            return nil
        }

        logCalibration(fallback, cropRect: cropRect, label: "ℹ️ Calibração TrueDepth instantânea")
        return fallback
    }

    /// Registra os valores milimétricos por pixel gerados a partir do sensor garantindo rastreabilidade.
    private func logCalibration(_ calibration: PostCaptureCalibration,
                                cropRect: CGRect,
                                label: String) {
        let horizontalMMPerPixel = calibration.horizontalReferenceMM / Double(cropRect.width)
        let verticalMMPerPixel = calibration.verticalReferenceMM / Double(cropRect.height)
        let formattedHorizontal = String(format: "%.5f", horizontalMMPerPixel)
        let formattedVertical = String(format: "%.5f", verticalMMPerPixel)
        print("\(label) mm/pixel: \(formattedHorizontal) x \(formattedVertical)")
    }

    /// Emite um log detalhado com as estatísticas do estimador TrueDepth para auditoria e depuração.
    private func logDepthDiagnostics(reason: String) {
        let diagnostics = calibrationEstimator.diagnostics()
        let horizontal = diagnostics.lastHorizontalMMPerPixel.map { String(format: "%.5f", $0) } ?? "n/d"
        let vertical = diagnostics.lastVerticalMMPerPixel.map { String(format: "%.5f", $0) } ?? "n/d"
        let depth = diagnostics.lastMeanDepth.map { String(format: "%.3f", $0) } ?? "n/d"
        let horizontalWeight = diagnostics.lastHorizontalWeight.map { String(format: "%.1f", $0) } ?? "n/d"
        let verticalWeight = diagnostics.lastVerticalWeight.map { String(format: "%.1f", $0) } ?? "n/d"

        print("🔍 Diagnóstico TrueDepth (\(reason)) -> amostras: \(diagnostics.storedSampleCount)/\(diagnostics.recentSampleCount) " +
              "mm/pixel: \(horizontal) x \(vertical) profundidade: \(depth)m pesos: \(horizontalWeight) | \(verticalWeight) " +
              "pixels avaliados: \(diagnostics.evaluatedPixelCount) candidatos: \(diagnostics.filteredCandidateCount)/\(diagnostics.rawCandidateCount) " +
              "confiança alta: \(diagnostics.highConfidencePixelCount)")
    }
}
