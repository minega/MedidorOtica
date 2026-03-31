//
//  CameraManager.swift
//  MedidorOticaApp
//
//  Gerenciador principal da camera com estado explicito de captura.
//

import Foundation
import AVFoundation
import ARKit
import Combine
import CoreImage
import ImageIO
import UIKit

// MARK: - Notificacoes
extension Notification.Name {
    static let cameraError = Notification.Name("CameraError")
    /// Notificacao disparada quando a sessao AR encontra um erro.
    static let arSessionError = Notification.Name("ARSessionError")
}

// MARK: - Erros
enum CameraError: Error, LocalizedError {
    case deniedAuthorization
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case createCaptureInput(Error)
    case deviceConfigurationFailed
    case captureFailed
    case missingTrueDepthData
    case sessionNotReady
    case staleFrame

    var errorDescription: String {
        switch self {
        case .deniedAuthorization:
            return "Acesso a camera negado. Habilite nas configuracoes do dispositivo."
        case .cameraUnavailable:
            return "Camera nao disponivel no dispositivo."
        case .cannotAddInput:
            return "Nao foi possivel adicionar a entrada da camera."
        case .cannotAddOutput:
            return "Nao foi possivel adicionar a saida da camera."
        case .createCaptureInput(let error):
            return "Erro na camera: \(error.localizedDescription)"
        case .deviceConfigurationFailed:
            return "Falha na configuracao da camera."
        case .captureFailed:
            return "Falha ao capturar a foto."
        case .missingTrueDepthData:
            return "Sensor TrueDepth obrigatorio nao forneceu dados confiaveis."
        case .sessionNotReady:
            return "A camera ainda nao esta pronta para medir."
        case .staleFrame:
            return "O ultimo frame valido ficou desatualizado. Reposicione e tente novamente."
        }
    }
}

