//
//  CameraCaptureState.swift
//  MedidorOticaApp
//
//  Modelos que representam o estado real do pipeline de captura.
//

import Foundation

// MARK: - Motivos de bloqueio
/// Motivos que impedem a captura de seguir para a foto final.
enum CameraCaptureBlockReason: Equatable {
    case preparingSession
    case sessionUnavailable
    case trackingUnavailable
    case faceNotDetected
    case distanceOutOfRange
    case faceNotCentered
    case headNotAligned
    case calibrationUnavailable
    case unstableFrame
    case staleFrame

    /// Texto curto utilizado pela interface para explicar o bloqueio atual.
    var shortMessage: String {
        switch self {
        case .preparingSession:
            return "Preparando a camera."
        case .sessionUnavailable:
            return "Sessao indisponivel."
        case .trackingUnavailable:
            return "Rastreamento instavel."
        case .faceNotDetected:
            return "Rosto nao detectado."
        case .distanceOutOfRange:
            return "Ajuste a distancia."
        case .faceNotCentered:
            return "Centralize o rosto."
        case .headNotAligned:
            return "Alinhe a cabeca."
        case .calibrationUnavailable:
            return "Aguardando calibracao."
        case .unstableFrame:
            return "Mantenha a posicao."
        case .staleFrame:
            return "Atualizando imagem."
        }
    }
}

// MARK: - Estado da captura
/// Estados principais do ciclo de captura.
enum CameraCaptureState: Equatable {
    case idle
    case preparing
    case checking(CameraCaptureBlockReason)
    case stableReady
    case countdown
    case capturing
    case captured
    case error(CameraCaptureBlockReason)
}

// MARK: - Avaliacao do frame
/// Resumo consistente das verificacoes calculadas para um frame especifico.
struct VerificationFrameEvaluation: Equatable, Sendable {
    let timestamp: TimeInterval
    let trackingIsNormal: Bool
    let hasTrackedFaceAnchor: Bool
    let faceDetected: Bool
    let distanceCorrect: Bool
    let faceAligned: Bool
    let headAligned: Bool

    /// Informa se todas as verificacoes principais ja passaram.
    var allChecksPassed: Bool {
        trackingIsNormal &&
        hasTrackedFaceAnchor &&
        faceDetected &&
        distanceCorrect &&
        faceAligned &&
        headAligned
    }

    /// Estado vazio utilizado ao reiniciar a camera.
    static let empty = VerificationFrameEvaluation(timestamp: 0,
                                                   trackingIsNormal: false,
                                                   hasTrackedFaceAnchor: false,
                                                   faceDetected: false,
                                                   distanceCorrect: false,
                                                   faceAligned: false,
                                                   headAligned: false)
}

// MARK: - Entrada e saida do motor de prontidao
/// Dados consumidos pelo motor de estabilidade da captura.
struct CaptureReadinessInput: Equatable, Sendable {
    let evaluation: VerificationFrameEvaluation
    let sessionReady: Bool
    let calibrationReady: Bool
}

/// Resultado gerado pelo motor de estabilidade da captura.
struct CaptureReadinessStatus: Equatable, Sendable {
    let blockReason: CameraCaptureBlockReason?
    let stableSampleCount: Int
    let requiredStableSampleCount: Int

    /// Informa se a captura pode iniciar imediatamente.
    var isStableReady: Bool {
        blockReason == nil && stableSampleCount >= requiredStableSampleCount
    }

    /// Percentual de prontidao acumulado para feedback visual.
    var progress: Double {
        guard requiredStableSampleCount > 0 else { return 0 }
        return Double(stableSampleCount) / Double(requiredStableSampleCount)
    }
}
