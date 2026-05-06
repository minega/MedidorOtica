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
                return makeStatus(blockReason: .staleFrame)
            }

            registerStableSample(timestamp: input.evaluation.timestamp)
            guard stableSampleCount >= requiredStableSampleCount else {
                return makeStatus(blockReason: .unstableFrame)
            }
            return makeStatus(blockReason: nil)
        }

        reset()
        return makeStatus(blockReason: blockingReason)
    }

    /// Verifica se o frame informado ainda e recente o bastante para capturar.
    func isFrameFresh(_ timestamp: TimeInterval) -> Bool {
        guard let lastAcceptedTimestamp else { return false }
        return abs(timestamp - lastAcceptedTimestamp) <= maximumCaptureAge
    }

    // MARK: - Helpers
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

    private func makeStatus(blockReason: CameraCaptureBlockReason?) -> CaptureReadinessStatus {
        CaptureReadinessStatus(blockReason: blockReason,
                               stableSampleCount: stableSampleCount,
                               requiredStableSampleCount: requiredStableSampleCount)
    }
}
