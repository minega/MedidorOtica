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

    var errorDescription: String {
        switch self {
        case .deniedAuthorization: return "Acesso à câmera negado. Habilite nas configurações do dispositivo."
        case .cameraUnavailable: return "Câmera não disponível no dispositivo."
        case .cannotAddInput: return "Não foi possível adicionar a entrada da câmera."
        case .cannotAddOutput: return "Não foi possível adicionar a saída da câmera."
        case .createCaptureInput(let error): return "Erro na câmera: \(error.localizedDescription)"
        case .deviceConfigurationFailed: return "Falha na configuração da câmera."
        case .captureFailed: return "Falha ao capturar a foto."
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
    var currentPhotoCaptureProcessor: PhotoCaptureProcessor?
    var arSession: ARSession?
    /// Indica se o hardware possui suporte ao sensor TrueDepth.
    private(set) var hardwareHasTrueDepth = false
    /// Observador de estado da lente frontal.
    private var lensStateObservation: NSKeyValueObservation?

    // MARK: - Initialization
    private override init() {
        super.init()
        checkAvailableSensors()
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
        lensStateObservation?.invalidate()
        lensStateObservation = nil
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

        lensStateObservation?.invalidate()
        lensStateObservation = nil
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
        lensStateObservation?.invalidate()
        lensStateObservation = nil

        guard position == .front else {
            publishLensCondition(isFrontCameraEnabled ? .unknown : .disabled)
            return
        }

        guard isFrontCameraEnabled else {
            publishLensCondition(.disabled)
            return
        }

        guard #available(iOS 17.4, *) else {
            publishLensCondition(.unsupported)
            return
        }

        guard let device = cameraDevice(for: .front, ignoringFrontOverride: true) else {
            publishLensCondition(.unknown)
            return
        }

        lensStateObservation = device.observe(\.lensState, options: [.initial, .new]) { [weak self] device, _ in
            guard let self = self else { return }
            let condition = self.mapLensState(device.lensState)
            self.publishLensCondition(condition)
        }
    }

    @available(iOS 17.4, *)
    private func mapLensState(_ state: AVCaptureDevice.LensState) -> CameraLensCondition {
        switch state {
        case .clean:
            return .clean
        case .smudged:
            return .needsCleaning
        case .unknown:
            return .unknown
        case .notReporting:
            return .notReporting
        @unknown default:
            return .unknown
        }
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
}

// MARK: - ARSessionDelegate
extension CameraManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        outputDelegate?(frame)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        if case .normal = camera.trackingState { return }

        // Quando o rastreamento não está normal, reseta verificações
        VerificationManager.shared.reset()
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        publishARError("Sessão AR falhou: \(error.localizedDescription)")
        restartSession()
    }

    func sessionWasInterrupted(_ session: ARSession) {
        publishARError("Sessão AR interrompida")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        restartSession()
    }
}
