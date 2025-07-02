//
//  VerificationManager.swift
//  MedidorOticaApp
//
//  Gerenciador central para as verificações de medição óptica
//

import Foundation
import Vision
import AVFoundation
import UIKit
import ARKit
import Combine
import ARKit

// Tipos de câmera disponíveis
enum CameraType {
    case front // Câmera frontal (TrueDepth)
    case back  // Câmera traseira (LiDAR)
}

class VerificationManager: ObservableObject {
    static let shared = VerificationManager()
    
    // Publicação das verificações para a interface
    @Published var verifications: [Verification] = []
    
    // Estado atual de cada verificação
    @Published var faceDetected = false
    @Published var distanceCorrect = false
    @Published var faceAligned = false
    @Published var headAligned = false
    @Published var frameDetected = false
    @Published var frameAligned = false
    @Published var gazeCorrect = false
    
    // Medições precisas
    @Published var lastMeasuredDistance: Float = 0.0 // em centímetros, com precisão de 0,5mm
    
    // Status do dispositivo e sensores
    @Published var hasTrueDepth = false // Indica se o dispositivo tem sensor TrueDepth
    @Published var hasLiDAR = false // Indica se o dispositivo tem sensor LiDAR
    
    // Compatibilidade com código antigo
    @Published var deviceHasDepthSensor: Bool = false // Para compatiblidade com código antigo
    @Published var faceCentered: Bool = false // Para compatiblidade com código antigo
    @Published var gazeData: [String: Float] = [:] // Para compatiblidade com código antigo
    @Published var alignmentData: [String: Float] = [:] // Para compatiblidade com código antigo
    @Published var facePosition: [String: Float] = [:] // Para compatiblidade com código antigo
    @Published var headRoll: Float = 0.0 // Para compatiblidade com código antigo
    
    // Sessão AR
    private var arSession: ARSession?
    
    // Configurações
    let minDistance: Float = 40.0 // cm
    let maxDistance: Float = 120.0 // cm
    
    private init() {
        // Inicializa a sessão AR
        arSession = ARSession()
        
        // Inicializa as verificações
        setupVerifications()
        
        // Verifica capacidades do dispositivo e armazena o resultado
        let capabilities = checkDeviceCapabilities()
        print("Dispositivo tem TrueDepth: \(capabilities.hasTrueDepth), tem LiDAR: \(capabilities.hasLiDAR)")
    }
    
    // MARK: - Configurações e capacidades do dispositivo
    
    /// Verifica as capacidades do dispositivo em termos de sensores
    private func checkDeviceCapabilitiesInternal() -> (hasTrueDepth: Bool, hasLiDAR: Bool) {
        print("Verificando capacidades do dispositivo...")
        
        // Verifica TrueDepth (câmera frontal)
        if let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) {
            if !device.activeFormat.supportedDepthDataFormats.isEmpty {
                hasTrueDepth = true
                print("Sensor TrueDepth detectado")
            }
        }
        
        // Verifica LiDAR (câmera traseira)
        hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        
        if hasLiDAR {
            print("Sensor LiDAR detectado")
        }
        
