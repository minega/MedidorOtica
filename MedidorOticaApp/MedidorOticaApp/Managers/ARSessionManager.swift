//
//  ARSessionManager.swift
//  MedidorOticaApp
//
//  Gerenciador otimizado da sessão ARKit
//

import ARKit
import Metal

class ARSessionManager: NSObject, ARSessionDelegate {
    static let shared = ARSessionManager()
    
    // MARK: - Properties
    
    private(set) var session: ARSession?
    private(set) var isRunning = false
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Session Management
    
    func setupARSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            print("ARKit não é suportado neste dispositivo")
            return
        }
        
        stopSessionIfNeeded()
        
        session = ARSession()
        session?.delegate = self
        
        let configuration = createARConfiguration()
        configuration.videoFormat = selectOptimalVideoFormat()
        
        session?.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
        
        print("Sessão AR inicializada com configuração otimizada")
    }
    
    func stopARSession() {
        session?.pause()
        isRunning = false
    }
    
    private func stopSessionIfNeeded() {
        guard isRunning else { return }
        stopARSession()
        Thread.sleep(forTimeInterval: 0.1) // Pequeno atraso para garantir que a sessão foi encerrada
    }
    
    // MARK: - Configuration
    
    private func createARConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        
        if #available(iOS 14.0, *) {
            configureSceneReconstruction(for: configuration)
            configureFrameSemantics(for: configuration)
        }
        
        configuration.environmentTexturing = .automatic
        configuration.planeDetection = [.horizontal, .vertical]
        
        return configuration
    }
    
    @available(iOS 14.0, *)
    private func configureSceneReconstruction(for configuration: ARWorldTrackingConfiguration) {
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
            print("Reconstrução de cena ativada")
        }
    }
    
    @available(iOS 14.0, *)
    private func configureFrameSemantics(for configuration: ARWorldTrackingConfiguration) {
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
            print("Semântica de profundidade ativada")
        }
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
            print("Segmentação de pessoas com profundidade ativada")
        }
    }
    
    private func selectOptimalVideoFormat() -> ARConfiguration.VideoFormat {
        let availableFormats = ARWorldTrackingConfiguration.supportedVideoFormats
        guard !availableFormats.isEmpty else {
            fatalError("Nenhum formato de vídeo disponível")
        }
        
        // Ordena os formatos pela melhor combinação de resolução e FPS
        let sortedFormats = availableFormats.sorted {
            let score1 = Double($0.imageResolution.width * $0.imageResolution.height) * Double($0.framesPerSecond)
            let score2 = Double($1.imageResolution.width * $1.imageResolution.height) * Double($1.framesPerSecond)
            return score1 > score2
        }
        
        // Para dispositivos mais antigos, escolhe um formato intermediário
        let isHighPerformanceDevice = ProcessInfo.processInfo.physicalMemory > 3_000_000_000 // > 3GB RAM
        let selectedFormat = isHighPerformanceDevice ? sortedFormats.first! : sortedFormats[min(1, sortedFormats.count - 1)]
        
        print("Formato selecionado: \(selectedFormat.imageResolution.width)x" +
              "\(selectedFormat.imageResolution.height) @ \(selectedFormat.framesPerSecond)fps")
        
        return selectedFormat
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("Erro na sessão AR: \(error.localizedDescription)")
        isRunning = false
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("Sessão AR interrompida")
        isRunning = false
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("Interrupção da sessão AR finalizada")
        setupARSession()
    }
    
    // MARK: - App Lifecycle
    
    @objc private func handleAppWillResignActive() {
        stopARSession()
    }
    
    @objc private func handleAppDidBecomeActive() {
        if !isRunning {
            setupARSession()
        }
    }
}
