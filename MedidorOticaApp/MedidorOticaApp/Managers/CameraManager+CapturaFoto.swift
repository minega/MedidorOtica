//
//  CameraManager+CapturaFoto.swift
//  MedidorOticaApp
//
//  Captura de foto validando sessao, frame e calibracao TrueDepth.
//

import AVFoundation
import UIKit
import ARKit
import ImageIO

extension CameraManager {
    // MARK: - Captura de foto
    /// Captura uma foto somente quando o pipeline estiver realmente pronto.
    func capturePhoto(completion: @escaping @Sendable (CapturedPhoto?) -> Void) {
        clearError()

        guard isMeasurementSessionReady else {
            failCapture(with: .sessionNotReady, completion: completion)
            return
        }

        guard canCaptureCurrentFrame() else {
            let error: CameraError = captureReadinessEngine.isFrameFresh(lastFrameTimestamp) ? .sessionNotReady : .staleFrame
            failCapture(with: error, completion: completion)
            return
        }

        markCaptureStarted()
        captureARPhoto(completion: completion)
    }

    /// Realiza a captura diretamente da ARSession validando o frame atual.
    private func captureARPhoto(completion: @escaping @Sendable (CapturedPhoto?) -> Void) {
        guard let frame = arSession?.currentFrame else {
            failCapture(with: .captureFailed, completion: completion)
            return
        }

        guard case .normal = frame.camera.trackingState else {
            failCapture(with: .sessionNotReady, completion: completion)
            return
        }

        guard frame.anchors.contains(where: { ($0 as? ARFaceAnchor)?.isTracked == true }) else {
            failCapture(with: .sessionNotReady, completion: completion)
            return
        }

        guard captureReadinessEngine.isFrameFresh(frame.timestamp) else {
            failCapture(with: .staleFrame, completion: completion)
            return
        }

        let captureEvaluation = VerificationManager.shared.evaluationForCapture(frame)
        handleVerificationEvaluation(captureEvaluation)
        guard captureEvaluation.allChecksPassed else {
            failCapture(with: .sessionNotReady, completion: completion)
            return
        }

        outputDelegate?(frame)

        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let cgOrientation = VerificationManager.shared.currentCGOrientation()
        let orientedCIImage = ciImage.oriented(forExifOrientation: cgOrientation.exifOrientation)

        guard let cgImage = photoProcessingContext.createCGImage(orientedCIImage,
                                                                 from: orientedCIImage.extent) else {
            failCapture(with: .captureFailed, completion: completion)
            return
        }

        let cropRect = CGRect(x: 0,
                              y: 0,
                              width: CGFloat(cgImage.width),
                              height: CGFloat(cgImage.height))
        guard let calibration = buildCalibration(from: frame,
                                                 cropRect: cropRect,
                                                 cgOrientation: cgOrientation) else {
            failCapture(with: .missingTrueDepthData, completion: completion)
            return
        }

        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        let photo = CapturedPhoto(image: image,
                                  calibration: calibration,
                                  frameTimestamp: frame.timestamp,
                                  orientation: cgOrientation)

        DispatchQueue.main.async {
            self.markCaptureCompleted()
            completion(photo)
        }
    }

    /// Calcula a calibracao da imagem utilizando dados do TrueDepth.
    private func buildCalibration(from frame: ARFrame,
                                  cropRect: CGRect,
                                  cgOrientation: CGImagePropertyOrientation) -> PostCaptureCalibration? {
        if let refined = validCalibration(calibrationEstimator.refinedCalibration(for: frame,
                                                                                  cropRect: cropRect,
                                                                                  orientation: cgOrientation)) {
            logCalibration(refined,
                           cropRect: cropRect,
                           frameTimestamp: frame.timestamp,
                           label: "OK Calibracao TrueDepth refinada")
            return refined
        }

        if let instant = validCalibration(calibrationEstimator.instantCalibration(for: frame,
                                                                                  cropRect: cropRect,
                                                                                  orientation: cgOrientation)) {
            logCalibration(instant,
                           cropRect: cropRect,
                           frameTimestamp: frame.timestamp,
                           label: "OK Calibracao TrueDepth imediata")
            return instant
        }

        if let reused = recentSuccessfulCalibration(referenceTimestamp: frame.timestamp) {
            logCalibration(reused,
                           cropRect: cropRect,
                           frameTimestamp: frame.timestamp,
                           label: "INFO Calibracao TrueDepth reutilizada")
            return reused
        }

        logCalibrationFailure(code: 301,
                              message: "Nao foi possivel obter calibracao confiavel no frame atual.")
        return nil
    }

    /// Valida a calibracao antes de permitir o uso no resumo final.
    private func validCalibration(_ calibration: PostCaptureCalibration?) -> PostCaptureCalibration? {
        guard let calibration, calibration.isReliable else { return nil }
        return calibration
    }

    /// Reutiliza a ultima calibracao valida apenas quando ela ainda e recente.
    private func recentSuccessfulCalibration(referenceTimestamp: TimeInterval) -> PostCaptureCalibration? {
        guard let calibration = lastSuccessfulCalibration, calibration.isReliable else { return nil }
        guard let timestamp = lastSuccessfulCalibrationTimestamp else { return nil }
        let age = abs(referenceTimestamp - timestamp)
        guard age <= CaptureReadinessEngine.defaultMaximumCaptureAge else { return nil }
        return calibration
    }

    /// Registra os valores milimetricos por pixel gerados a partir do sensor.
    private func logCalibration(_ calibration: PostCaptureCalibration,
                                cropRect: CGRect,
                                frameTimestamp: TimeInterval,
                                label: String) {
        lastSuccessfulCalibration = calibration
        lastSuccessfulCalibrationTimestamp = frameTimestamp
        lastCalibrationFailure = nil

        let horizontalMMPerPixel = calibration.horizontalReferenceMM / Double(cropRect.width)
        let verticalMMPerPixel = calibration.verticalReferenceMM / Double(cropRect.height)
        let formattedHorizontal = String(format: "%.5f", horizontalMMPerPixel)
        let formattedVertical = String(format: "%.5f", verticalMMPerPixel)
        print("\(label) mm/pixel: \(formattedHorizontal) x \(formattedVertical)")
    }

    /// Emite um log detalhado com as estatisticas do estimador TrueDepth.
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
        lastCalibrationFailure = (code, message)
        logDepthDiagnostics(reason: reason)
    }

    /// Encapsula o fluxo comum de falha da captura.
    private func failCapture(with error: CameraError,
                             completion: @escaping @Sendable (CapturedPhoto?) -> Void) {
        publishError(error)
        DispatchQueue.main.async {
            completion(nil)
        }
    }
}
