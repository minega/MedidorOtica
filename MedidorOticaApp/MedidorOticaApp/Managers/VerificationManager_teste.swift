//
//  VerificationManager.swift
//  MedidorOticaApp
//
//  Gerenciador central para as verificações de medição óptica
//

import Foundation
import Vision
import AVFoundation
import ARKit
import Combine

// Tipos de câmera disponíveis
enum CameraType {
    case front // Câmera frontal (TrueDepth)
    case back  // Câmera traseira (LiDAR)
}

class VerificationManager: ObservableObject {
    static let shared = VerificationManager()

    // Publicação das verificações para a interface
    @Published var verifications: [Verification] = []

    /// Passo atual da máquina de estados
    @Published var currentStep: VerificationStep = .idle

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

    /// Controle de frequência das atualizações (15 fps)
    private var lastPublishTime = Date.distantPast
    private let publishInterval: TimeInterval = 1.0 / 15.0
    
    // Controle de taxa de quadros para processamento
    private var lastProcessedFrameTime: TimeInterval = 0
    
    // Compatibilidade com código antigo
    @Published var gazeData: [String: Float] = [:] // Para compatiblidade com código antigo
    @Published var alignmentData: [String: Float] = [:] // Para compatiblidade com código antigo
    @Published var facePosition: [String: Float] = [:] // Para compatiblidade com código antigo
    
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
    
    /// Verifica e armazena as capacidades do dispositivo
    func checkDeviceCapabilities() -> (hasTrueDepth: Bool, hasLiDAR: Bool) {
        print("Verificando capacidades do dispositivo...")

        // TrueDepth (câmera frontal)
        if let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front),
           !device.activeFormat.supportedDepthDataFormats.isEmpty {
            hasTrueDepth = true
            print("Sensor TrueDepth detectado")
        }

        // LiDAR (câmera traseira)
        hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        if hasLiDAR { print("Sensor LiDAR detectado") }

        print("Capacidades do dispositivo - TrueDepth: \(hasTrueDepth), LiDAR: \(hasLiDAR)")
        return (hasTrueDepth, hasLiDAR)
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
    