        print("Capacidades do dispositivo - TrueDepth: \(hasTrueDepth), LiDAR: \(hasLiDAR)")
        return (hasTrueDepth, hasLiDAR)
    }
    
    /// Interface pública para verificação de capacidades do dispositivo
    func checkDeviceCapabilities() -> (hasTrueDepth: Bool, hasLiDAR: Bool) {
        return checkDeviceCapabilitiesInternal()
    }
    
    /// Configura a sessão AR para o tipo de câmera especificado
    func createARSession(for cameraType: CameraType) -> ARSession {
        // Se já existe uma sessão, pausa e remove as configurações antigas
        if let existingSession = self.arSession {
            existingSession.pause()
            self.arSession = nil
        }
        
        // Cria uma nova sessão AR
        let newSession = ARSession()
        self.arSession = newSession
        
        // Configura a sessão com as opções apropriadas
        let configuration: ARConfiguration
        var configurationError: String? = nil
        
        do {
            switch cameraType {
            case .front:
                // Verifica se o dispositivo suporta rastreamento facial
                guard ARFaceTrackingConfiguration.isSupported else {
                    configurationError = "Este dispositivo não suporta rastreamento facial (TrueDepth)."
                    throw NSError(domain: "ARError", code: 1001, userInfo: [NSLocalizedDescriptionKey: configurationError ?? "Erro desconhecido"])
                }
                
                let faceConfig = ARFaceTrackingConfiguration()
                faceConfig.maximumNumberOfTrackedFaces = 1
                if #available(iOS 13.0, *) {
                    faceConfig.isLightEstimationEnabled = true
                }
                configuration = faceConfig
                print("Configurando sessão AR para rastreamento facial")
                
            case .back:
                // Verifica se o dispositivo suporta rastreamento de mundo
                guard ARWorldTrackingConfiguration.isSupported else {
                    configurationError = "Este dispositivo não suporta rastreamento de mundo."
                    throw NSError(domain: "ARError", code: 1002, userInfo: [NSLocalizedDescriptionKey: configurationError ?? "Erro desconhecido"])
                }
                
                let worldConfig = ARWorldTrackingConfiguration()
                
                // Habilita reconstrução de cena e dados de profundidade se LiDAR disponível
                if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                    worldConfig.sceneReconstruction = .mesh
                    worldConfig.frameSemantics.insert(.sceneDepth)
                    print("Configurando sessão AR com LiDAR para profundidade")
                }
                
                configuration = worldConfig
            }
            
            // Executa a configuração com tratamento de erros
            newSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            print("Sessão AR configurada com sucesso para \(cameraType)")
            
        } catch {
            // Em caso de erro, notifica a view para exibir uma mensagem ao usuário
            let errorMessage = configurationError ?? "Falha ao configurar a sessão AR: \(error.localizedDescription)"
            print(errorMessage)
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("ARConfigurationFailed"),
                    object: nil,
                    userInfo: ["error": errorMessage]
                )
            }
            
            // Configura uma sessão vazia para evitar crashes
            let emptyConfig = ARWorldTrackingConfiguration()
            newSession.run(emptyConfig, options: [.resetTracking, .removeExistingAnchors])
        }
        
        return newSession
    }
    
    private func setupVerifications() {
        // Cria as verificações na ordem correta
        verifications = [
            Verification(id: 1, type: .faceDetection, isChecked: false),
            Verification(id: 2, type: .distance, isChecked: false),
            Verification(id: 3, type: .centering, isChecked: false),
            Verification(id: 4, type: .headAlignment, isChecked: false),
            Verification(id: 5, type: .frameDetection, isChecked: false),
            Verification(id: 6, type: .frameTilt, isChecked: false),
            Verification(id: 7, type: .gaze, isChecked: false)
        ]
    }
    
    // Verifica se todas as verificações obrigatórias estão corretas
    var allVerificationsChecked: Bool {
        // Para fins de teste, apenas as verificações 1 e 2 são obrigatórias
        return faceDetected && distanceCorrect
    }
    
    // MARK: - ARKit Integração para verificações
    
    /// Processa um frame ARFrame para realizar todas as verificações
    func processARFrame(_ frame: ARFrame) {
        // Verifica se o frame é válido
        guard case .normal = frame.camera.trackingState else {
            print("Aviso: Rastreamento da câmera não está no estado normal: \(frame.camera.trackingState)")
            return
        }
        
        // Verificação 1: Detecção de rosto
        let faceDetected = checkFaceDetection(in: frame)
        
        // Só continua com as demais verificações se um rosto for detectado
        if faceDetected {
            // Verificação 2: Distância
            let distanceOk = checkDistance(in: frame)
            
            // Verificação 3: Centralização do rosto
            if distanceOk {
                let centeredOk = checkFaceCentering(in: frame)
                
                // Verificação 4: Alinhamento da cabeça
                if centeredOk {
                    let headAlignedOk = checkHeadAlignment(in: frame)
                    
                    // Verificação 5: Direcionamento do olhar
                    if headAlignedOk {
                        let gazeOk = checkGaze(in: frame)
                        print("Olhar direcionado para a câmera: \(gazeOk)")
                    }
                }
            }
            
            // Log detalhado apenas se estiver em modo de depuração
            #if DEBUG
            print("Verificações sequenciais: " +
                  "Rosto=\(faceDetected), " +
                  "Distância=\(distanceOk), " +
                  "Centralizado=\(self.faceAligned), " +
                  "Cabeça=\(self.headAligned), " +
                  "Olhar=\(self.gazeCorrect)")
            #endif
        } else {
            // Se nenhum rosto for detectado, redefine todas as verificações
            resetAllVerifications()
            print("Verificações com ARKit: Nenhum rosto detectado")
        }
        
        // Atualiza as verificações na thread principal
        DispatchQueue.main.async { [weak self] in
            self?.updateVerificationStatus()
        }
    }
    
    /// Redefine todas as verificações para o estado inicial
    private func resetAllVerifications() {
        faceDetected = false
        distanceCorrect = false
        faceAligned = false
        headAligned = false
        frameDetected = false
        frameAligned = false
        gazeCorrect = false
        
        // Atualiza a lista de verificações
        for i in 0..<verifications.count {
            verifications[i].isChecked = false
        }
    }
    
    /// Verifica se há um rosto detectado no frame
    private func checkFaceDetection(in frame: ARFrame) -> Bool {
        // Verifica se há âncoras de rosto no frame
        let hasFaceAnchor = frame.anchors.contains { $0 is ARFaceAnchor }
        
        // Atualiza o estado na thread principal
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.faceDetected = hasFaceAnchor
            
            // Atualiza a verificação correspondente
            if let index = self.verifications.firstIndex(where: { $0.type == .faceDetection }) {
                self.verifications[index].isChecked = hasFaceAnchor
            }
        }
        
        return hasFaceAnchor
    }
    
    /// Verifica a distância do usuário à câmera
    private func checkDistance(in frame: ARFrame) -> Bool {
        // Verificação com TrueDepth (câmera frontal)
        if let faceAnchor = frame.anchors.first(where: { $0 is ARFaceAnchor }) as? ARFaceAnchor {
            // Calcula a distância da câmera ao rosto usando a posição Z da âncora
            // A posição Z é negativa e representa a distância em metros
            let distanceInMeters = abs(faceAnchor.transform.columns.3.z)
            let distanceInCm = distanceInMeters * 100
            
            // Armazena a distância medida com precisão
            let finalDistanceInCm = Float(distanceInCm)
            let isDistanceOk = finalDistanceInCm >= minDistance && finalDistanceInCm <= maxDistance
            
            // Atualiza o estado na thread principal
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lastMeasuredDistance = finalDistanceInCm
                self.distanceCorrect = isDistanceOk
                self.deviceHasDepthSensor = true
                
                // Atualiza a verificação correspondente
                if let index = self.verifications.firstIndex(where: { $0.type == .distance }) {
                    self.verifications[index].isChecked = isDistanceOk
                    self.verifications[index].value = String(format: "%.1f cm", finalDistanceInCm)
                }
            }
            
            return isDistanceOk
        }
        // Verificação com LiDAR (câmera traseira)
        else if let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth {
            // Usa o mapa de profundidade para estimar a distância
            let depthMap = depthData.depthMap
            let distanceInMeters = getAverageDepth(from: depthMap)
            let distanceInCm = distanceInMeters * 100
            
            // Armazena a distância medida
            let finalDistanceInCm = Float(distanceInCm)
            let isDistanceOk = finalDistanceInCm >= minDistance && finalDistanceInCm <= maxDistance
            
            // Atualiza o estado na thread principal
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lastMeasuredDistance = finalDistanceInCm
                self.distanceCorrect = isDistanceOk
                self.deviceHasDepthSensor = true
                
                // Atualiza a verificação correspondente
                if let index = self.verifications.firstIndex(where: { $0.type == .distance }) {
                    self.verifications[index].isChecked = isDistanceOk
                    self.verifications[index].value = String(format: "%.1f cm", finalDistanceInCm)
                }
            }
            
            return isDistanceOk
        }
        
        // Se não for possível medir a distância
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.distanceCorrect = false
        }
        return false
    }
    
    /// Verifica se o rosto está centralizado no frame
    func checkFaceCentering(in frame: ARFrame) -> Bool {
        guard let faceAnchor = frame.anchors.first(where: { $0 is ARFaceAnchor }) as? ARFaceAnchor else {
            self.faceAligned = false
            self.faceCentered = false
            return false
        }
        
        // Obtém a posição X e Y do rosto
        let facePosition = faceAnchor.transform.columns.3
        
        // Tolerância de centralização em metros (0.5 cm = 0.005 metros)
        let tolerance: Float = 0.005
        
        // Verifica se o rosto está centralizado (X e Y próximos de zero)
        let isCentered = abs(facePosition.x) < tolerance && abs(facePosition.y) < tolerance
        
        // Atualiza tanto faceAligned quanto faceCentered (para compatibilidade)
        self.faceAligned = isCentered
        self.faceCentered = isCentered
        
        // Atualiza facePosition para compatibilidade com código antigo
        self.facePosition = ["x": facePosition.x, "y": facePosition.y, "z": facePosition.z]
        
        return isCentered
    }
    
    /// Verifica se a cabeça está alinhada corretamente
    func checkHeadAlignment(in frame: ARFrame) -> Bool {
        guard let faceAnchor = frame.anchors.first(where: { $0 is ARFaceAnchor }) as? ARFaceAnchor else {
            self.headAligned = false
            return false
        }
        
        // Extrai os ângulos de Euler da matriz de transformação
        let transform = faceAnchor.transform
        
        // Converte a matriz de rotação para ângulos de Euler
        let pitch = asin(-transform.columns.2.y)
        let yaw = atan2(transform.columns.2.x, transform.columns.2.z)
        let roll = atan2(transform.columns.0.y, transform.columns.1.y)
        
        // Converte para graus
        let pitchDegrees = abs(pitch * 180 / .pi)
        let yawDegrees = abs(yaw * 180 / .pi)
        let rollDegrees = abs(roll * 180 / .pi)
        
        // Tolerância de 2 graus para cada eixo
        let tolerance: Float = 2.0
        
        // Verifica se todos os ângulos estão dentro da tolerância
        let isAligned = pitchDegrees < tolerance && yawDegrees < tolerance && rollDegrees < tolerance
        
        self.headAligned = isAligned
        
        // Atualiza o headRoll e alignmentData para compatibilidade com código antigo
        self.headRoll = Float(roll)
        self.alignmentData = ["pitch": Float(pitchDegrees),
                             "yaw": Float(yawDegrees),
                             "roll": Float(rollDegrees)]
        
        return isAligned
    }
    
    /// Verifica se o olhar está direcionado para a câmera
    func checkGaze(in frame: ARFrame) -> Bool {
        guard let faceAnchor = frame.anchors.first(where: { $0 is ARFaceAnchor }) as? ARFaceAnchor else {
            self.gazeCorrect = false
            return false
        }
        
        // Usa os blend shapes para verificar o olhar
        let blendShapes = faceAnchor.blendShapes
        
        // Verifica se os olhos estão abertos
        let leftEyeBlink = blendShapes[.eyeBlinkLeft]?.floatValue ?? 0.0
        let rightEyeBlink = blendShapes[.eyeBlinkRight]?.floatValue ?? 0.0
        
        // Considera que os olhos estão abertos se o valor de piscar for menor que 0.5
        let eyesOpen = leftEyeBlink < 0.5 && rightEyeBlink < 0.5
        
        // Verifica a direção do olhar usando os blend shapes
        // Nota: ARKit não tem BlendShapeLocation.lookAtPoint, usamos eye look in/out como alternativa
        let lookUpLeft = blendShapes[.eyeLookInLeft]?.floatValue ?? 0.0
        let lookDownLeft = blendShapes[.eyeLookOutLeft]?.floatValue ?? 0.0
        let lookUpRight = blendShapes[.eyeLookInRight]?.floatValue ?? 0.0
        let lookDownRight = blendShapes[.eyeLookOutRight]?.floatValue ?? 0.0
        let eyeSquintLeft = blendShapes[.eyeSquintLeft]?.floatValue ?? 0.0
        let eyeSquintRight = blendShapes[.eyeSquintRight]?.floatValue ?? 0.0
        
        // Verifica se o olhar está direcionado para a câmera (sem desvio significativo)
        let gazeStraight = (lookUpLeft < 0.2 && lookDownLeft < 0.2 &&
                          lookUpRight < 0.2 && lookDownRight < 0.2 &&
                          eyeSquintLeft < 0.3 && eyeSquintRight < 0.3)
        
        // Atualiza gazeData para compatibilidade com código antigo
        gazeData = ["leftEyeBlink": leftEyeBlink,
                   "rightEyeBlink": rightEyeBlink,
                   "lookUpLeft": lookUpLeft,
                   "lookUpRight": lookUpRight,
                   "eyeSquintLeft": eyeSquintLeft,
                   "eyeSquintRight": eyeSquintRight]
        
        // O olhar está correto se os olhos estão abertos e direcionados para a frente
        let isGazeCorrect = eyesOpen && gazeStraight
        
        self.gazeCorrect = isGazeCorrect
        return isGazeCorrect
    }
    
    /// Obtém a profundidade média de um mapa de profundidade
    private func getAverageDepth(from depthMap: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        // Considera apenas a região central (25% da área total)
        let centerRegionWidth = width / 2
        let centerRegionHeight = height / 2
        let startX = (width - centerRegionWidth) / 2
        let startY = (height - centerRegionHeight) / 2
        
        // Obtém o formato dos pixels
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)!
        
        var totalDepth: Float = 0.0
        var validSamples = 0
        
        // Para mapa de profundidade de 32 bits (Float32)
        for y in startY..<(startY + centerRegionHeight) {
            for x in startX..<(startX + centerRegionWidth) {
                let pixelAddress = baseAddress.advanced(by: y * bytesPerRow + x * MemoryLayout<Float32>.size)
                let depth = pixelAddress.assumingMemoryBound(to: Float32.self).pointee
                
                // Apenas considere valores válidos (maior que zero)
                if depth > 0 {
                    totalDepth += Float(depth)
                    validSamples += 1
                }
            }
        }
        
        // Calcula a média
        let averageDepth = validSamples > 0 ? Double(totalDepth / Float(validSamples)) : 0.0
        return averageDepth
    }
    
    // Método público para atualizar as verificações a partir de extensões
    func updateAllVerifications() {
        updateVerificationStatus()
    }
    
    // Reseta todas as verificações após um determinado tipo
    private func resetVerificationsAfter(_ type: VerificationType) {
        // Encontra o índice da verificação especificada
        guard let typeIndex = verifications.firstIndex(where: { $0.type == type }) else { return }
        
        // Obtemos os tipos das verificações subsequentes
        let subsequentTypes = VerificationType.allCases.filter { currentType in
            guard let currentIndex = verifications.firstIndex(where: { $0.type == currentType }) else { return false }
            return currentIndex > typeIndex
        }
        
        // Reseta todas as verificações subsequentes
        for verificationType in subsequentTypes {
            if let index = verifications.firstIndex(where: { $0.type == verificationType }) {
                verifications[index].isChecked = false
            }
            
            // Reseta também os estados correspondentes
            switch verificationType {
            case .distance:
                distanceCorrect = false
            case .centering:
                faceAligned = false
            case .headAlignment:
                headAligned = false
            case .frameDetection:
                frameDetected = false
            case .frameTilt:
                frameAligned = false
            case .gaze:
                gazeCorrect = false
            default:
                break
            }
        }
    }
    
    // Atualiza o status das verificações com base nos estados atuais e na lógica sequencial
    private func updateVerificationStatus() {
        // Implementação da lógica sequencial - cada etapa depende da anterior
        // Etapa 1: Detecção de rosto (independente, sempre verificada)
        if let index = verifications.firstIndex(where: { $0.type == .faceDetection }) {
            verifications[index].isChecked = faceDetected
        }
        
        // Se o rosto não for detectado, todas as outras verificações falham
        if !faceDetected {
            resetVerificationsAfter(.faceDetection)
            return
        }
        
        // Etapa 2: Verificação de distância (depende da detecção de rosto)
        if let index = verifications.firstIndex(where: { $0.type == .distance }) {
            verifications[index].isChecked = distanceCorrect
        }
        
        // Se a distância não estiver correta, todas as verificações subsequentes falham
        if !distanceCorrect {
            resetVerificationsAfter(.distance)
            return
        }
        
        // Etapa 3: Centralização do rosto (depende da distância)
        if let index = verifications.firstIndex(where: { $0.type == .centering }) {
            verifications[index].isChecked = faceAligned
        }
        
        // Se o rosto não estiver centralizado, as próximas falham
        if !faceAligned {
            resetVerificationsAfter(.centering)
            return
        }
        
        // Etapa 4: Alinhamento da cabeça (depende da centralização)
        if let index = verifications.firstIndex(where: { $0.type == .headAlignment }) {
            verifications[index].isChecked = headAligned
        }
        
        // Se a cabeça não estiver alinhada, as próximas falham
        if !headAligned {
            resetVerificationsAfter(.headAlignment)
            return
        }
        
        // Etapa 5: Detecção da armação (opcional, depende do alinhamento da cabeça)
        if let index = verifications.firstIndex(where: { $0.type == .frameDetection }) {
            verifications[index].isChecked = frameDetected
        }
        
        // Se a armação for obrigatória mas não for detectada, as próximas falham
        // Como é opcional para teste, continuamos mesmo se falhar
        
        // Etapa 6: Alinhamento da armação (opcional, depende da detecção da armação)
        if let index = verifications.firstIndex(where: { $0.type == .frameTilt }) {
            verifications[index].isChecked = frameDetected && frameAligned
        }
        
        // Etapa 7: Direção do olhar (depende de todas as anteriores)
        if let index = verifications.firstIndex(where: { $0.type == .gaze }) {
            verifications[index].isChecked = gazeCorrect
        }
    }
}
