//
//  CameraManager.swift
//  MedidorOticaApp
//
//  Gerenciador otimizado da câmera
//

import Foundation
import AVFoundation
import ARKit
import Combine

// MARK: - Notificações
extension Notification.Name {
    static let cameraError = Notification.Name("CameraError")
    /// Notificação disparada quando a sessão AR encontra um erro
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

    var errorDescription: String {
        switch self {
        case .deniedAuthorization: return "Acesso à câmera negado. Habilite nas configurações do dispositivo."
        case .cameraUnavailable: return "Câmera não disponível no dispositivo."
        case .cannotAddInput: return "Não foi possível adicionar a entrada da câmera."
        case .cannotAddOutput: return "Não foi possível adicionar a saída da câmera."
        case .createCaptureInput(let error): return "Erro na câmera: \(error.localizedDescription)"
        case .deviceConfigurationFailed: return "Falha na configuração da câmera."
        case .captureFailed: return "Falha ao capturar a foto."
        case .missingTrueDepthData: return "Sensor TrueDepth obrigatório não forneceu dados confiáveis."
        }
    }
}

// MARK: - CameraManager
/// Classe responsável por gerenciar a câmera e delegar atualizações da sessão AR.
class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()

    // MARK: - Published Properties
    @Published private(set) var error: CameraError?
    @Published var isFlashOn = false
    @Published var cameraPosition: AVCaptureDevice.Position = .front
    @Published var isSessionRunning = false
    @Published private(set) var hasTrueDepth = false
    @Published private(set) var hasLiDAR = false
    /// Indica se a câmera frontal está habilitada para uso no aplicativo.
    @Published private(set) var isFrontCameraEnabled = true
    /// Estado da limpeza da lente frontal, quando suportado pelo dispositivo.
    @Published private(set) var frontLensCondition: CameraLensCondition = .unknown
    /// Indica se a sessão atual utiliza ARKit (TrueDepth ou LiDAR)
    @Published var isUsingARSession = false

    /// Callback invocado a cada novo frame AR
    public var outputDelegate: ((ARFrame) -> Void)?

    // MARK: - Private Properties
    /// Sessão de captura utilizada pela visualização
    let session = AVCaptureSession()
    let sessionQueue = DispatchQueue(label: "com.oticaManzolli.sessionQueue", qos: .userInitiated)
    let videoOutput = AVCapturePhotoOutput()
    var videoDeviceInput: AVCaptureDeviceInput?
    var arSession: ARSession?
    /// Contexto compartilhado para operações de processamento de imagem e correção de orientação.
    let photoProcessingContext = CIContext()
    /// Indica se o hardware possui suporte ao sensor TrueDepth.
    private(set) var hardwareHasTrueDepth = false
    /// Estimador dedicado a consolidar a calibração proveniente do sensor TrueDepth.
    let calibrationEstimator = TrueDepthCalibrationEstimator()
    /// Observadores dedicados ao monitoramento de condições relacionadas à lente frontal.
    private var lensMonitorCancellables: Set<AnyCancellable> = []
    /// Heurística que estima a limpeza da lente frontal analisando resultados das verificações.
    private let frontLensMonitor = FrontLensCleanlinessMonitor()

    // MARK: - Initialization
    private override init() {
        super.init()
        checkAvailableSensors()
        // Agenda a integração com o VerificationManager após concluir a criação do singleton.
        connectVerificationManagerAsync()
    }

    // MARK: - Error Handling
    /// Publica um erro e dispara uma notificação para os observadores.
    func publishError(_ error: CameraError) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.error = error
            NotificationCenter.default.post(name: .cameraError, object: nil, userInfo: ["error": error])
        }
    }

    /// Publica uma mensagem de erro relacionada à sessão AR.
    func publishARError(_ message: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .arSessionError,
                                            object: nil,
                                            userInfo: ["message": message])
        }
    }

    // MARK: - Device Capabilities
    /// Verifica sensores disponíveis como TrueDepth e LiDAR.
    func checkAvailableSensors() {
        hardwareHasTrueDepth = ARFaceTrackingConfiguration.isSupported
        hasTrueDepth = hardwareHasTrueDepth && isFrontCameraEnabled

        if #available(iOS 13.4, *) {
            // Verifica suporte a profundidade de cena ou reconstrução 3D
            hasLiDAR = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) ||
                       ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        } else {
            hasLiDAR = false
        }

        print("Sensores disponíveis - TrueDepth: \(hasTrueDepth), LiDAR: \(hasLiDAR)")
    }

    // MARK: - Cleanup
    deinit {
        print("CameraManager sendo desalocado")

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

// MARK: - Controle Manual da Câmera Frontal
extension CameraManager {

    /// Define manualmente se a câmera frontal pode ser utilizada pelo aplicativo.
    /// - Parameter enabled: `true` para permitir o uso da câmera frontal, `false` para bloqueá-la.
    func setFrontCameraEnabled(_ enabled: Bool) {
        guard isFrontCameraEnabled != enabled else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

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

    /// Estados possíveis para a lente da câmera frontal.
    /// Mantém valores adicionais para futuros SDKs que reportarem o estado de limpeza diretamente.
    enum CameraLensCondition: Equatable {
        /// Estado inicial ou não determinado da lente.
        case unknown
        /// A lente foi avaliada e está limpa.
        case clean
        /// A lente apresenta sujeira ou precisa ser limpa.
        case needsCleaning
        /// O dispositivo sinalizou que não está reportando o estado da lente.
        case notReporting
        /// O hardware ou a versão do sistema não suporta a leitura da lente.
        case unsupported
        /// A câmera frontal foi desabilitada manualmente pelo aplicativo.
        case disabled
    }

    /// Trata a habilitação manual da câmera frontal.
    private func handleFrontCameraEnabled() {
        print("Câmera frontal habilitada manualmente")
        updateLensMonitoring(for: cameraPosition)
        VerificationManager.shared.updateActiveSensor(using: self)
    }

    /// Trata a desabilitação manual da câmera frontal, garantindo que o app não use sensores inválidos.
    private func handleFrontCameraDisabled() {
        print("Câmera frontal desabilitada manualmente")
        publishLensCondition(.disabled)

        if cameraPosition == .front {
            if hasLiDAR {
                switchCamera()
            } else {
                stop()
                publishError(.cameraUnavailable)
            }
        } else {
            VerificationManager.shared.updateActiveSensor(using: self)
        }
    }

    /// Atualiza o monitoramento da limpeza da lente frontal conforme a posição atual.
    /// - Parameter position: Posição da câmera atualmente ativa.
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

        // API oficial indisponível; utiliza heurística baseada nas verificações recentes.
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

    /// Integra o gerenciamento de verificações de forma assíncrona para evitar ciclos de inicialização.
    private func connectVerificationManagerAsync() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let verificationManager = VerificationManager.shared
            self.configureLensMonitoring(using: verificationManager)
            verificationManager.updateActiveSensor(using: self)
        }
    }

    /// Configura observadores para ajustar a condição da lente frontal com base nas verificações em tempo real.
    /// - Parameter verificationManager: Fonte das verificações publicadas para o Combine.
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

    /// Atualiza a condição da lente com base no retorno das verificações do `VerificationManager`.
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
    /// Número máximo de perdas aceitáveis antes de considerar a lente suja.
    private let missThreshold: Int
    /// Contador de atualizações consecutivas sem detecção facial.
    private var consecutiveMisses = 0
    /// Última condição inferida para a lente frontal.
    private var lastCondition: CameraManager.CameraLensCondition = .unknown
    /// Indica se já houve dados suficientes para estimar o estado da lente.
    private var hasReceivedFeedback = false

    init(missThreshold: Int = 24) {
        self.missThreshold = missThreshold
    }

    /// Registra uma nova observação e retorna a condição estimada da lente frontal.
    /// - Parameter hasValidFaceFrame: Indica se o frame atual possui rosto detectado em posição utilizável.
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

    /// Retorna a melhor estimativa disponível mesmo quando não há feedback recente.
    var estimatedCondition: CameraManager.CameraLensCondition {
        guard hasReceivedFeedback else { return .unknown }
        return lastCondition
    }

    /// Reinicia os contadores e estado interno do monitor.
    func reset() {
        consecutiveMisses = 0
        lastCondition = .unknown
        hasReceivedFeedback = false
    }
}

// MARK: - ARSessionDelegate
extension CameraManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        outputDelegate?(frame)

        guard cameraPosition == .front, hasTrueDepth else { return }
        let cgOrientation = VerificationManager.shared.currentCGOrientation()
        let uiOrientation = VerificationManager.shared.currentUIOrientation()
        calibrationEstimator.ingest(frame: frame,
                                    cgOrientation: cgOrientation,
                                    uiOrientation: uiOrientation)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        if case .normal = camera.trackingState { return }

        // Quando o rastreamento não está normal, reseta verificações
        VerificationManager.shared.reset()
        calibrationEstimator.reset()
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        publishARError("Sessão AR falhou: \(error.localizedDescription)")
        calibrationEstimator.reset()
        restartSession()
    }

    func sessionWasInterrupted(_ session: ARSession) {
        publishARError("Sessão AR interrompida")
        calibrationEstimator.reset()
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        restartSession()
    }
}
