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

    /// Fila serial usada para processar os frames sem sobrecarregar a CPU.
    private let processingQueue = DispatchQueue(label: "com.oticaManzolli.verification.queue",
                                               qos: .userInitiated)

    /// Indica se um frame já está em processamento para evitar filas gigantes.
    private var isProcessingFrame = false

    /// Controle de frequência do processamento de frames (15 fps).
    private var lastFrameTime = Date.distantPast
    private let frameInterval: TimeInterval = 1.0 / 15.0

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
        // Controla a frequência do processamento para evitar sobrecarga
        let now = Date()
        guard !isProcessingFrame, now.timeIntervalSince(lastFrameTime) >= frameInterval else {
            return
        }
        lastFrameTime = now
        isProcessingFrame = true

        // Aviso de rastreamento limitado
        if case .limited = frame.camera.trackingState {
            print("Aviso: rastreamento limitado - resultados podem ser imprecisos")
        }

        processingQueue.async { [weak self] in
            guard let self = self else { return }
            // Garante que o flag seja resetado mesmo em retornos antecipados
            defer { isProcessingFrame = false }
            // MARK: Passo 1 - Detecção de rosto
            let facePresent = self.checkFaceDetection(using: frame)
            DispatchQueue.main.async { self.faceDetected = facePresent }

            guard facePresent else {
                self.resetNonFaceVerifications()
                DispatchQueue.main.async { [weak self] in
                    self?.updateVerificationStatus(throttled: true)
                }
                print("Verificações com ARKit: Nenhum rosto detectado")
                return
            }

            let faceAnchor = frame.anchors.first { $0 is ARFaceAnchor } as? ARFaceAnchor

            // MARK: Passo 2 - Distância
            let distanceOk = self.checkDistance(using: frame, faceAnchor: faceAnchor)
            DispatchQueue.main.async { self.distanceCorrect = distanceOk }
            guard distanceOk else {
                self.resetVerificationsAfter(.distance)
                DispatchQueue.main.async { [weak self] in
                    self?.updateVerificationStatus(throttled: true)
                }
                return
            }

            // MARK: Passo 3 - Centralização do rosto
            let centeredOk = self.checkFaceCentering(using: frame, faceAnchor: faceAnchor)
            DispatchQueue.main.async { self.faceAligned = centeredOk }
            guard centeredOk else {
                self.resetVerificationsAfter(.centering)
                DispatchQueue.main.async { [weak self] in
                    self?.updateVerificationStatus(throttled: true)
                }
                return
            }

            // MARK: Passo 4 - Alinhamento da cabeça
            let headAlignedOk = self.checkHeadAlignment(using: frame, faceAnchor: faceAnchor)
            DispatchQueue.main.async { self.headAligned = headAlignedOk }
            guard headAlignedOk else {
                self.resetVerificationsAfter(.headAlignment)
                DispatchQueue.main.async { [weak self] in
                    self?.updateVerificationStatus(throttled: true)
                }
                return
            }

            // MARK: Passo 5 - Direção do olhar
            let gazeOk = self.checkGaze(using: frame)
            DispatchQueue.main.async { self.gazeCorrect = gazeOk }

            #if DEBUG
            print("Verificações sequenciais: " +
                  "Rosto=\(facePresent), " +
                  "Distância=\(distanceOk), " +
                  "Centralizado=\(centeredOk), " +
                  "Cabeça=\(headAlignedOk), " +
                  "Olhar=\(gazeOk)")
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
            self.lastMeasuredDistance = 0

            // Trabalha em cópia para notificar a interface
            var updated = self.verifications
            for index in updated.indices { updated[index].isChecked = false }
            self.verifications = updated
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
            self.lastMeasuredDistance = 0

            var updated = self.verifications
            for index in updated.indices where updated[index].type != .faceDetection {
                updated[index].isChecked = false
            }
            self.verifications = updated
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
        guard let typeIndex = verifications.firstIndex(where: { $0.type == type }) else { return }

        let subsequentTypes = VerificationType.allCases.filter { currentType in
            guard let currentIndex = verifications.firstIndex(where: { $0.type == currentType }) else { return false }
            return currentIndex > typeIndex
        }

        DispatchQueue.main.async { [self] in
            var updated = verifications

            for verificationType in subsequentTypes {
                if let index = updated.firstIndex(where: { $0.type == verificationType }) {
                    updated[index].isChecked = false
                }

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

            verifications = updated
        }
    }
    
    // Atualiza o status das verificações conforme os estados atuais
    // Este método deve sempre executar no `DispatchQueue.main`
    private func updateVerificationStatus(throttled: Bool = false) {
        let publishWork = {
            if throttled {
                let now = Date()
                guard now.timeIntervalSince(lastPublishTime) >= publishInterval else { return }
                lastPublishTime = now
            }

            // Trabalha em cópia para garantir notificação do @Published
            var updated = verifications

            // Etapa 1: Detecção de rosto
            if let index = updated.firstIndex(where: { $0.type == .faceDetection }) {
                updated[index].isChecked = faceDetected
            }

            guard faceDetected else {
                resetVerificationsAfter(.faceDetection)
                currentStep = .faceDetection
                verifications = updated
                return
            }

            // Etapa 2: Verificação de distância
            if let index = updated.firstIndex(where: { $0.type == .distance }) {
                updated[index].isChecked = distanceCorrect
            }

            guard distanceCorrect else {
                resetVerificationsAfter(.distance)
                currentStep = .distance
                verifications = updated
                return
            }

            // Etapa 3: Centralização do rosto
            if let index = updated.firstIndex(where: { $0.type == .centering }) {
                updated[index].isChecked = faceAligned
            }

            guard faceAligned else {
                resetVerificationsAfter(.centering)
                currentStep = .centering
                verifications = updated
                return
            }

            // Etapa 4: Alinhamento da cabeça
            if let index = updated.firstIndex(where: { $0.type == .headAlignment }) {
                updated[index].isChecked = headAligned
            }

            guard headAligned else {
                resetVerificationsAfter(.headAlignment)
                currentStep = .headAlignment
                verifications = updated
                return
            }

            // Etapa 5: Detecção da armação (opcional)
            if let index = updated.firstIndex(where: { $0.type == .frameDetection }) {
                updated[index].isChecked = frameDetected
            }

            // Etapa 6: Inclinação da armação (opcional)
            if let index = updated.firstIndex(where: { $0.type == .frameTilt }) {
                updated[index].isChecked = frameDetected && frameAligned
            }

            // Etapa 7: Direção do olhar
            if let index = updated.firstIndex(where: { $0.type == .gaze }) {
                updated[index].isChecked = gazeCorrect
            }

            currentStep = gazeCorrect ? .completed : .gaze

            // Atualiza a propriedade publicada
            verifications = updated
        }

        if Thread.isMainThread {
            publishWork()
        } else {
            DispatchQueue.main.async(execute: publishWork)
        }
    }

    /// Sincroniza `hasTrueDepth` e `hasLiDAR` com o `CameraManager`.
    private func updateCapabilities(manager: CameraManager = .shared) {
        hasTrueDepth = manager.hasTrueDepth
        hasLiDAR = manager.hasLiDAR
    }
}
