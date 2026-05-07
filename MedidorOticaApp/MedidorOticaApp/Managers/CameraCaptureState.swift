//
//  CameraCaptureState.swift
//  MedidorOticaApp
//
//  Modelos que representam o estado real do pipeline de captura.
//

import Foundation

// MARK: - Motivos de bloqueio do TrueDepth
/// Motivos que explicam porque o sensor TrueDepth ainda nao esta vivo para medir.
enum TrueDepthBlockReason: Error, Equatable, Sendable {
    case noFaceAnchor
    case faceNotTracked
    case invalidIntrinsics
    case invalidEyeDepth
    case ipdOutOfRange
    case pixelBaselineTooSmall
    case scaleOutOfRange
    case baselineNoiseTooHigh
    case noRecentSamples

    /// Texto curto para diagnostico e orientacao do usuario.
    var shortMessage: String {
        switch self {
        case .noFaceAnchor:
            return "Encaixe testa, olhos e queixo dentro do oval."
        case .faceNotTracked:
            return "Mantenha o rosto inteiro visivel no oval."
        case .invalidIntrinsics:
            return "A camera esta reiniciando a calibracao do sensor."
        case .invalidEyeDepth:
            return "Deixe os dois olhos, sobrancelhas e cantos visiveis."
        case .ipdOutOfRange:
            return "Aproxime o rosto ate os olhos ocuparem mais o oval."
        case .pixelBaselineTooSmall:
            return "Aproxime o rosto para aumentar a leitura dos olhos."
        case .scaleOutOfRange:
            return "Ajuste a distancia e segure o celular reto."
        case .baselineNoiseTooHigh:
            return "Segure o celular e o rosto sem girar por um instante."
        case .noRecentSamples:
            return "Aproxime o rosto ate aparecer a malha facial."
        }
    }

    /// Indica se o watchdog deve tentar reiniciar a sessao automaticamente.
    var shouldAutoRecover: Bool {
        switch self {
        case .noFaceAnchor, .faceNotTracked:
            return false
        default:
            return true
        }
    }
}

// MARK: - Bootstrap do TrueDepth
/// Estados do bootstrap do sensor antes do inicio das verificacoes.
enum TrueDepthBootstrapState: Equatable, Sendable {
    case startingSession
    case waitingForFaceAnchor
    case waitingForEyeProjection
    case waitingForDepthConsistency
    case sensorAlive
    case recovering(attempt: Int)
    case failed(reason: TrueDepthBlockReason)

    /// Informa se o sensor ja destravou o fluxo normal de verificacoes.
    var isSensorAlive: Bool {
        if case .sensorAlive = self {
            return true
        }
        return false
    }
}

/// Snapshot consolidado do bootstrap do sensor no frame mais recente.
struct TrueDepthBootstrapStatus: Equatable, Sendable {
    let state: TrueDepthBootstrapState
    let failureReason: TrueDepthBlockReason?
    let recentSampleCount: Int
    let lastValidSampleTimestamp: TimeInterval?
    let lastRejectTimestamp: TimeInterval?

    /// Indica se o gate das verificacoes pode ser liberado.
    var sensorAlive: Bool {
        state.isSensorAlive
    }
}

// MARK: - Politica de recuperacao
/// Decide quando o deadlock do TrueDepth deve virar reinicio automatico.
struct TrueDepthRecoveryPolicy: Equatable, Sendable {
    let progressTimeout: TimeInterval
    let recoveryCooldown: TimeInterval
    let persistentFailureThreshold: Int

    init(progressTimeout: TimeInterval = 1.0,
         recoveryCooldown: TimeInterval = 1.5,
         persistentFailureThreshold: Int = 3) {
        self.progressTimeout = progressTimeout
        self.recoveryCooldown = recoveryCooldown
        self.persistentFailureThreshold = persistentFailureThreshold
    }

    /// Avalia o estado atual do sensor e define a proxima acao.
    func decision(referenceTimestamp: TimeInterval,
                  lastProgressTimestamp: TimeInterval?,
                  lastRestartTimestamp: TimeInterval?,
                  recoveryAttempt: Int,
                  failureReason: TrueDepthBlockReason?) -> TrueDepthRecoveryDecision {
        guard let failureReason, failureReason.shouldAutoRecover else {
            return .none
        }

        let baseline = lastProgressTimestamp ?? referenceTimestamp
        guard referenceTimestamp - baseline >= progressTimeout else {
            return .none
        }

        if let lastRestartTimestamp,
           referenceTimestamp - lastRestartTimestamp < recoveryCooldown {
            return recoveryAttempt >= persistentFailureThreshold ?
                .showFailure(reason: failureReason) : .none
        }

        return .restart(reason: failureReason)
    }
}

/// Resultado da politica de recuperacao do TrueDepth.
enum TrueDepthRecoveryDecision: Equatable, Sendable {
    case none
    case restart(reason: TrueDepthBlockReason)
    case showFailure(reason: TrueDepthBlockReason)
}