// MARK: - CameraManager
/// Classe responsavel por gerenciar a camera e delegar atualizacoes da sessao AR.
final class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()

    // MARK: - Qualidade de imagem
    /// Contexto dedicado para renderizar a foto final com o maximo de fidelidade pratica.
    private static let photoColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Cria um `CIContext` fixo para evitar variacoes de renderizacao entre frames.
    private static func makePhotoProcessingContext() -> CIContext {
        CIContext(options: [
            .cacheIntermediates: false,
            .workingColorSpace: photoColorSpace,
            .outputColorSpace: photoColorSpace,
            .priorityRequestLow: false
        ])
    }

    // MARK: - Published Properties
    @Published private(set) var error: CameraError?
    @Published var isFlashOn = false
    @Published var cameraPosition: AVCaptureDevice.Position = .front
    @Published var isSessionRunning = false
    @Published private(set) var hasTrueDepth = false
    @Published private(set) var hasLiDAR = false
    @Published private(set) var isFrontCameraEnabled = true
    @Published private(set) var frontLensCondition: CameraLensCondition = .unknown
    @Published var isUsingARSession = false
    @Published private(set) var captureState: CameraCaptureState = .idle
    @Published private(set) var captureHint = CameraCaptureBlockReason.preparingSession.shortMessage
    @Published private(set) var captureProgress = 0.0
    @Published private(set) var trueDepthState: TrueDepthBootstrapState = .startingSession
    @Published private(set) var trueDepthFailureReason: TrueDepthBlockReason?
    @Published private(set) var trueDepthRecoveryAttempt = 0
    @Published private(set) var trueDepthLastValidSampleTimestamp: TimeInterval?

    /// Callback invocado a cada novo frame AR.
    var outputDelegate: ((ARFrame) -> Void)?

    // MARK: - Shared Camera Resources
    let session = AVCaptureSession()
    let sessionQueue = DispatchQueue(label: "com.oticaManzolli.sessionQueue", qos: .userInitiated)
    let videoOutput = AVCapturePhotoOutput()
    var videoDeviceInput: AVCaptureDeviceInput?
    var arSession: ARSession?
    let photoProcessingContext = CameraManager.makePhotoProcessingContext()
    private(set) var hardwareHasTrueDepth = false
    let calibrationEstimator = TrueDepthCalibrationEstimator()

    // MARK: - Capture State
    let captureReadinessEngine = CaptureReadinessEngine()
    var lastSuccessfulCalibration: PostCaptureCalibration?
    var lastCalibrationFailure: (code: Int, message: String)?
    private(set) var lastVerificationEvaluation: VerificationFrameEvaluation = .empty
    var lastFrameTimestamp: TimeInterval = 0
    var lastSuccessfulCalibrationTimestamp: TimeInterval?
    private let trueDepthRecoveryPolicy = TrueDepthRecoveryPolicy()
    private var trueDepthBootstrapStartTimestamp: TimeInterval?
    private var trueDepthLastProgressTimestamp: TimeInterval?
    private var trueDepthLastRestartTimestamp: TimeInterval?
    private var trueDepthInternalState: TrueDepthBootstrapState = .startingSession
    private var trueDepthInternalFailureReason: TrueDepthBlockReason?
    private var trueDepthInternalRecoveryAttempt = 0

    // MARK: - Monitoring
    private var lensMonitorCancellables: Set<AnyCancellable> = []
    private let frontLensMonitor = FrontLensCleanlinessMonitor()

    // MARK: - Initialization
    private override init() {
        super.init()
        checkAvailableSensors()
        connectVerificationManagerAsync()
    }

    // MARK: - Error Handling
    /// Publica um erro e dispara uma notificacao para os observadores.
    func publishError(_ error: CameraError) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.error = error
            if let blockReason = self.blockReason(for: error) {
                self.setCaptureState(.error(blockReason),
                                     hint: blockReason.shortMessage,
                                     progress: 0)
            }
            NotificationCenter.default.post(name: .cameraError,
                                            object: nil,
                                            userInfo: ["error": error])
        }
    }

    /// Limpa o ultimo erro publicado sem alterar o restante do pipeline.
    func clearError() {
        if Thread.isMainThread {
            error = nil
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.error = nil
            }
        }
    }

    /// Retorna a ultima mensagem detalhada de falha na calibracao, quando disponivel.
    func latestCalibrationFailureHint() -> String? {
        guard let failure = lastCalibrationFailure else { return nil }
        return "Codigo \(failure.code): \(failure.message)"
    }

    /// Informa se a calibracao TrueDepth esta pronta para captura e retorna um hint amigavel.
    func calibrationReadiness() -> (ready: Bool, hint: String?) {
        guard cameraPosition == .front, isUsingARSession else {
            return (true, nil)
        }

        guard isTrueDepthSensorAlive else {
            return (false, trueDepthHint())
        }

        if let calibration = lastSuccessfulCalibration,
           calibration.isReliable,
           hasRecentSuccessfulCalibration {
            return (true, nil)
        }

        return calibrationEstimator.readiness(minRecentSamples: 2)
    }

    /// Publica uma mensagem de erro relacionada a sessao AR.
    func publishARError(_ message: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .arSessionError,
                                            object: nil,
                                            userInfo: ["message": message])
        }
    }

    // MARK: - Device Capabilities
    /// Verifica sensores disponiveis. Nesta fase o fluxo ativo usa apenas TrueDepth.
    func checkAvailableSensors() {
        isFrontCameraEnabled = true
        hardwareHasTrueDepth = ARFaceTrackingConfiguration.isSupported
        hasTrueDepth = hardwareHasTrueDepth
        hasLiDAR = false
        print("Sensores disponiveis - TrueDepth: \(hasTrueDepth), LiDAR: \(hasLiDAR)")
    }

    // MARK: - Capture Pipeline
    /// Informa se a sessao atual esta realmente pronta para medir.
    var isMeasurementSessionReady: Bool {
        isUsingARSession &&
        isSessionRunning &&
        cameraPosition == .front &&
        hasTrueDepth &&
        isFrontCameraEnabled &&
        arSession != nil
    }

    /// Informa se o TrueDepth ja provou que esta produzindo dados uteis.
    var isTrueDepthSensorAlive: Bool {
        trueDepthInternalState.isSensorAlive
    }

    /// Informa se a captura esta liberada pelo pipeline.
    var isCaptureReady: Bool {
        captureState == .stableReady || captureState == .countdown
    }

    /// Marca o pipeline como em preparacao.
    func beginPreparingCapture() {
        resetCapturePipeline(resetCalibration: true)
        setCaptureState(.preparing,
                        hint: CameraCaptureBlockReason.preparingSession.shortMessage,
                        progress: 0)
    }

    /// Atualiza o estado de contagem regressiva da captura automatica.
    func setCountdownActive(_ isActive: Bool) {
        guard captureState != .capturing, captureState != .captured else { return }

        if isActive {
            setCaptureState(.countdown,
                            hint: "Mantenha a posicao.",
                            progress: 1)
        } else {
            updateCaptureReadiness()
        }
    }

    /// Marca o inicio da captura real da foto.
    func markCaptureStarted() {
        setCaptureState(.capturing, hint: "Capturando foto.", progress: 1)
    }

    /// Marca a captura como concluida.
    func markCaptureCompleted() {
        setCaptureState(.captured, hint: "Foto capturada.", progress: 1)
    }

    /// Reinicia apenas o estado de captura mantendo a sessao aberta.
    func resetCaptureStateForReuse() {
        guard isMeasurementSessionReady else {
            beginPreparingCapture()
            return
        }

        captureReadinessEngine.reset()
        lastVerificationEvaluation = .empty
        setCaptureState(.preparing,
                        hint: CameraCaptureBlockReason.preparingSession.shortMessage,
                        progress: 0)
    }

    /// Atualiza o pipeline com a avaliacao mais recente das verificacoes.
    func handleVerificationEvaluation(_ evaluation: VerificationFrameEvaluation) {
        guard isSessionRunning || captureState == .preparing else { return }
        lastVerificationEvaluation = evaluation
        updateCaptureReadiness()
    }

    /// Atualiza o estado publicado da captura usando a avaliacao mais recente.
    func updateCaptureReadiness() {
        guard captureState != .capturing, captureState != .captured else { return }

        let readiness = calibrationReadiness()
        let input = CaptureReadinessInput(evaluation: lastVerificationEvaluation,
                                          sessionReady: isMeasurementSessionReady,
                                          calibrationReady: readiness.ready)
        let status = captureReadinessEngine.evaluate(input: input)
        applyReadiness(status, calibrationHint: readiness.hint)
    }

    /// Informa se ainda existe um frame estavel e recente o suficiente para capturar.
    func canCaptureCurrentFrame() -> Bool {
        guard isCaptureReady else { return false }
        guard lastFrameTimestamp > 0 else { return false }
        guard captureReadinessEngine.isFrameFresh(lastFrameTimestamp) else { return false }
        return true
    }

    /// Limpa os dados acumulados do pipeline de captura.
    func resetCapturePipeline(resetCalibration: Bool) {
        captureReadinessEngine.reset()
        lastVerificationEvaluation = .empty
        lastFrameTimestamp = 0
        if Thread.isMainThread {
            captureProgress = 0
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.captureProgress = 0
            }
        }

        if resetCalibration {
            lastSuccessfulCalibration = nil
            lastSuccessfulCalibrationTimestamp = nil
            lastCalibrationFailure = nil
            trueDepthLastValidSampleTimestamp = nil
            calibrationEstimator.reset()
        }
    }

    // MARK: - Helpers de estado
    private var hasRecentSuccessfulCalibration: Bool {
        guard let timestamp = lastSuccessfulCalibrationTimestamp else { return false }
        guard lastFrameTimestamp > 0 else { return false }
        let maximumAge = CaptureReadinessEngine.defaultMaximumFrameGap + 0.25
        return abs(lastFrameTimestamp - timestamp) <= maximumAge
    }

    private func updatePreviewCalibration(for frame: ARFrame,
                                          cgOrientation: CGImagePropertyOrientation,
                                          uiOrientation: UIInterfaceOrientation) {
        guard let calibration = calibrationEstimator.previewCalibration(for: frame,
                                                                        orientation: cgOrientation,
                                                                        uiOrientation: uiOrientation),
              calibration.isReliable else {
            return
        }

        lastSuccessfulCalibration = calibration
        lastSuccessfulCalibrationTimestamp = frame.timestamp
        lastCalibrationFailure = nil
    }

    private func applyReadiness(_ status: CaptureReadinessStatus,
                                calibrationHint: String?) {
        if status.isStableReady {
            let nextState: CameraCaptureState = captureState == .countdown ? .countdown : .stableReady
            setCaptureState(nextState,
                            hint: "Continue olhando para a tela. Na contagem, olhe para a camera.",
                            progress: 1)
            return
        }

        let reason = status.blockReason ?? .unstableFrame
        let hint = guidance(for: reason,
                            progress: status.progress,
                            calibrationHint: calibrationHint)
        setCaptureState(.checking(reason), hint: hint, progress: status.progress)
    }

    private func guidance(for reason: CameraCaptureBlockReason,
                          progress: Double,
                          calibrationHint: String?) -> String {
        switch reason {
        case .calibrationUnavailable:
            return calibrationHint ?? reason.shortMessage
        case .unstableFrame:
            let percent = max(Int((progress * 100).rounded()), 1)
            return "Mantenha a posicao (\(percent)% )."
        default:
            return reason.shortMessage
        }
    }

    func setCaptureState(_ state: CameraCaptureState,
                         hint: String,
                         progress: Double) {
        let publish = { [weak self] in
            guard let self else { return }
            self.captureState = state
            self.captureHint = hint
            self.captureProgress = min(max(progress, 0), 1)
        }

        if Thread.isMainThread {
            publish()
        } else {
            DispatchQueue.main.async(execute: publish)
        }
    }

    private func blockReason(for error: CameraError) -> CameraCaptureBlockReason? {
        switch error {
        case .missingTrueDepthData:
            return .calibrationUnavailable
        case .sessionNotReady:
            return .sessionUnavailable
        case .staleFrame:
            return .staleFrame
        case .captureFailed:
            return .sessionUnavailable
        default:
            return nil
        }
    }

    // MARK: - Bootstrap do TrueDepth
    /// Prepara o bootstrap do sensor antes do inicio das verificacoes.
    func prepareTrueDepthBootstrap(resetRecoveryAttempt: Bool,
                                   recoveryReason: TrueDepthBlockReason? = nil) {
        VerificationManager.shared.setTrueDepthGate(isOpen: false)
        trueDepthBootstrapStartTimestamp = nil
        trueDepthLastProgressTimestamp = nil
        trueDepthInternalFailureReason = recoveryReason

        if resetRecoveryAttempt {
            trueDepthInternalRecoveryAttempt = 0
            trueDepthLastRestartTimestamp = nil
            publishTrueDepthState(.startingSession,
                                  failureReason: nil,
                                  lastValidSampleTimestamp: nil)
            return
        }

        publishTrueDepthState(.recovering(attempt: max(trueDepthInternalRecoveryAttempt, 1)),
                              failureReason: recoveryReason,
                              lastValidSampleTimestamp: nil)
    }

    /// Retorna um texto curto que explica o bloqueio atual do sensor.
    func trueDepthHint() -> String {
        switch trueDepthInternalState {
        case .startingSession:
            return "Aguarde a camera abrir e o TrueDepth iniciar."
        case .waitingForFaceAnchor:
            return trueDepthInternalFailureReason?.shortMessage ?? "Encaixe testa, olhos e queixo dentro do oval."
        case .waitingForEyeProjection:
            return trueDepthInternalFailureReason?.shortMessage ?? "Deixe os dois olhos totalmente visiveis no oval."
        case .waitingForDepthConsistency:
            return trueDepthInternalFailureReason?.shortMessage ?? "Segure o celular reto e parado ate a malha estabilizar."
        case .sensorAlive:
            return "TrueDepth ativo."
        case .recovering(let attempt):
            return "Reiniciando o TrueDepth (\(attempt))."
        case .failed(let reason):
            return reason.shortMessage
        }
    }

    /// Atualiza o bootstrap do sensor e decide se o watchdog precisa reiniciar a sessao.
    func handleTrueDepthBootstrap(status: TrueDepthBootstrapStatus,
                                  referenceTimestamp: TimeInterval) {
        let wasSensorAlive = isTrueDepthSensorAlive
        noteTrueDepthProgress(status: status, referenceTimestamp: referenceTimestamp)
        VerificationManager.shared.setTrueDepthGate(isOpen: status.sensorAlive)

        if status.sensorAlive {
            if !wasSensorAlive {
                resetCaptureStateForReuse()
            }

            trueDepthInternalRecoveryAttempt = 0
            trueDepthInternalFailureReason = nil
            publishTrueDepthState(.sensorAlive,
                                  failureReason: nil,
                                  lastValidSampleTimestamp: status.lastValidSampleTimestamp)
            return
        }

        if wasSensorAlive {
            VerificationManager.shared.reset()
            resetCapturePipeline(resetCalibration: true)
            setCaptureState(.checking(.calibrationUnavailable),
                            hint: status.failureReason?.shortMessage ?? trueDepthHint(),
                            progress: 0)
        }

        let decision = trueDepthRecoveryPolicy.decision(referenceTimestamp: referenceTimestamp,
                                                        lastProgressTimestamp: trueDepthLastProgressTimestamp,
                                                        lastRestartTimestamp: trueDepthLastRestartTimestamp,
                                                        recoveryAttempt: trueDepthInternalRecoveryAttempt,
                                                        failureReason: status.failureReason)

        switch decision {
        case .restart(let reason):
            recoverTrueDepth(reason: reason, referenceTimestamp: referenceTimestamp)
        case .showFailure(let reason):
            publishTrueDepthState(.failed(reason: reason),
                                  failureReason: reason,
                                  lastValidSampleTimestamp: status.lastValidSampleTimestamp)
        case .none:
            publishTrueDepthState(status.state,
                                  failureReason: status.failureReason,
                                  lastValidSampleTimestamp: status.lastValidSampleTimestamp)
        }
    }

    private func noteTrueDepthProgress(status: TrueDepthBootstrapStatus,
                                       referenceTimestamp: TimeInterval) {
        if trueDepthBootstrapStartTimestamp == nil {
            trueDepthBootstrapStartTimestamp = referenceTimestamp
        }

        if status.sensorAlive {
            trueDepthLastProgressTimestamp = referenceTimestamp
            return
        }

        if trueDepthInternalFailureReason != status.failureReason ||
            trueDepthInternalState != status.state {
            trueDepthLastProgressTimestamp = referenceTimestamp
            return
        }

        if trueDepthLastProgressTimestamp == nil {
            trueDepthLastProgressTimestamp = trueDepthBootstrapStartTimestamp ?? referenceTimestamp
        }
    }

    private func recoverTrueDepth(reason: TrueDepthBlockReason,
                                  referenceTimestamp: TimeInterval) {
        trueDepthInternalRecoveryAttempt += 1
        trueDepthLastRestartTimestamp = referenceTimestamp
        trueDepthLastProgressTimestamp = referenceTimestamp
        publishTrueDepthState(.recovering(attempt: trueDepthInternalRecoveryAttempt),
                              failureReason: reason,
                              lastValidSampleTimestamp: nil)
        restartSession(recoveryReason: reason)
    }

    private func publishTrueDepthState(_ state: TrueDepthBootstrapState,
                                       failureReason: TrueDepthBlockReason?,
                                       lastValidSampleTimestamp: TimeInterval?) {
        trueDepthInternalState = state
        trueDepthInternalFailureReason = failureReason

        let publish = { [weak self] in
            guard let self else { return }
            let publishedAttempt: Int
            if case .recovering(let attempt) = state {
                publishedAttempt = attempt
            } else {
                publishedAttempt = self.trueDepthInternalRecoveryAttempt
            }

            self.trueDepthState = state
            self.trueDepthFailureReason = failureReason
            self.trueDepthRecoveryAttempt = publishedAttempt
            self.trueDepthLastValidSampleTimestamp = lastValidSampleTimestamp
        }

        if Thread.isMainThread {
            publish()
        } else {
            DispatchQueue.main.async(execute: publish)
        }
    }

    // MARK: - Cleanup
    deinit {
        if isSessionRunning {
            stop()
        }

        arSession?.pause()
        arSession?.delegate = nil
        arSession = nil
        lensMonitorCancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Concurrency
/// O gerenciamento interno ja usa filas dedicadas; esta conformidade evita falsos positivos do Swift 6.
extension CameraManager: @unchecked Sendable {}

// MARK: - Controle Manual da Camera Frontal
extension CameraManager {
    /// Define manualmente se a camera frontal pode ser utilizada pelo aplicativo.
    /// - Parameter enabled: `true` para permitir o uso da camera frontal.
    func setFrontCameraEnabled(_ enabled: Bool) {
        guard isFrontCameraEnabled != enabled else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isFrontCameraEnabled = enabled
            self.hasTrueDepth = self.hardwareHasTrueDepth && enabled

            if enabled {
                self.checkAvailableSensors()
                self.handleFrontCameraEnabled()
            } else {
                self.handleFrontCameraDisabled()
            }
        }
    }

    /// Estados possiveis para a lente da camera frontal.
    enum CameraLensCondition: Equatable {
        case unknown
        case clean
        case needsCleaning
        case notReporting
        case unsupported
        case disabled
    }

    /// Trata a habilitacao manual da camera frontal.
    private func handleFrontCameraEnabled() {
        print("Camera frontal habilitada manualmente")
        updateLensMonitoring(for: cameraPosition)
        VerificationManager.shared.updateActiveSensor(using: self)
    }

    /// Trata a desabilitacao manual da camera frontal.
    private func handleFrontCameraDisabled() {
        print("Camera frontal desabilitada manualmente")
        publishLensCondition(.disabled)

        if cameraPosition == .front {
            stop()
            publishError(.cameraUnavailable)
        } else {
            VerificationManager.shared.updateActiveSensor(using: self)
        }
    }

    /// Atualiza o monitoramento da limpeza da lente frontal conforme a posicao atual.
    func updateLensMonitoring(for position: AVCaptureDevice.Position) {
        guard position == .front else {
            publishLensCondition(isFrontCameraEnabled ? .unknown : .disabled)
            return
        }

        guard isFrontCameraEnabled else {
            publishLensCondition(.disabled)
            return
        }

        guard hardwareHasTrueDepth else {
            publishLensCondition(.unsupported)
            return
        }

        let inferredCondition = frontLensMonitor.estimatedCondition
        publishLensCondition(inferredCondition == .unknown ? .notReporting : inferredCondition)
    }

    /// Publica o estado da lente na thread principal.
    private func publishLensCondition(_ condition: CameraLensCondition) {
        if Thread.isMainThread {
            frontLensCondition = condition
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.frontLensCondition = condition
            }
        }
    }

    /// Integra o gerenciamento de verificacoes de forma assincrona.
    private func connectVerificationManagerAsync() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let verificationManager = VerificationManager.shared
            verificationManager.evaluationHandler = { [weak self] evaluation in
                self?.handleVerificationEvaluation(evaluation)
            }
            self.configureLensMonitoring(using: verificationManager)
            verificationManager.updateActiveSensor(using: self)
        }
    }

    /// Configura observadores para ajustar a condicao da lente frontal.
    private func configureLensMonitoring(using verificationManager: VerificationManager) {
        guard lensMonitorCancellables.isEmpty else { return }

        verificationManager.$faceDetected
            .combineLatest(verificationManager.$distanceCorrect)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] faceDetected, distanceCorrect in
                let reliableDetection = faceDetected && distanceCorrect
                self?.handleLensFeedback(hasValidFaceFrame: reliableDetection || faceDetected)
            }
            .store(in: &lensMonitorCancellables)
    }

    /// Atualiza a condicao da lente com base no retorno das verificacoes.
    private func handleLensFeedback(hasValidFaceFrame: Bool) {
        guard cameraPosition == .front else {
            frontLensMonitor.reset()
            publishLensCondition(isFrontCameraEnabled ? .unknown : .disabled)
            return
        }

        guard isFrontCameraEnabled else {
            frontLensMonitor.reset()
            publishLensCondition(.disabled)
            return
        }

        guard isSessionRunning else {
            frontLensMonitor.reset()
            publishLensCondition(.unknown)
            return
        }

        let condition = frontLensMonitor.register(hasValidFaceFrame: hasValidFaceFrame)
        publishLensCondition(condition)
    }
}

