//
//  CameraManager.swift
//  MedidorOticaApp
//
//  Gerenciador otimizado da câmera
//

import AVFoundation
import ARKit

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
        hasTrueDepth = ARFaceTrackingConfiguration.isSupported

        if #available(iOS 13.4, *) {
            hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
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
        arSession = nil
        NotificationCenter.default.removeObserver(self)
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
    }

    func sessionWasInterrupted(_ session: ARSession) {
        publishARError("Sessão AR interrompida")
    }
}