// MARK: - Snapshot da pose da cabeca
/// Pose atual da cabeca medida no frame mais recente.
struct HeadPoseSnapshot: Equatable, Sendable {
    let rollDegrees: Float
    let yawDegrees: Float
    let pitchDegrees: Float
    let timestamp: TimeInterval
    let sensor: VerificationManager.SensorType

    /// Indica se os tres eixos foram medidos com valores finitos.
    var isValid: Bool {
        rollDegrees.isFinite &&
        yawDegrees.isFinite &&
        pitchDegrees.isFinite
    }
}

// MARK: - Motivos de bloqueio
/// Motivos que impedem a captura de seguir para a foto final.
enum CameraCaptureBlockReason: Equatable {
    case preparingSession
    case sessionUnavailable
    case trackingUnavailable
    case faceNotDetected
    case distanceOutOfRange
    case faceNotCentered
    case headPoseUnavailable
    case headNotAligned
    case calibrationUnavailable
    case unstableFrame
    case staleFrame

    /// Texto curto utilizado pela interface para explicar o bloqueio atual.
    var shortMessage: String {
        switch self {
        case .preparingSession:
            return "Aguarde a camera abrir e estabilizar."
        case .sessionUnavailable:
            return "A camera reiniciou e esta recuperando a sessao."
        case .trackingUnavailable:
            return "Reenquadre o rosto inteiro dentro do oval."
        case .faceNotDetected:
            return "Encaixe o rosto inteiro no oval."
        case .distanceOutOfRange:
            return "Ajuste a distancia do rosto."
        case .faceNotCentered:
            return "Ajuste o celular ate o nariz ficar no centro."
        case .headPoseUnavailable:
            return "Mantenha testa, olhos e queixo visiveis para medir os eixos."
        case .headNotAligned:
            return "Corrija o eixo indicado na seta da tela."
        case .calibrationUnavailable:
            return "Aguardando a malha facial e a calibracao do sensor."
        case .unstableFrame:
            return "Segure o celular sem girar nem aproximar."
        case .staleFrame:
            return "Aguarde a imagem atualizar."
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
    let headPoseAvailable: Bool
    let headAligned: Bool

    /// Informa se todas as verificacoes principais ja passaram.
    var allChecksPassed: Bool {
        allChecksPassed(requiresTrackedFaceAnchor: true)
    }

    /// Informa se todas as verificacoes passaram considerando o sensor ativo.
    func allChecksPassed(requiresTrackedFaceAnchor: Bool) -> Bool {
        trackingIsNormal &&
        (!requiresTrackedFaceAnchor || hasTrackedFaceAnchor) &&
        faceDetected &&
        distanceCorrect &&
        faceAligned &&
        headPoseAvailable &&
        headAligned
    }

    /// Estado vazio utilizado ao reiniciar a camera.
    static let empty = VerificationFrameEvaluation(timestamp: 0,
                                                   trackingIsNormal: false,
                                                   hasTrackedFaceAnchor: false,
                                                   faceDetected: false,
                                                   distanceCorrect: false,
                                                   faceAligned: false,
                                                   headPoseAvailable: false,
                                                   headAligned: false)
}

// MARK: - Entrada e saida do motor de prontidao
/// Politica usada pelo motor de estabilidade conforme o sensor ativo.
struct CaptureReadinessPolicy: Equatable, Sendable {
    let requiredStableSampleCount: Int
    let maximumFrameGap: TimeInterval
    let maximumCaptureAge: TimeInterval

    /// Politica padrao usada pela camera frontal TrueDepth.
    static let trueDepth = CaptureReadinessPolicy(
        requiredStableSampleCount: CapturePrecisionPolicy.stableSampleCount,
        maximumFrameGap: CapturePrecisionPolicy.maximumFrameGap,
        maximumCaptureAge: CapturePrecisionPolicy.maximumCaptureAge
    )

    /// Politica traseira: Vision/LiDAR oscila mais, entao o bloco bom precisa ser curto.
    static let rearLiDAR = CaptureReadinessPolicy(
        requiredStableSampleCount: RearLiDARCapturePrecisionPolicy.stableSampleCount,
        maximumFrameGap: RearLiDARCapturePrecisionPolicy.maximumFrameGap,
        maximumCaptureAge: RearLiDARCapturePrecisionPolicy.maximumCaptureAge
    )
}

/// Dados consumidos pelo motor de estabilidade da captura.
struct CaptureReadinessInput: Equatable, Sendable {
    let evaluation: VerificationFrameEvaluation
    let sessionReady: Bool
    let calibrationReady: Bool
    let requiresTrackedFaceAnchor: Bool
    let policy: CaptureReadinessPolicy?

    init(evaluation: VerificationFrameEvaluation,
         sessionReady: Bool,
         calibrationReady: Bool,
         requiresTrackedFaceAnchor: Bool = true,
         policy: CaptureReadinessPolicy? = nil) {
        self.evaluation = evaluation
        self.sessionReady = sessionReady
        self.calibrationReady = calibrationReady
        self.requiresTrackedFaceAnchor = requiresTrackedFaceAnchor
        self.policy = policy
    }
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
