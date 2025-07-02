//
//  CameraManager.swift
//  MedidorOticaApp
//
//  Gerenciador otimizado da câmera
//

import AVFoundation
import UIKit
import ARKit

// MARK: - Notificações
extension Notification.Name {
    static let cameraError = Notification.Name("CameraError")
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
class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()
    
    // MARK: - Published Properties
    @Published private(set) var error: CameraError?
    @Published private(set) var isFlashOn = false
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .front
    @Published private(set) var isSessionRunning = false
    @Published private(set) var hasTrueDepth = false
    @Published private(set) var hasLiDAR = false
    
    // MARK: - Private Properties
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.oticaManzolli.sessionQueue", qos: .userInitiated)
    private let videoOutput = AVCapturePhotoOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var currentPhotoCaptureProcessor: PhotoCaptureProcessor?
    private var arSession: ARSession?
    private var isUsingARSession = false
    
    // MARK: - Initialization
    private override init() {
        super.init()
        checkAvailableSensors()
    }
    
    // MARK: - Session Control
    func start() {
        guard !isSessionRunning else { return }
        
        if isUsingARSession, let arSession = arSession {
            startARSession(arSession)
        } else {
            startCaptureSession()
        }
    }
    
    private func startARSession(_ arSession: ARSession) {
        let configuration = createARConfiguration()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            do {
                arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
                self.isSessionRunning = true
                print("Sessão AR iniciada com sucesso")
            } catch {
                self.publishError(.deviceConfigurationFailed)
            }
        }
    }
    
    private func createARConfiguration() -> ARConfiguration {
        if cameraPosition == .front, ARFaceTrackingConfiguration.isSupported {
            let config = ARFaceTrackingConfiguration()
            config.maximumNumberOfTrackedFaces = 1
            if #available(iOS 13.0, *) {
                config.isLightEstimationEnabled = true
            }
            print("Usando ARFaceTrackingConfiguration")
            return config
        } else if ARWorldTrackingConfiguration.isSupported {
            let config = ARWorldTrackingConfiguration()
            if #available(iOS 13.4, *), ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .mesh
                config.frameSemantics.insert(.sceneDepth)
            }
            print("Usando ARWorldTrackingConfiguration")
            return config
        }
        
        print("ERRO: Nenhuma configuração AR suportada")
        publishError(.deviceConfigurationFailed)
        return ARWorldTrackingConfiguration() // Retorna configuração padrão em caso de falha
    }
    
    private func startCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.session.isRunning {
                self.session.stopRunning()
            }
            
            self.setupSession()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                
                if !self.session.isRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                    
                    if self.session.isRunning {
                        print("Sessão da câmera iniciada com sucesso")
                    } else {
                        self.publishError(.deviceConfigurationFailed)
                    }
                }
            }
        }
    }
    
    func stop() {
        guard isSessionRunning else { return }
        
        if isUsingARSession {
            stopARSession()
        } else {
            stopCaptureSession()
        }
        
        isSessionRunning = false
    }
    
    private func stopARSession() {
        arSession?.pause()
        print("Sessão AR parada")
    }
    
    private func stopCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            
            self.session.stopRunning()
            self.cleanupSession()
            print("Sessão da câmera parada")
        }
    }
    
    private func cleanupSession() {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
        videoDeviceInput = nil
    }
    
    func setupSession() {
        print("Configurando sessão da câmera...")
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.stopSessionIfRunning()
            self.printAvailableDevices()
            
            self.session.beginConfiguration()
            self.cleanupSession()
            
            // Configura a qualidade da sessão
            if self.session.canSetSessionPreset(.high) {
                self.session.sessionPreset = .high
            }
            
            // Configura o input de vídeo
            self.configureVideoInput()
            
            // Configura o output da foto
            guard self.configurePhotoOutput() else {
                self.session.commitConfiguration()
                return
            }
            
            self.session.commitConfiguration()
            print("Configuração da sessão finalizada com sucesso")
            
            self.startSession()
        }
    }
    
    private func stopSessionIfRunning() {
        if session.isRunning {
            session.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }
    
    private func printAvailableDevices() {
        print("Dispositivos de câmera disponíveis:")
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .unspecified
        )
        for device in discoverySession.devices {
            print("- \(device.localizedName) (posição: \(device.position == .front ? "frontal" : "traseira"))")
        }
    }
    
    private func configurePhotoOutput() -> Bool {
        guard session.canAddOutput(videoOutput) else {
            print("Erro: Não foi possível adicionar output de foto")
            publishError(.cannotAddOutput)
            return false
        }
        
        session.addOutput(videoOutput)
        videoOutput.isHighResolutionCaptureEnabled = true
        print("Output de foto adicionado com sucesso")
        
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
                print("Orientação de vídeo configurada para portrait")
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = (cameraPosition == .front)
                print("Espelhamento de vídeo configurado: \(cameraPosition == .front)")
            }
        }
        
        return true
    }
    
    private func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            self.session.startRunning()
            
            DispatchQueue.main.async {
                self.isSessionRunning = true
            }
            
            print("Sessão da câmera iniciada após configuração")
        }
    }
    
    // MARK: - Device Handling
    
    private func cameraDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: position
        )
        
        return discoverySession.devices.first
    }
    
    private func configureVideoInput() {
        guard let videoDevice = cameraDevice(for: cameraPosition) else {
            publishError(.cameraUnavailable)
            return
        }
        
        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                // Atualiza a orientação do vídeo
                if let connection = videoOutput.connection(with: .video) {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                    if connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = (cameraPosition == .front)
                    }
                }
            } else {
                publishError(.cannotAddInput)
            }
        } catch {
            publishError(.createCaptureInput(error))
        }
    }
    
    // MARK: - Camera Controls
    
    func switchCamera() {
        isUsingARSession ? switchARPosition() : switchAVPosition()
    }
    
    private func switchARPosition() {
        cameraPosition = (cameraPosition == .front) ? .back : .front
        print("Nova posição da câmera: \(cameraPosition == .front ? "frontal" : "traseira")")
        
        if let arSession = arSession {
            let configuration = createARConfiguration()
            arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
    }
    
    private func switchAVPosition() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Para a sessão atual
            self.session.beginConfiguration()
            
            // Remove input existente se houver
            if let currentInput = self.videoDeviceInput {
                self.session.removeInput(currentInput)
            }
            
            // Alterna a posição da câmera
            self.cameraPosition = (self.cameraPosition == .front) ? .back : .front
            
            // Configura o novo dispositivo de entrada
            self.configureVideoInput()
            
            // Confirma as alterações
            self.session.commitConfiguration()
            
            print("Nova posição da câmera: \(self.cameraPosition == .front ? "frontal" : "traseira")")
        }
    }
    
    func toggleFlash() {
        guard let device = videoDeviceInput?.device else { return }
        
        guard device.hasTorch, device.isTorchAvailable else {
            publishError(.deviceConfigurationFailed)
            return
        }
        
        do {
            try device.lockForConfiguration()
            
            isFlashOn.toggle()
            
            if device.isTorchModeSupported(isFlashOn ? .on : .off) {
                device.torchMode = isFlashOn ? .on : .off
            } else {
                isFlashOn = (device.torchMode == .on)
                publishError(.deviceConfigurationFailed)
            }
            
            device.unlockForConfiguration()
        } catch {
            publishError(.deviceConfigurationFailed)
        }
    }
    
    // MARK: - Photo Capture
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        if isUsingARSession {
            captureARPhoto(completion: completion)
        } else {
            captureAVPhoto(completion: completion)
        }
    }
    
    private func captureARPhoto(completion: @escaping (UIImage?) -> Void) {
        guard let frame = arSession?.currentFrame else {
            print("ERRO: Não foi possível obter o frame atual da sessão AR")
            DispatchQueue.main.async { completion(nil) }
            return
        }
        
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("ERRO: Falha ao criar CGImage a partir do buffer de pixel")
            DispatchQueue.main.async { completion(nil) }
            return
        }
        
        let image = UIImage(cgImage: cgImage)
        print("Imagem capturada da sessão AR com sucesso")
        DispatchQueue.main.async { completion(image) }
    }
    
    private func captureAVPhoto(completion: @escaping (UIImage?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard self.session.isRunning, self.videoDeviceInput != nil else {
                print("Erro: Sessão não está em execução ou input não configurado")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let settings = self.createPhotoSettings()
            
            let processor = PhotoCaptureProcessor { [weak self] image in
                self?.handleCapturedPhoto(image: image, completion: completion)
            }
            
            self.currentPhotoCaptureProcessor = processor
            self.videoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }
    
    private func createPhotoSettings() -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        
        if let device = videoDeviceInput?.device, device.isFlashAvailable {
            settings.flashMode = isFlashOn ? .on : .off
            print("Flash configurado: \(isFlashOn ? "ligado" : "desligado")")
        }
        
        return settings
    }
    
    private func handleCapturedPhoto(image: UIImage?, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.currentPhotoCaptureProcessor = nil
            print(image != nil ? "Foto capturada com sucesso" : "Falha ao capturar foto")
            completion(image)
        }
    }
    
    // MARK: - Error Handling
    private func publishError(_ error: CameraError) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.error = error
            NotificationCenter.default.post(
                name: .cameraError,
                object: nil,
                userInfo: ["error": error]
            )
        }
    }
    
    // MARK: - Device Capabilities
    private func checkAvailableSensors() {
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
    
    // MARK: - Configuration
    func setup(position: AVCaptureDevice.Position, arSession: ARSession? = nil, completion: @escaping (Bool) -> Void) {
        cameraPosition = position
        self.arSession = arSession
        isUsingARSession = (arSession != nil)
        
        isUsingARSession ? configureARSession(completion) : configureCaptureSession(completion)
    }
    
    private func configureARSession(_ completion: @escaping (Bool) -> Void) {
        print("Configurando com ARSession fornecida")
        completion(true)
    }
    
    private func configureCaptureSession(_ completion: @escaping (Bool) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.setupSession()
            DispatchQueue.main.async { completion(true) }
        }
    }
    }

// MARK: - Photo Capture Processor
private class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private var selfRetain: PhotoCaptureProcessor?
    private let completion: (UIImage?) -> Void
    
    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
        super.init()
        self.selfRetain = self
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { selfRetain = nil } // Libera a referência forte
        
        if let error = error {
            print("Erro ao processar foto: \(error.localizedDescription)")
            completion(nil)
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            print("Falha ao processar imagem")
            completion(nil)
            return
        }
        
        completion(image)
    }
}