    /// Processa um `ARFrame` realizando todas as verificações sequenciais
    func processARFrame(_ frame: ARFrame) {
        // Aviso de rastreamento limitado
        if case .limited = frame.camera.trackingState {
            print("⚠️ Aviso: rastreamento limitado - resultados podem ser imprecisos")
        }
        
        // Verifica se já estamos processando um frame para evitar sobrecarga
        let currentTime = Date().timeIntervalSince1970
        guard currentTime - lastProcessedFrameTime > 0.05 else { // Limita a ~20fps
            return
        }
        lastProcessedFrameTime = currentTime
        
        // Processa em uma fila de alta prioridade para não bloquear a thread principal
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Marca o tempo de início do processamento para medição de desempenho
            let startTime = Date()
            
            // Primeira verificação: detecção de rosto
            let facePresent = self.checkFaceDetection(using: frame)
            
            // Obtém o faceAnchor apenas uma vez para otimização
            let faceAnchor = frame.anchors.first { $0 is ARFaceAnchor } as? ARFaceAnchor
            
            // Variáveis para armazenar os resultados das verificações
            var distanceOk = false
            var centeredOk = false
            var headAlignedOk = false
            var gazeOk = false
            
            // Executa as verificações sequencialmente, parando na primeira que falhar
            if facePresent {
                print("✅ Rosto detectado, verificando distância...")
                distanceOk = self.checkDistance(using: frame, faceAnchor: faceAnchor)
                
                if distanceOk {
                    print("✅ Distância correta, verificando centralização...")
                    centeredOk = self.checkFaceCentering(using: frame, faceAnchor: faceAnchor)
                    
                    if centeredOk {
                        print("✅ Rosto centralizado, verificando alinhamento da cabeça...")
                        headAlignedOk = self.checkHeadAlignment(using: frame, faceAnchor: faceAnchor)
                        
                        if headAlignedOk {
                            print("✅ Cabeça alinhada, verificando direção do olhar...")
                            gazeOk = self.checkGaze(using: frame)
                            if gazeOk {
                                print("✅ Todas as verificações concluídas com sucesso!")
                            }
                        }
                    }
                }
            } else {
                print("❌ Nenhum rosto detectado no frame atual")
            }
            
            // Calcula o tempo total de processamento
            let processingTime = Date().timeIntervalSince(startTime) * 1000 // em milissegundos
            if processingTime > 30 { // Log apenas se o processamento estiver demorando muito
                print("⏱️ Tempo de processamento do frame: \(String(format: "%.1f", processingTime))ms")
            }
            
            // Atualiza a interface na thread principal
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Armazena os estados atuais para verificar mudanças
                let previousStates = (
                    faceDetected: self.faceDetected,
                    distanceCorrect: self.distanceCorrect,
                    faceAligned: self.faceAligned,
                    headAligned: self.headAligned,
                    gazeCorrect: self.gazeCorrect
                )
                
                // Atualiza os estados
                self.faceDetected = facePresent
                self.distanceCorrect = distanceOk
                
                // Só atualiza as verificações subsequentes se as anteriores estiverem OK
                if facePresent && distanceOk {
                    self.faceAligned = centeredOk
                    
                    if centeredOk {
                        self.headAligned = headAlignedOk
                        
                        if headAlignedOk {
                            self.gazeCorrect = gazeOk
                        }
                    }
                } else {
                    // Reseta as verificações subsequentes se alguma anterior falhar
                    if !facePresent { 
                        print("🔄 Resetando verificações (nenhum rosto detectado)")
                        self.resetNonFaceVerifications() 
                    }
                    if !distanceOk { 
                        print("🔄 Resetando verificações (distância incorreta)")
                        self.faceAligned = false; 
                        self.headAligned = false; 
                        self.gazeCorrect = false 
                    }
                    if !centeredOk { 
                        print("🔄 Resetando verificações (rosto não centralizado)")
                        self.headAligned = false; 
                        self.gazeCorrect = false 
                    }
                    if !headAlignedOk { 
                        print("🔄 Resetando verificações (cabeça desalinhada)")
                        self.gazeCorrect = false 
                    }
                }
                
                // Verifica se houve mudança nos estados para evitar atualizações desnecessárias
                let statesChanged = 
                    previousStates.faceDetected != facePresent ||
                    previousStates.distanceCorrect != distanceOk ||
                    previousStates.faceAligned != centeredOk ||
                    previousStates.headAligned != headAlignedOk ||
                    previousStates.gazeCorrect != gazeOk
                
                if statesChanged {
                    // Atualiza a interface com o estado atual
                    self.updateVerificationStatus(throttled: true)
                    
                    #if DEBUG
                    print("🔄 Atualização de estado: " +
                          "Rosto=\(facePresent), " +
                          "Distância=\(distanceOk), " +
                          "Centralizado=\(centeredOk), " +
                          "Cabeça=\(headAlignedOk), " +
                          "Olhar=\(gazeOk)")
                    #endif
                }
            }
        }
    }
    
    /// Redefine todas as verificações para o estado inicial
    private func resetAllVerifications() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.faceDetected = false
            self.distanceCorrect = false
            self.faceAligned = false
            self.headAligned = false
            self.frameDetected = false
            self.frameAligned = false
            self.gazeCorrect = false

            // Atualiza a lista de verificações
            for i in 0..<self.verifications.count {
                self.verifications[i].isChecked = false
                needsUpdate = true
            }
        }
    func updateAllVerifications() {
        updateVerificationStatus(throttled: true)
    }

    /// Permite resetar todas as verificações externamente
    func reset() {
        resetAllVerifications()
        updateVerificationStatus(throttled: true)
    }
    
    /// Reinicia todas as verificações, exceto a detecção de rosto
    private func resetNonFaceVerifications() {
        print("🔄 Iniciando reset de verificações não relacionadas a rosto...")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                print("❌ Erro: self é nulo em resetNonFaceVerifications")
                return
            }
            
            // Armazena os valores atuais para verificar se houve mudança
            let previousStates = (
                distanceCorrect: self.distanceCorrect,
                faceAligned: self.faceAligned,
                headAligned: self.headAligned,
                frameDetected: self.frameDetected,
                frameAligned: self.frameAligned,
                gazeCorrect: self.gazeCorrect
            )
            
            // Reseta todos os estados para falso
            self.distanceCorrect = false
            self.faceAligned = false
            self.headAligned = false
            self.frameDetected = false
            self.frameAligned = false
            self.gazeCorrect = false
            
            // Log dos estados anteriores
            print("📊 Estados anteriores ao reset:")
            print("  - Distância correta: \(previousStates.distanceCorrect)")
            print("  - Rosto alinhado: \(previousStates.faceAligned)")
            print("  - Cabeça alinhada: \(previousStates.headAligned)")
            print("  - Armação detectada: \(previousStates.frameDetected)")
            print("  - Armação alinhada: \(previousStates.frameAligned)")
            print("  - Olhar correto: \(previousStates.gazeCorrect)")
            
            // Atualiza a lista de verificações
            var updatedVerifications: [VerificationType: Bool] = [:]
            var needsUpdate = false
            
            // Itera por todas as verificações, exceto a de detecção de rosto
            for i in 0..<self.verifications.count where self.verifications[i].type != .faceDetection {
                let type = self.verifications[i].type
                let wasChecked = self.verifications[i].isChecked
                
                if wasChecked {
                    self.verifications[i].isChecked = false
                    needsUpdate = true
                    updatedVerifications[type] = false
                }
            }
            
            // Verifica se houve alguma mudança nos estados
            let statesChanged = 
                previousStates.distanceCorrect || 
                previousStates.faceAligned || 
                previousStates.headAligned || 
                previousStates.frameDetected || 
                previousStates.frameAligned || 
                previousStates.gazeCorrect ||
                !updatedVerifications.isEmpty
            
            // Log das verificações atualizadas
            if !updatedVerifications.isEmpty {
                print("🔄 Verificações atualizadas:")
                for (type, isChecked) in updatedVerifications {
                    print("  - \(type.rawValue): \(isChecked)")
                }
            } else {
                print("ℹ️ Nenhuma verificação não-rosto para atualizar")
            }
            
            // Só notifica se houve mudança
            if statesChanged {
                print("🔄 Estados alterados, atualizando interface...")
                self.updateVerificationStatus(throttled: true)
                
                #if DEBUG
                // Log detalhado em modo debug
                print("🔍 Estado após reset de verificações não-rosto:")
                print("  - distanceCorrect: \(self.distanceCorrect)")
                print("  - faceAligned: \(self.faceAligned)")
                print("  - headAligned: \(self.headAligned)")
                print("  - frameDetected: \(self.frameDetected)")
                print("  - frameAligned: \(self.frameAligned)")
                print("  - gazeCorrect: \(self.gazeCorrect)")
                #endif
            } else {
                print("ℹ️ Nenhuma mudança de estado detectada, pulando atualização")
            }
        }
    }
    
    // Reseta todas as verificações após um determinado tipo
    private func resetVerificationsAfter(_ type: VerificationType) {
        print("🔄 Resetando verificações após: \(type.rawValue)")
        
        // Encontra o índice da verificação especificada
        guard let typeIndex = verifications.firstIndex(where: { $0.type == type }) else {
            print("❌ Erro: Tipo de verificação não encontrado: \(type.rawValue)")
            return
        }
        
        // Obtém os tipos das verificações subsequentes
        let subsequentTypes = VerificationType.allCases.filter { currentType in
            guard let currentIndex = verifications.firstIndex(where: { $0.type == currentType }) else {
                print("⚠️ Aviso: Tipo de verificação não encontrado no array: \(currentType.rawValue)")
                return false
            }
            return currentIndex > typeIndex
        }
        
        print("  🔄 Tipos subsequentes a serem resetados: \(subsequentTypes.map { $0.rawValue }.joined(separator: ", "))")
        
        // Armazena os estados atuais para verificar mudanças
        let previousStates = (
            distanceCorrect: distanceCorrect,
            faceAligned: faceAligned,
            headAligned: headAligned,
            frameDetected: frameDetected,
            frameAligned: frameAligned,
            gazeCorrect: gazeCorrect
        )
        
        // Reseta todas as verificações subsequentes
        var updatedVerifications: [VerificationType] = []
        
        for verificationType in subsequentTypes {
            // Atualiza o array de verificações
            if let index = verifications.firstIndex(where: { $0.type == verificationType }),
               verifications[index].isChecked {
                verifications[index].isChecked = false
                updatedVerifications.append(verificationType)
            }
            
            // Reseta também os estados correspondentes
            var stateChanged = false
            
            switch verificationType {
            case .distance where distanceCorrect:
                distanceCorrect = false
                stateChanged = true
            case .centering where faceAligned:
                faceAligned = false
                stateChanged = true
            case .headAlignment where headAligned:
                headAligned = false
                stateChanged = true
            case .frameDetection where frameDetected:
                frameDetected = false
                stateChanged = true
            case .frameTilt where frameAligned:
                frameAligned = false
                stateChanged = true
            case .gaze where gazeCorrect:
                gazeCorrect = false
                stateChanged = true
            default:
                break
            }
            
            if stateChanged {
                print("  🔄 Estado alterado: \(verificationType.rawValue) = false")
            }
        }
        
        // Log das verificações atualizadas
        if !updatedVerifications.isEmpty {
            print("  🔄 Verificações resetadas: \(updatedVerifications.map { $0.rawValue }.joined(separator: ", "))")
        } else {
            print("  ℹ️ Nenhuma verificação subsequente para resetar após: \(type.rawValue)")
        }
        
        // Verifica se houve alguma mudança de estado
        let statesChanged = 
            previousStates.distanceCorrect != distanceCorrect ||
            previousStates.faceAligned != faceAligned ||
            previousStates.headAligned != headAligned ||
            previousStates.frameDetected != frameDetected ||
            previousStates.frameAligned != frameAligned ||
            previousStates.gazeCorrect != gazeCorrect ||
            !updatedVerifications.isEmpty
        
        if statesChanged {
            print("  ✅ Reset concluído para verificações após: \(type.rawValue)")
        } else {
            print("  ℹ️ Nenhuma mudança de estado detectada ao resetar verificações após: \(type.rawValue)")
        }
    }
    
    // Atualiza o status das verificações com base nos estados atuais e na lógica sequencial
    // Atualiza o status das verificações e a máquina de estados
    private func updateVerificationStatus(throttled: Bool = false) {
        // Controle de taxa para evitar sobrecarga de atualizações
        if throttled {
            let now = Date()
            let timeSinceLastUpdate = now.timeIntervalSince(lastPublishTime)
            
            // Se ainda não passou tempo suficiente desde a última atualização, ignora
            guard timeSinceLastUpdate >= publishInterval else {
                #if DEBUG
                print("⏱️ Pulando atualização - Muito cedo desde a última atualização: \(String(format: "%.3f", timeSinceLastUpdate))s")
                #endif
                return 
            }
            lastPublishTime = now
        }
        
        print("🔄 Iniciando atualização do status de verificação...")
        
        // Armazena o estado anterior para detecção de mudanças
        let previousStep = currentStep
        var updatedVerifications: [VerificationType: Bool] = [:]
        
        // Implementação da lógica sequencial - cada etapa depende da anterior
        // Etapa 1: Detecção de rosto (independente, sempre verificada)
        if let index = verifications.firstIndex(where: { $0.type == .faceDetection }) {
            if verifications[index].isChecked != faceDetected {
                verifications[index].isChecked = faceDetected
                updatedVerifications[.faceDetection] = faceDetected
                print("  - Atualizado faceDetection para: \(faceDetected)")
            }
        }

        // Se o rosto não for detectado, todas as outras verificações falham
        if !faceDetected {
            print("  ❌ Rosto não detectado, resetando verificações subsequentes...")
            resetVerificationsAfter(.faceDetection)
            currentStep = .faceDetection
            
            if previousStep != currentStep {
                print("  🔄 Mudança de estado: \(previousStep) -> \(currentStep)")
            }
            
            // Força a atualização da UI
            objectWillChange.send()
            return
        }

        // Etapa 2: Verificação de distância (depende da detecção de rosto)
        if let index = verifications.firstIndex(where: { $0.type == .distance }) {
            if verifications[index].isChecked != distanceCorrect {
                verifications[index].isChecked = distanceCorrect
                updatedVerifications[.distance] = distanceCorrect
                print("  - Atualizado distance para: \(distanceCorrect)")
            }
        }

        // Se a distância não estiver correta, todas as verificações subsequentes falham
        if !distanceCorrect {
            print("  ❌ Distância incorreta, resetando verificações subsequentes...")
            resetVerificationsAfter(.distance)
            currentStep = .distance
            
            if previousStep != currentStep {
                print("  🔄 Mudança de estado: \(previousStep) -> \(currentStep)")
            }
            
            // Força a atualização da UI
            objectWillChange.send()
            return
        }
        
        // Log das verificações atualizadas
        if !updatedVerifications.isEmpty {
            print("  🔄 Verificações atualizadas nesta iteração:")
            for (type, isChecked) in updatedVerifications {
                print("    - \(type.rawValue): \(isChecked)")
            }
        } else {
            print("  ℹ️ Nenhuma verificação atualizada nesta iteração")
        }

        // Etapa 3: Centralização do rosto (depende da distância)
        if let index = verifications.firstIndex(where: { $0.type == .centering }) {
            if verifications[index].isChecked != faceAligned {
                verifications[index].isChecked = faceAligned
                updatedVerifications[.centering] = faceAligned
                print("  - Atualizado centering para: \(faceAligned)")
            }
        }

        // Se o rosto não estiver centralizado, as próximas falham
        if !faceAligned {
            print("  ❌ Rosto não centralizado, resetando verificações subsequentes...")
            resetVerificationsAfter(.centering)
            currentStep = .centering
            
            if previousStep != currentStep {
                print("  🔄 Mudança de estado: \(previousStep) -> \(currentStep)")
            }
            
            // Força a atualização da UI
            objectWillChange.send()
            return
        }

        // Etapa 4: Alinhamento da cabeça (depende da centralização)
        if let index = verifications.firstIndex(where: { $0.type == .headAlignment }) {
            if verifications[index].isChecked != headAligned {
                verifications[index].isChecked = headAligned
                updatedVerifications[.headAlignment] = headAligned
                print("  - Atualizado headAlignment para: \(headAligned)")
            }
        }

        // Se a cabeça não estiver alinhada, as próximas falham
        if !headAligned {
            print("  ❌ Cabeça não alinhada, resetando verificações subsequentes...")
            resetVerificationsAfter(.headAlignment)
            currentStep = .headAlignment
            
            if previousStep != currentStep {
                print("  🔄 Mudança de estado: \(previousStep) -> \(currentStep)")
            }
            
            // Força a atualização da UI
            objectWillChange.send()
            return
        }

        // Etapa 5: Detecção da armação (opcional, depende do alinhamento da cabeça)
        if let index = verifications.firstIndex(where: { $0.type == .frameDetection }) {
            let newValue = frameDetected
            if verifications[index].isChecked != newValue {
                verifications[index].isChecked = newValue
                updatedVerifications[.frameDetection] = newValue
                print("  - Atualizado frameDetection para: \(newValue)")
            }
        }
        
        // Se a armação for obrigatória mas não for detectada, as próximas falham
        // Como é opcional para teste, continuamos mesmo se falhar

        // Etapa 6: Alinhamento da armação (opcional, depende da detecção da armação)
        if let index = verifications.firstIndex(where: { $0.type == .frameTilt }) {
            let newValue = frameDetected && frameAligned
            if verifications[index].isChecked != newValue {
                verifications[index].isChecked = newValue
                updatedVerifications[.frameTilt] = newValue
                print("  - Atualizado frameTilt para: \(newValue) (frameDetected: \(frameDetected), frameAligned: \(frameAligned))")
            }
        }

        // Etapa 7: Direção do olhar (depende de todas as anteriores)
        if let index = verifications.firstIndex(where: { $0.type == .gaze }) {
            if verifications[index].isChecked != gazeCorrect {
                verifications[index].isChecked = gazeCorrect
                updatedVerifications[.gaze] = gazeCorrect
                print("  - Atualizado gaze para: \(gazeCorrect)")
            }
        }

        // Atualiza o estado atual com base na verificação do olhar
        let newStep: VerificationStep = gazeCorrect ? .completed : .gaze
        if currentStep != newStep {
            print("  🔄 Mudança de estado: \(currentStep) -> \(newStep)")
            currentStep = newStep
        }
    }
}