// MARK: - FrontLensCleanlinessMonitor
private final class FrontLensCleanlinessMonitor {
    private let missThreshold: Int
    private var consecutiveMisses = 0
    private var lastCondition: CameraManager.CameraLensCondition = .unknown
    private var hasReceivedFeedback = false

    init(missThreshold: Int = 24) {
        self.missThreshold = missThreshold
    }

    /// Registra uma nova observacao e retorna a condicao estimada da lente frontal.
    func register(hasValidFaceFrame: Bool) -> CameraManager.CameraLensCondition {
        hasReceivedFeedback = true

        if hasValidFaceFrame {
            consecutiveMisses = 0
            lastCondition = .clean
            return lastCondition
        }

        consecutiveMisses = min(consecutiveMisses + 1, missThreshold)
        lastCondition = consecutiveMisses >= missThreshold ? .needsCleaning : .notReporting
        return lastCondition
    }

    /// Retorna a melhor estimativa disponivel mesmo sem feedback recente.
    var estimatedCondition: CameraManager.CameraLensCondition {
        guard hasReceivedFeedback else { return .unknown }
        return lastCondition
    }

    /// Reinicia o estado interno do monitor.
    func reset() {
        consecutiveMisses = 0
        lastCondition = .unknown
        hasReceivedFeedback = false
    }
}

