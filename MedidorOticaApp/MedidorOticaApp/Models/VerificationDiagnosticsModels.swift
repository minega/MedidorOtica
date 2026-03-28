//
//  VerificationDiagnosticsModels.swift
//  MedidorOticaApp
//
//  Tipos estruturados usados para publicar diagnosticos da captura em tempo real.
//

import Foundation

// MARK: - Direcao de ajuste
/// Direcao sugerida para corrigir o enquadramento atual.
enum VerificationDiagnosticDirection: String, Codable, Equatable, Sendable {
    case none
    case left
    case right
    case up
    case down
    case center
    case clockwise
    case counterclockwise
    case forward
    case backward
    case hold
}

// MARK: - Metrica de verificacao
/// Representa uma subchecagem com valor, faixa alvo e confianca.
struct VerificationMetricDiagnostic: Equatable, Sendable {
    let id: String
    let title: String
    let currentValue: Float?
    let targetRange: ClosedRange<Float>?
    let unit: String
    let direction: VerificationDiagnosticDirection
    let confidence: Float
    let isPassing: Bool
    let detail: String
}

// MARK: - Alinhamento da cabeca
/// Identifica qual subchecagem do alinhamento falhou primeiro.
enum HeadAlignmentCheckKind: String, Codable, Equatable, Sendable {
    case roll
    case yaw
    case pitch
    case eyeLineLevel
    case eyeDepthSymmetry
    case noseDepthLead
    case invalidPose
}

/// Diagnostico consolidado da etapa de alinhamento da cabeca.
struct HeadAlignmentDiagnostic: Equatable, Sendable {
    let metrics: [VerificationMetricDiagnostic]
    let primaryFailureKind: HeadAlignmentCheckKind?
    let primaryFailure: VerificationMetricDiagnostic?
    let blockingHint: String
    let technicalReason: String
    let confidence: Float
}

// MARK: - Falha principal
/// Detalhe unico do motivo que bloqueou o frame atual.
struct VerificationFailureDetail: Equatable, Sendable {
    let overallStep: VerificationStep
    let blockingReason: CameraCaptureBlockReason
    let blockingHint: String
    let diagnosticLabel: String
    let technicalReason: String
    let directionHint: String
    let confidence: Float
}

// MARK: - Resultado por frame
/// Contrato unico publicado pela verificacao para a UI e para o pipeline de captura.
struct VerificationFrameResult: Equatable, Sendable {
    let evaluation: VerificationFrameEvaluation
    let overallStep: VerificationStep
    let blockingReason: CameraCaptureBlockReason?
    let blockingHint: String
    let failureDetail: VerificationFailureDetail?
    let headAlignmentDiagnostic: HeadAlignmentDiagnostic?

    /// Valor vazio usado ao reiniciar a camera.
    static let empty = VerificationFrameResult(evaluation: .empty,
                                               overallStep: .idle,
                                               blockingReason: nil,
                                               blockingHint: "",
                                               failureDetail: nil,
                                               headAlignmentDiagnostic: nil)
}

// MARK: - Snapshot geral
/// Snapshot consolidado do pipeline inteiro usado pela UI de diagnostico.
struct CaptureDiagnosticsSnapshot: Equatable, Sendable {
    let overallStep: VerificationStep
    let blockingReason: CameraCaptureBlockReason?
    let blockingHint: String
    let failureDetail: VerificationFailureDetail?
    let headAlignmentDiagnostic: HeadAlignmentDiagnostic?
    let trueDepthState: TrueDepthBootstrapState
    let trueDepthFailureReason: TrueDepthBlockReason?
    let calibrationReady: Bool
    let calibrationHint: String?
    let captureState: CameraCaptureState
    let captureProgress: Double
    let stableSampleCount: Int
    let requiredStableSampleCount: Int

    /// Snapshot vazio usado antes do primeiro frame util.
    static let empty = CaptureDiagnosticsSnapshot(overallStep: .idle,
                                                  blockingReason: nil,
                                                  blockingHint: "",
                                                  failureDetail: nil,
                                                  headAlignmentDiagnostic: nil,
                                                  trueDepthState: .startingSession,
                                                  trueDepthFailureReason: nil,
                                                  calibrationReady: false,
                                                  calibrationHint: nil,
                                                  captureState: .idle,
                                                  captureProgress: 0,
                                                  stableSampleCount: 0,
                                                  requiredStableSampleCount: 0)
}
