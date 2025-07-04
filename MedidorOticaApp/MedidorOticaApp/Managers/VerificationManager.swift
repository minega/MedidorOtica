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
    
    // Compatibilidade com código antigo
    @Published var gazeData: [String: Float] = [:] // Para compatiblidade com código antigo
    @Published var alignmentData: [String: Float] = [:] // Para compatiblidade com código antigo
    @Published var facePosition: [String: Float] = [:] // Para compatiblidade com código antigo
    
    // Configurações
    let minDistance: Float = 40.0 // cm
    let maxDistance: Float = 120.0 // cm

    private init() {
        // Inicializa as verificações
        setupVerifications()

        // Sincroniza as capacidades do dispositivo a partir do CameraManager
        updateCapabilities()
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
            print("Aviso: rastreamento limitado - resultados podem ser imprecisos")
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Primeira verificação: detecção de rosto
            let facePresent = self.checkFaceDetection(using: frame)

            guard facePresent else {
                self.resetNonFaceVerifications()
                DispatchQueue.main.async { [weak self] in
                    self?.updateVerificationStatus(throttled: true)
                }
                print("Verificações com ARKit: Nenhum rosto detectado")
                return
            }

            let faceAnchor = frame.anchors.first { $0 is ARFaceAnchor } as? ARFaceAnchor
            let distanceOk = self.checkDistance(using: frame, faceAnchor: faceAnchor)
            if distanceOk {
                let centeredOk = self.checkFaceCentering(using: frame, faceAnchor: faceAnchor)

                if centeredOk {
                    let headAlignedOk = self.checkHeadAlignment(using: frame, faceAnchor: faceAnchor)

                    if headAlignedOk {
                        let gazeOk = self.checkGaze(using: frame)
                        print("Olhar direcionado para a câmera: \(gazeOk)")
                    }
                }
            }

            #if DEBUG
            print("Verificações sequenciais: " +
                  "Rosto=\(facePresent), " +
                  "Distância=\(distanceOk), " +
                  "Centralizado=\(self.faceAligned), " +
                  "Cabeça=\(self.headAligned), " +
                  "Olhar=\(self.gazeCorrect)")
            #endif

            DispatchQueue.main.async { [weak self] in
                self?.updateVerificationStatus(throttled: true)
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
            }
        }
    }

    /// Reseta todas as verificações exceto a detecção de rosto
    private func resetNonFaceVerifications() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.distanceCorrect = false
            self.faceAligned = false
            self.headAligned = false
            self.frameDetected = false
            self.frameAligned = false
            self.gazeCorrect = false

            for i in 0..<self.verifications.count {
                if self.verifications[i].type != .faceDetection {
                    self.verifications[i].isChecked = false
                }
            }
        }
    }

    
    /// Método público para atualizar as verificações a partir de extensões
    func updateAllVerifications() {
        updateVerificationStatus(throttled: true)
    }

    /// Permite resetar todas as verificações externamente
    func reset() {
        resetAllVerifications()
        updateVerificationStatus(throttled: true)
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
    // Atualiza o status das verificações e a máquina de estados
    private func updateVerificationStatus(throttled: Bool = false) {
        if throttled {
            let now = Date()
            guard now.timeIntervalSince(lastPublishTime) >= publishInterval else { return }
            lastPublishTime = now
        }

        // Implementação da lógica sequencial - cada etapa depende da anterior
        // Etapa 1: Detecção de rosto (independente, sempre verificada)
        if let index = verifications.firstIndex(where: { $0.type == .faceDetection }) {
            verifications[index].isChecked = faceDetected
        }

        // Se o rosto não for detectado, todas as outras verificações falham
        if !faceDetected {
            resetVerificationsAfter(.faceDetection)
            currentStep = .faceDetection
            return
        }

        // Etapa 2: Verificação de distância (depende da detecção de rosto)
        if let index = verifications.firstIndex(where: { $0.type == .distance }) {
            verifications[index].isChecked = distanceCorrect
        }

        // Se a distância não estiver correta, todas as verificações subsequentes falham
        if !distanceCorrect {
            resetVerificationsAfter(.distance)
            currentStep = .distance
            return
        }

        // Etapa 3: Centralização do rosto (depende da distância)
        if let index = verifications.firstIndex(where: { $0.type == .centering }) {
            verifications[index].isChecked = faceAligned
        }

        // Se o rosto não estiver centralizado, as próximas falham
        if !faceAligned {
            resetVerificationsAfter(.centering)
            currentStep = .centering
            return
        }

        // Etapa 4: Alinhamento da cabeça (depende da centralização)
        if let index = verifications.firstIndex(where: { $0.type == .headAlignment }) {
            verifications[index].isChecked = headAligned
        }

        // Se a cabeça não estiver alinhada, as próximas falham
        if !headAligned {
            resetVerificationsAfter(.headAlignment)
            currentStep = .headAlignment
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

        currentStep = gazeCorrect ? .completed : .gaze
    }

    /// Sincroniza `hasTrueDepth` e `hasLiDAR` com o `CameraManager`.
    private func updateCapabilities(manager: CameraManager = .shared) {
        hasTrueDepth = manager.hasTrueDepth
        hasLiDAR = manager.hasLiDAR
    }
}