// MARK: - ARSessionDelegate
extension CameraManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lastFrameTimestamp = frame.timestamp
        guard cameraPosition == .front, hasTrueDepth else {
            outputDelegate?(frame)
            return
        }

        let cgOrientation = VerificationManager.shared.currentCGOrientation()
        let uiOrientation = VerificationManager.shared.currentUIOrientation()
        let bootstrapStatus = calibrationEstimator.ingest(frame: frame,
                                                          cgOrientation: cgOrientation,
                                                          uiOrientation: uiOrientation)
        updatePreviewCalibration(for: frame,
                                 cgOrientation: cgOrientation,
                                 uiOrientation: uiOrientation)
        handleTrueDepthBootstrap(status: bootstrapStatus,
                                 referenceTimestamp: frame.timestamp)
        outputDelegate?(frame)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        guard case .normal = camera.trackingState else {
            prepareTrueDepthBootstrap(resetRecoveryAttempt: true,
                                      recoveryReason: .faceNotTracked)
            publishTrueDepthState(.waitingForFaceAnchor,
                                  failureReason: .faceNotTracked,
                                  lastValidSampleTimestamp: nil)
            VerificationManager.shared.reset()
            resetCapturePipeline(resetCalibration: true)
            setCaptureState(.checking(.trackingUnavailable),
                            hint: CameraCaptureBlockReason.trackingUnavailable.shortMessage,
                            progress: 0)
            return
        }

        updateCaptureReadiness()
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        publishARError("Sessao AR falhou: \(error.localizedDescription)")
        beginPreparingCapture()
        restartSession()
    }

    func sessionWasInterrupted(_ session: ARSession) {
        publishARError("Sessao AR interrompida")
        beginPreparingCapture()
        prepareTrueDepthBootstrap(resetRecoveryAttempt: false,
                                  recoveryReason: .noRecentSamples)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        beginPreparingCapture()
        restartSession()
    }
}
