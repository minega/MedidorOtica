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
            print("ERRO 200: Tentativa de captura sem sessao TrueDepth ativa")
            publishError(.missingTrueDepthData)
            DispatchQueue.main.async { completion(nil) }
            return
        }

        captureARPhoto(completion: completion)
    }

    /// Realiza a captura diretamente da ARSession validando a calibração recebida.
    private func captureARPhoto(completion: @escaping (CapturedPhoto?) -> Void) {
        guard let frame = arSession?.currentFrame else {
            print("ERRO 201: Nao foi possivel obter o frame atual da sessao AR")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        outputDelegate?(frame)

        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = photoProcessingContext
        // Reaproveita a orientação calculada pelo VerificationManager para alinhar a foto ao preview.
        let cgOrientation = VerificationManager.shared.currentCGOrientation()
        let orientedCIImage = ciImage.oriented(forExifOrientation: cgOrientation.exifOrientation)

        guard let cgImageFull = context.createCGImage(orientedCIImage, from: orientedCIImage.extent) else {
            print("ERRO 202: Falha ao criar CGImage a partir do buffer de pixel")
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
            print("ERRO 203: Falha ao recortar a imagem capturada")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let image = UIImage(cgImage: croppedCG, scale: 1.0, orientation: .up)
        guard let calibration = buildCalibration(from: frame,
                                                 cropRect: cropRect,
                                                 cgOrientation: cgOrientation),
              calibration.isReliable else {
            logCalibrationFailure(code: 103, message: "Calibracao TrueDepth indisponivel ou invalida")
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
                                  cgOrientation: CGImagePropertyOrientation) -> PostCaptureCalibration? {
        if let refined = calibrationEstimator.refinedCalibration(for: frame,
                                                                 cropRect: cropRect,
                                                                 orientation: cgOrientation) {
            logCalibration(refined, cropRect: cropRect, label: "OK Calibracao TrueDepth refinada")
            return refined
        }

        logCalibrationFailure(code: 101, message: "Calibracao refinada indisponivel")

        guard let fallback = calibrationEstimator.instantCalibration(for: frame,
                                                                     cropRect: cropRect,
                                                                     orientation: cgOrientation) else {
            logCalibrationFailure(code: 102, message: "Nenhuma calibracao TrueDepth pode ser derivada do frame atual")
            return nil
        }

        logCalibration(fallback, cropRect: cropRect, label: "WARN Calibracao TrueDepth instantanea")
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

    /// Emite um log detalhado com as estatisticas do estimador TrueDepth para auditoria e depuracao.
    private func logDepthDiagnostics(reason: String) {
        let diagnostics = calibrationEstimator.diagnostics()
        let horizontal = diagnostics.lastHorizontalMMPerPixel.map { String(format: "%.5f", $0) } ?? "n/d"
        let vertical = diagnostics.lastVerticalMMPerPixel.map { String(format: "%.5f", $0) } ?? "n/d"
        let depth = diagnostics.lastDepthMM.map { String(format: "%.1f", $0) } ?? "n/d"
        let baselineError = diagnostics.lastBaselineError.map { String(format: "%.3f", $0) } ?? "n/d"

        print("Diagnostico TrueDepth (\(reason)) -> amostras: \(diagnostics.recentSampleCount)/\(diagnostics.storedSampleCount) mm/pixel: \(horizontal) x \(vertical) profundidade: \(depth)mm erroIPD: \(baselineError)")
    }

    /// Registra mensagem de falha numerada para facilitar depuracao.
    private func logCalibrationFailure(code: Int, message: String) {
        let reason = "ERRO \(code): \(message)"
        print(reason)
        logDepthDiagnostics(reason: reason)
    }
}
