//
//  DepthDataManager.swift
//  MedidorOticaApp
//
//  Gerenciador otimizado de dados de profundidade
//

import AVFoundation

class DepthDataManager: NSObject, AVCaptureDataOutputSynchronizerDelegate {
    static let shared = DepthDataManager()
    
    // MARK: - Properties
    
    private let sessionQueue = DispatchQueue(label: "com.medidorotica.depthSessionQueue")
    private let dataOutputQueue = DispatchQueue(
        label: "com.medidorotica.depthDataQueue",
        qos: .userInitiated,
        attributes: [],
        autoreleaseFrequency: .workItem
    )
    
    private var captureSession: AVCaptureSession?
    private var depthDevice: AVCaptureDevice?
    private var depthDataOutput: AVCaptureDepthDataOutput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    
    @Published private(set) var currentDepthData: AVDepthData?
    @Published private(set) var isConfigured = false
    @Published private(set) var isRunning = false
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionWasInterrupted),
            name: .AVCaptureSessionWasInterrupted,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded,
            object: nil
        )
    }
    
    deinit {
        stopDepthCapture()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    func setupDepthCapture() {
        sessionQueue.async { [weak self] in
            self?.configureCaptureSession()
        }
    }
    
    func startDepthCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.isRunning else { return }
            
            if !self.isConfigured {
                self.configureCaptureSession()
            }
            
            guard self.isConfigured else { return }
            
            self.captureSession?.startRunning()
            self.isRunning = true
        }
    }
    
    func stopDepthCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            
            self.captureSession?.stopRunning()
            self.isRunning = false
        }
    }
    
    // MARK: - Private Methods
    
    private func configureCaptureSession() {
        guard !isConfigured else { return }
        
        do {
            try configureDevice()
            try configureSession()
            isConfigured = true
        } catch {
            print("Erro na configuração da captura de profundidade: \(error.localizedDescription)")
            cleanup()
        }
    }
    
    private func configureDevice() throws {
        guard let device = AVCaptureDevice.default(
            .builtInTrueDepthCamera,
            for: .video,
            position: .front
        ) else {
            throw DepthError.trueDepthCameraUnavailable
        }
        
        depthDevice = device
        
        // Configura o dispositivo para captura de profundidade
        try device.lockForConfiguration()
        
        if device.isAutoFocusRangeRestrictionSupported {
            device.autoFocusRangeRestriction = .near
        }
        
        if device.isSmoothAutoFocusSupported {
            device.isSmoothAutoFocusEnabled = true
        }
        
        device.unlockForConfiguration()
    }
    
    private func configureSession() throws {
        guard let device = depthDevice else {
            throw DepthError.deviceNotConfigured
        }
        
        let session = AVCaptureSession()
        session.sessionPreset = .vga640x480
        
        // Configura a entrada de vídeo
        let videoInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(videoInput) else {
            throw DepthError.cannotAddInput
        }
        session.addInput(videoInput)
        
        // Configura a saída de profundidade
        let depthOutput = AVCaptureDepthDataOutput()
        depthOutput.isFilteringEnabled = true
        
        guard session.canAddOutput(depthOutput) else {
            throw DepthError.cannotAddDepthOutput
        }
        session.addOutput(depthOutput)
        depthDataOutput = depthOutput
        
        // Configura a saída de vídeo
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(nil, queue: dataOutputQueue)
        
        guard session.canAddOutput(videoOutput) else {
            throw DepthError.cannotAddVideoOutput
        }
        session.addOutput(videoOutput)
        videoDataOutput = videoOutput
        
        // Configura o sincronizador
        guard let depthOutput = depthDataOutput, let videoOutput = videoDataOutput else {
            throw DepthError.outputConfigurationFailed
        }
        
        let synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
        synchronizer.setDelegate(self, queue: dataOutputQueue)
        outputSynchronizer = synchronizer
        
        captureSession = session
    }
    
    private func cleanup() {
        captureSession?.stopRunning()
        
        if let session = captureSession {
            for input in session.inputs {
                session.removeInput(input)
            }
            
            for output in session.outputs {
                session.removeOutput(output)
            }
        }
        
        captureSession = nil
        depthDevice = nil
        depthDataOutput = nil
        videoDataOutput = nil
        outputSynchronizer = nil
        currentDepthData = nil
        isConfigured = false
        isRunning = false
    }
    
    // MARK: - AVCaptureDataOutputSynchronizerDelegate
    
    func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        guard let syncedDepthData = synchronizedDataCollection.synchronizedData(
            for: depthDataOutput!
        ) as? AVCaptureSynchronizedDepthData,
              !syncedDepthData.depthDataWasDropped else {
            return
        }
        
        let depthData = syncedDepthData.depthData
        DispatchQueue.main.async {
            self.currentDepthData = depthData
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc private func handleSessionWasInterrupted(notification: Notification) {
        isRunning = false
    }
    
    @objc private func handleSessionInterruptionEnded(notification: Notification) {
        if isConfigured {
            startDepthCapture()
        }
    }
}

// MARK: - Error Handling

enum DepthError: Error, LocalizedError {
    case trueDepthCameraUnavailable
    case deviceNotConfigured
    case cannotAddInput
    case cannotAddDepthOutput
    case cannotAddVideoOutput
    case outputConfigurationFailed
    
    var errorDescription: String? {
        switch self {
        case .trueDepthCameraUnavailable:
            return "Câmera TrueDepth não disponível"
        case .deviceNotConfigured:
            return "Dispositivo não configurado"
        case .cannotAddInput:
            return "Não foi possível adicionar a entrada de vídeo"
        case .cannotAddDepthOutput:
            return "Não foi possível adicionar a saída de profundidade"
        case .cannotAddVideoOutput:
            return "Não foi possível adicionar a saída de vídeo"
        case .outputConfigurationFailed:
            return "Falha na configuração das saídas"
        }
    }
}
