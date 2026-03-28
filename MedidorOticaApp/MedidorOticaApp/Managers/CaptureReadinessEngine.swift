//
//  CaptureReadinessEngine.swift
//  MedidorOticaApp
//
//  Motor que exige estabilidade real antes de liberar a captura.
//

import Foundation

// MARK: - Motor de prontidao
/// Exige amostras consecutivas validas antes de liberar a foto.
final class CaptureReadinessEngine {
    // MARK: - Configuracao
    static let defaultStableSampleCount = 6
    static let defaultMaximumFrameGap: TimeInterval = 0.35
    static let defaultMaximumCaptureAge: TimeInterval = 0.25

    private let requiredStableSampleCount: Int
    private let maximumFrameGap: TimeInterval
    private let maximumCaptureAge: TimeInterval

    // MARK: - Estado interno
    private var stableSampleCount = 0
    private var lastAcceptedTimestamp: TimeInterval?

    // MARK: - Inicializacao
    init(requiredStableSampleCount: Int = CaptureReadinessEngine.defaultStableSampleCount,
         maximumFrameGap: TimeInterval = CaptureReadinessEngine.defaultMaximumFrameGap,
         maximumCaptureAge: TimeInterval = CaptureReadinessEngine.defaultMaximumCaptureAge) {
        self.requiredStableSampleCount = max(requiredStableSampleCount, 1)
        self.maximumFrameGap = maximumFrameGap
        self.maximumCaptureAge = maximumCaptureAge
    }

    // MARK: - API publica
    /// Reinicia o estado acumulado de estabilidade.
    func reset() {
        stableSampleCount = 0
        lastAcceptedTimestamp = nil
    }

    /// Avalia o frame atual e retorna o nivel de prontidao da captura.
    func evaluate(input: CaptureReadinessInput) -> CaptureReadinessStatus {
        guard let blockingReason = hardBlockReason(for: input) else {
            guard isTimestampContinuous(input.evaluation.timestamp) else {
                reset()
                return makeStatus(blockReason: .staleFrame,
                                  failureDetail: input.verificationResult.failureDetail)
            }

            registerStableSample(timestamp: input.evaluation.timestamp)
            guard stableSampleCount >= requiredStableSampleCount else {
                return makeStatus(blockReason: .unstableFrame,
                                  failureDetail: input.verificationResult.failureDetail)
            }
            return makeStatus(blockReason: nil,
                              failureDetail: nil)
        }

        reset()
        return makeStatus(blockReason: blockingReason,
                          failureDetail: resolvedFailureDetail(for: blockingReason,
                                                               input: input))
    }

    /// Verifica se o frame informado ainda e recente o bastante para capturar.
    func isFrameFresh(_ timestamp: TimeInterval) -> Bool {
        guard let lastAcceptedTimestamp else { return false }
        return abs(timestamp - lastAcceptedTimestamp) <= maximumCaptureAge
    }

    // MARK: - Helpers
    private func hardBlockReason(for input: CaptureReadinessInput) -> CameraCaptureBlockReason? {
        guard input.sessionReady else { return .sessionUnavailable }
        if let blockingReason = input.verificationResult.blockingReason {
            return blockingReason
        }
        guard input.calibrationReady else { return .calibrationUnavailable }
        return nil
    }

    private func resolvedFailureDetail(for reason: CameraCaptureBlockReason,
                                       input: CaptureReadinessInput) -> VerificationFailureDetail? {
        if input.verificationResult.blockingReason == reason {
            return input.verificationResult.failureDetail
        }

        guard reason == .calibrationUnavailable else {
            return input.verificationResult.failureDetail
        }

        let hint = input.calibrationHint ?? reason.shortMessage
        return VerificationFailureDetail(overallStep: input.verificationResult.overallStep,
                                         blockingReason: reason,
                                         blockingHint: hint,
                                         diagnosticLabel: "Calibracao",
                                         technicalReason: hint,
                                         directionHint: hint,
                                         confidence: 1)
    }

    private func isTimestampContinuous(_ timestamp: TimeInterval) -> Bool {
        guard let lastAcceptedTimestamp else { return true }
        let delta = timestamp - lastAcceptedTimestamp
        return delta.isFinite && delta >= 0 && delta <= maximumFrameGap
    }

    private func registerStableSample(timestamp: TimeInterval) {
        if !isTimestampContinuous(timestamp) {
            stableSampleCount = 0
        }

        stableSampleCount = min(stableSampleCount + 1, requiredStableSampleCount)
        lastAcceptedTimestamp = timestamp
    }

    private func makeStatus(blockReason: CameraCaptureBlockReason?,
                            failureDetail: VerificationFailureDetail?) -> CaptureReadinessStatus {
        CaptureReadinessStatus(blockReason: blockReason,
                               failureDetail: failureDetail,
                               stableSampleCount: stableSampleCount,
                               requiredStableSampleCount: requiredStableSampleCount)
    }
}
