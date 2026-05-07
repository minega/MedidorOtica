//
//  CaptureReadinessEngine.swift
//  MedidorOticaApp
//
//  Motor que exige estabilidade real antes de liberar a captura.
//

import Foundation

// MARK: - Politica de precisao da captura
/// Centraliza os limites que controlam a captura automatica.
enum CapturePrecisionPolicy {
    /// Tolerancia final do PC no eixo X. Este eixo impacta diretamente a DNP.
    static let horizontalCenteringTolerance: Float = 0.0014
    /// Tolerancia final do PC no eixo Y, mantendo a camera na altura media das pupilas.
    static let verticalCenteringTolerance: Float = 0.0020
    /// Faixa assistida usada apenas enquanto a cabeca ainda esta fora dos eixos.
    static let alignmentAssistHorizontalTolerance: Float = 0.0030
    /// Faixa assistida vertical usada apenas para nao alternar nervosamente entre etapas.
    static let alignmentAssistVerticalTolerance: Float = 0.0035
    /// Tolerancia final de roll da cabeca.
    static let rollToleranceDegrees: Float = 1.2
    /// Tolerancia final de yaw da cabeca.
    static let yawToleranceDegrees: Float = 1.2
    /// Tolerancia final de pitch da cabeca.
    static let pitchToleranceDegrees: Float = 1.3
    /// Quantidade de frames perfeitos exigida antes do disparo automatico.
    static let stableSampleCount = 4
    /// Maior intervalo aceito entre frames validos consecutivos.
    static let maximumFrameGap: TimeInterval = 0.16
    /// Idade maxima do frame aceito no disparo final.
    static let maximumCaptureAge: TimeInterval = 0.12
}

// MARK: - Motor de prontidao
/// Exige amostras consecutivas validas antes de liberar a foto.
/// A calibracao final continua sendo validada no frame real da captura.
final class CaptureReadinessEngine {
    // MARK: - Configuracao
    static let defaultStableSampleCount = CapturePrecisionPolicy.stableSampleCount
    static let defaultMaximumFrameGap: TimeInterval = CapturePrecisionPolicy.maximumFrameGap
    static let defaultMaximumCaptureAge: TimeInterval = CapturePrecisionPolicy.maximumCaptureAge

    private let defaultPolicy: CaptureReadinessPolicy

    // MARK: - Estado interno
    private var stableSampleCount = 0
    private var lastAcceptedTimestamp: TimeInterval?
    private var activeMaximumCaptureAge = CaptureReadinessEngine.defaultMaximumCaptureAge

    // MARK: - Inicializacao
    init(requiredStableSampleCount: Int = CaptureReadinessEngine.defaultStableSampleCount,
         maximumFrameGap: TimeInterval = CaptureReadinessEngine.defaultMaximumFrameGap,
         maximumCaptureAge: TimeInterval = CaptureReadinessEngine.defaultMaximumCaptureAge) {
        self.defaultPolicy = CaptureReadinessPolicy(requiredStableSampleCount: max(requiredStableSampleCount, 1),
                                                    maximumFrameGap: maximumFrameGap,
                                                    maximumCaptureAge: maximumCaptureAge)
        self.activeMaximumCaptureAge = maximumCaptureAge
    }

    // MARK: - API publica
    /// Reinicia o estado acumulado de estabilidade.
    func reset() {
        stableSampleCount = 0
        lastAcceptedTimestamp = nil
    }

    /// Avalia o frame atual e retorna o nivel de prontidao da captura.
    func evaluate(input: CaptureReadinessInput) -> CaptureReadinessStatus {
        let policy = resolvedPolicy(for: input)
        activeMaximumCaptureAge = policy.maximumCaptureAge

        guard let blockingReason = hardBlockReason(for: input) else {
            guard isTimestampContinuous(input.evaluation.timestamp, policy: policy) else {
                reset()
                return makeStatus(blockReason: .staleFrame, policy: policy)
            }

            registerStableSample(timestamp: input.evaluation.timestamp, policy: policy)
            guard stableSampleCount >= policy.requiredStableSampleCount else {
                return makeStatus(blockReason: .unstableFrame, policy: policy)
            }
            return makeStatus(blockReason: nil, policy: policy)
        }

        reset()
        return makeStatus(blockReason: blockingReason, policy: policy)
    }

    /// Verifica se o frame informado ainda e recente o bastante para capturar.
    func isFrameFresh(_ timestamp: TimeInterval) -> Bool {
        guard let lastAcceptedTimestamp else { return false }
        return abs(timestamp - lastAcceptedTimestamp) <= activeMaximumCaptureAge
    }

    // MARK: - Helpers
    private func resolvedPolicy(for input: CaptureReadinessInput) -> CaptureReadinessPolicy {
        input.policy ?? defaultPolicy
    }

    private func hardBlockReason(for input: CaptureReadinessInput) -> CameraCaptureBlockReason? {
        guard input.sessionReady else { return .sessionUnavailable }
        guard input.evaluation.trackingIsNormal else { return .trackingUnavailable }
        if input.requiresTrackedFaceAnchor {
            guard input.evaluation.hasTrackedFaceAnchor else { return .trackingUnavailable }
        }
        guard input.evaluation.faceDetected else { return .faceNotDetected }
        guard input.evaluation.distanceCorrect else { return .distanceOutOfRange }
        guard input.evaluation.faceAligned else { return .faceNotCentered }
        guard input.evaluation.headPoseAvailable else { return .headPoseUnavailable }
        guard input.evaluation.headAligned else { return .headNotAligned }
        return nil
    }

    private func isTimestampContinuous(_ timestamp: TimeInterval,
                                       policy: CaptureReadinessPolicy) -> Bool {
        guard let lastAcceptedTimestamp else { return true }
        let delta = timestamp - lastAcceptedTimestamp
        return delta.isFinite && delta >= 0 && delta <= policy.maximumFrameGap
    }

    private func registerStableSample(timestamp: TimeInterval,
                                      policy: CaptureReadinessPolicy) {
        if !isTimestampContinuous(timestamp, policy: policy) {
            stableSampleCount = 0
        }

        stableSampleCount = min(stableSampleCount + 1, policy.requiredStableSampleCount)
        lastAcceptedTimestamp = timestamp
    }

    private func makeStatus(blockReason: CameraCaptureBlockReason?,
                            policy: CaptureReadinessPolicy) -> CaptureReadinessStatus {
        CaptureReadinessStatus(blockReason: blockReason,
                               stableSampleCount: stableSampleCount,
                               requiredStableSampleCount: policy.requiredStableSampleCount)
    }
}
