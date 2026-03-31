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
    private enum CaptureWarningConstants {
        /// Coeficiente acima do qual o olhar parece desviado da camera.
        static let gazeDeviationThreshold: Float = 0.35
    }

    private enum CaptureRetryConstants {
        /// Numero maximo de tentativas curtas sobre frames consecutivos.
        static let maximumAttempts = 6
        /// Intervalo curto para esperar o proximo frame do ARKit.
        static let retryDelay: TimeInterval = 0.08
    }

    private enum DepthAnchoredCalibrationConstants {
        /// Faixa util de mm por pixel para o fallback ancorado no plano do PC.
        static let allowedMMPerPixelRange: ClosedRange<Double> = 0.01...0.35
    }

    private struct CaptureCalibrationBundle {
        let global: PostCaptureCalibration
        let local: LocalFaceScaleCalibration
    }

    private struct CaptureFrameContext {
        let frame: ARFrame
        let faceAnchor: ARFaceAnchor
        let cgOrientation: CGImagePropertyOrientation
        let uiOrientation: UIInterfaceOrientation
    }

    // MARK: - Captura de foto
    /// Captura uma foto somente quando o pipeline estiver realmente pronto.
    func capturePhoto(completion: @escaping @Sendable (CapturedPhoto?) -> Void) {
        clearError()

        guard isMeasurementSessionReady else {
            failCapture(with: .sessionNotReady, completion: completion)
            return
        }

        guard isCaptureReady else {
            let error: CameraError = captureReadinessEngine.isFrameFresh(lastFrameTimestamp) ? .sessionNotReady : .staleFrame
            failCapture(with: error, completion: completion)
            return
        }

        markCaptureStarted()
        captureARPhotoAttempt(attempt: 0, completion: completion)
    }

    /// Tenta capturar sobre alguns frames consecutivos para absorver oscilacoes curtas do sensor.
    private func captureARPhotoAttempt(attempt: Int,
                                       completion: @escaping @Sendable (CapturedPhoto?) -> Void) {
        switch makeCapturedPhoto() {
        case .success(let photo):
            DispatchQueue.main.async {
                self.markCaptureCompleted()
                completion(photo)
            }
        case .failure(let error):
            retryOrFailCapture(after: error,
                               attempt: attempt,
                               completion: completion)
        }
    }

    /// Monta a foto final a partir do frame atual do ARKit.
    private func makeCapturedPhoto() -> Result<CapturedPhoto, CameraError> {
        switch buildCaptureFrameContext() {
        case .failure(let error):
            return .failure(error)
        case .success(let context):
            return renderCapturedPhoto(from: context)
        }
    }

    /// Coleta um frame valido para a captura atual.
    private func buildCaptureFrameContext() -> Result<CaptureFrameContext, CameraError> {
        guard let frame = arSession?.currentFrame else {
            return .failure(.captureFailed)
        }

        guard case .normal = frame.camera.trackingState else {
            return .failure(.sessionNotReady)
        }

        guard let trackedFaceAnchor = frame.anchors
            .compactMap({ $0 as? ARFaceAnchor })
            .first(where: { $0.isTracked }) else {
            return .failure(.sessionNotReady)
        }

        guard captureReadinessEngine.isFrameFresh(frame.timestamp) else {
            return .failure(.staleFrame)
        }

        let captureEvaluation = VerificationManager.shared.evaluationForCapture(frame)
        handleVerificationEvaluation(captureEvaluation)
        guard captureEvaluation.allChecksPassed else {
            return .failure(.sessionNotReady)
        }

        return .success(CaptureFrameContext(frame: frame,
                                            faceAnchor: trackedFaceAnchor,
                                            cgOrientation: VerificationManager.shared.currentCGOrientation(),
                                            uiOrientation: VerificationManager.shared.currentUIOrientation()))
    }

    /// Renderiza a foto e resolve a calibracao final do frame escolhido.
    private func renderCapturedPhoto(from context: CaptureFrameContext) -> Result<CapturedPhoto, CameraError> {
        outputDelegate?(context.frame)

        let ciImage = CIImage(cvPixelBuffer: context.frame.capturedImage)
        let orientedCIImage = ciImage.oriented(forExifOrientation: context.cgOrientation.exifOrientation)

        guard let cgImage = photoProcessingContext.createCGImage(orientedCIImage,
                                                                 from: orientedCIImage.extent) else {
            return .failure(.captureFailed)
        }

        let cropRect = CGRect(x: 0,
                              y: 0,
                              width: CGFloat(cgImage.width),
                              height: CGFloat(cgImage.height))
        guard let calibration = buildCalibration(from: context.frame,
                                                 faceAnchor: context.faceAnchor,
                                                 cropRect: cropRect,
                                                 cgOrientation: context.cgOrientation,
                                                 uiOrientation: context.uiOrientation) else {
            return .failure(.missingTrueDepthData)
        }

        let captureCentralPoint = VerificationManager.shared
            .trueDepthMeasurementReference(faceAnchor: context.faceAnchor, frame: context.frame)?
            .pcNormalizedPoint
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        let photo = CapturedPhoto(image: image,
                                  calibration: calibration.global,
                                  localCalibration: calibration.local,
                                  captureCentralPoint: captureCentralPoint,
                                  frameTimestamp: context.frame.timestamp,
                                  orientation: context.cgOrientation,
                                  captureWarning: makeCaptureWarning(from: context.faceAnchor))
        return .success(photo)
    }

    /// Reexecuta a captura quando a falha for transitória e ainda houver tentativas disponiveis.
    private func retryOrFailCapture(after error: CameraError,
                                    attempt: Int,
                                    completion: @escaping @Sendable (CapturedPhoto?) -> Void) {
        guard isRetryableCaptureError(error),
              attempt + 1 < CaptureRetryConstants.maximumAttempts else {
            failCapture(with: error, completion: completion)
            return
        }

        sessionQueue.asyncAfter(deadline: .now() + CaptureRetryConstants.retryDelay) { [weak self] in
            guard let self else { return }
            self.captureARPhotoAttempt(attempt: attempt + 1, completion: completion)
        }
    }

    /// Define quais falhas da captura podem ser resolvidas aguardando o frame seguinte.
    private func isRetryableCaptureError(_ error: CameraError) -> Bool {
        switch error {
        case .captureFailed,
             .missingTrueDepthData,
             .sessionNotReady,
             .staleFrame:
            return true
        default:
            return false
        }
    }

    /// Calcula a calibracao da imagem utilizando dados do TrueDepth.
    private func buildCalibration(from frame: ARFrame,
                                  faceAnchor: ARFaceAnchor,
                                  cropRect: CGRect,
                                  cgOrientation: CGImagePropertyOrientation,
                                  uiOrientation: UIInterfaceOrientation) -> CaptureCalibrationBundle? {
        if let localCalibration = buildLocalCalibration(from: frame,
                                                        faceAnchor: faceAnchor,
                                                        cgOrientation: cgOrientation,
                                                        uiOrientation: uiOrientation),
           let localGlobal = validCalibration(localCalibration.globalCalibration) {
            logCalibration(localGlobal,
                           cropRect: cropRect,
                           frameTimestamp: frame.timestamp,
                           label: "OK Calibracao local da malha")
            return CaptureCalibrationBundle(global: localGlobal,
                                            local: localCalibration)
        }

        if let refined = validCalibration(calibrationEstimator.refinedCalibration(for: frame,
                                                                                  cropRect: cropRect,
                                                                                  orientation: cgOrientation,
                                                                                  uiOrientation: uiOrientation)) {
            logCalibration(refined,
                           cropRect: cropRect,
                           frameTimestamp: frame.timestamp,
                           label: "OK Calibracao TrueDepth refinada")
            return CaptureCalibrationBundle(global: refined,
                                            local: .empty)
        }

        if let instant = validCalibration(calibrationEstimator.instantCalibration(for: frame,
                                                                                  cropRect: cropRect,
                                                                                  orientation: cgOrientation,
                                                                                  uiOrientation: uiOrientation)) {
            logCalibration(instant,
                           cropRect: cropRect,
                           frameTimestamp: frame.timestamp,
                           label: "OK Calibracao TrueDepth imediata")
            return CaptureCalibrationBundle(global: instant,
                                            local: .empty)
        }

        if let reused = recentSuccessfulCalibration(referenceTimestamp: frame.timestamp) {
            logCalibration(reused,
                           cropRect: cropRect,
                           frameTimestamp: frame.timestamp,
                           label: "INFO Calibracao TrueDepth reutilizada")
            return CaptureCalibrationBundle(global: reused,
                                            local: .empty)
        }

        if let depthAnchored = buildDepthAnchoredCalibration(from: frame,
                                                             faceAnchor: faceAnchor,
                                                             cropRect: cropRect,
                                                             cgOrientation: cgOrientation) {
            logCalibration(depthAnchored,
                           cropRect: cropRect,
                           frameTimestamp: frame.timestamp,
                           label: "OK Calibracao ancorada no plano do PC")
            return CaptureCalibrationBundle(global: depthAnchored,
                                            local: .empty)
        }

        logCalibrationFailure(code: 301,
                              message: "Nao foi possivel obter calibracao confiavel no frame atual.")
        return nil
    }

    /// Monta o mapa local da face usando profundidade real e intrinsics da camera.
    private func buildLocalCalibration(from frame: ARFrame,
                                       faceAnchor: ARFaceAnchor,
                                       cgOrientation: CGImagePropertyOrientation,
                                       uiOrientation: UIInterfaceOrientation) -> LocalFaceScaleCalibration? {
        calibrationEstimator.localFaceCalibration(for: frame,
                                                  faceAnchor: faceAnchor,
                                                  orientation: cgOrientation,
                                                  uiOrientation: uiOrientation)
    }

    /// Valida a calibracao antes de permitir o uso no resumo final.
    private func validCalibration(_ calibration: PostCaptureCalibration?) -> PostCaptureCalibration? {
        guard let calibration, calibration.isReliable else { return nil }
        return calibration
    }

    /// Cria uma calibracao de fallback usando profundidade real do PC e intrinsics da camera.
    private func buildDepthAnchoredCalibration(from frame: ARFrame,
                                               faceAnchor: ARFaceAnchor,
                                               cropRect: CGRect,
                                               cgOrientation: CGImagePropertyOrientation) -> PostCaptureCalibration? {
        guard let reference = VerificationManager.shared.trueDepthMeasurementReference(faceAnchor: faceAnchor,
                                                                                       frame: frame) else {
            return nil
        }

        let depthMeters = Double(abs(reference.pcCameraPosition.z))
        guard depthMeters.isFinite, depthMeters > 0 else { return nil }

        let focal = orientedFocalLengths(from: frame.camera.intrinsics,
                                         orientation: cgOrientation)
        guard focal.fx > 0, focal.fy > 0 else { return nil }

        let horizontalMMPerPixel = depthMeters * 1000.0 / focal.fx
        let verticalMMPerPixel = depthMeters * 1000.0 / focal.fy
        guard isValidDepthAnchoredScale(horizontalMMPerPixel),
              isValidDepthAnchoredScale(verticalMMPerPixel) else {
            return nil
        }

        let horizontalReference = horizontalMMPerPixel * Double(cropRect.width)
        let verticalReference = verticalMMPerPixel * Double(cropRect.height)
        let calibration = PostCaptureCalibration(horizontalReferenceMM: horizontalReference,
                                                 verticalReferenceMM: verticalReference)
        return calibration.isReliable ? calibration : nil
    }

    /// Valida a escala milimetrica derivada da profundidade do PC.
    private func isValidDepthAnchoredScale(_ mmPerPixel: Double) -> Bool {
        mmPerPixel.isFinite &&
        DepthAnchoredCalibrationConstants.allowedMMPerPixelRange.contains(mmPerPixel)
    }

    /// Resolve os focais orientados no mesmo referencial da imagem final da captura.
    private func orientedFocalLengths(from intrinsics: simd_float3x3,
                                      orientation: CGImagePropertyOrientation) -> (fx: Double, fy: Double) {
        let rawFX = Double(intrinsics.columns.0.x)
        let rawFY = Double(intrinsics.columns.1.y)
        return isRotatedCaptureOrientation(orientation) ? (rawFY, rawFX) : (rawFX, rawFY)
    }

    /// Informa se a orientacao final troca largura e altura em relacao ao sensor bruto.
    private func isRotatedCaptureOrientation(_ orientation: CGImagePropertyOrientation) -> Bool {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        default:
            return false
        }
    }

    /// Reutiliza a ultima calibracao valida apenas quando ela ainda e recente.
    private func recentSuccessfulCalibration(referenceTimestamp: TimeInterval) -> PostCaptureCalibration? {
        guard let calibration = lastSuccessfulCalibration, calibration.isReliable else { return nil }
        guard let timestamp = lastSuccessfulCalibrationTimestamp else { return nil }
        let age = abs(referenceTimestamp - timestamp)
        let maximumAge = CaptureReadinessEngine.defaultMaximumFrameGap + 0.25
        guard age <= maximumAge else { return nil }
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
        let rejectReason = diagnostics.lastRejectReason?.shortMessage ?? "n/d"

        print("Diagnostico TrueDepth (\(reason)) -> amostras: \(diagnostics.recentSampleCount)/\(diagnostics.storedSampleCount) mm/pixel: \(horizontal) x \(vertical) profundidade: \(depth)mm erroIPD: \(baselineError) rejeicao: \(rejectReason)")
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

    // MARK: - Avisos de captura
    /// Gera um aviso opcional quando o olhar parece nao estar voltado para a camera.
    private func makeCaptureWarning(from faceAnchor: ARFaceAnchor) -> String? {
        let strongestDeviation = strongestGazeDeviation(in: faceAnchor.blendShapes)
        guard strongestDeviation >= CaptureWarningConstants.gazeDeviationThreshold else {
            return nil
        }

        return "Aviso: o olhar nao pareceu direto para a camera. Revise a pupila com mais cuidado."
    }

    /// Mede o maior deslocamento estimado do olhar com base nos blendshapes do TrueDepth.
    private func strongestGazeDeviation(in blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]) -> Float {
        let monitoredLocations: [ARFaceAnchor.BlendShapeLocation] = [
            .eyeLookInLeft,
            .eyeLookOutLeft,
            .eyeLookUpLeft,
            .eyeLookDownLeft,
            .eyeLookInRight,
            .eyeLookOutRight,
            .eyeLookUpRight,
            .eyeLookDownRight
        ]

        return monitoredLocations
            .map { blendShapes[$0]?.floatValue ?? 0 }
            .max() ?? 0
    }
}
