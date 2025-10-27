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
import CoreGraphics

/// Gerencia todas as verificações de medição óptica.
final class VerificationManager: ObservableObject {
    static let shared = VerificationManager()

    // Publicação das verificações para a interface
    @Published var verifications: [Verification] = []

    /// Passo atual da máquina de estados
    @Published var currentStep: VerificationStep = .idle

    /// Representa o sensor ativo para as verificações AR.
    enum SensorType {
        case none
        case trueDepth
        case liDAR
    }

    /// Sensor que deve ser utilizado prioritariamente nas verificações.
    @Published private(set) var activeSensor: SensorType = .none

    // Estado atual de cada verificação
    @Published var faceDetected = false
    @Published var distanceCorrect = false
    @Published var faceAligned = false
    @Published var headAligned = false
    
    // Medições precisas
    @Published var lastMeasuredDistance: Float = 0.0 // em centímetros, com precisão de 0,5mm

    /// Coordenadas normalizadas das pupilas exibidas na tela.
    @Published var pupilCenters: (left: CGPoint, right: CGPoint)?
    
    // Status do dispositivo e sensores
    @Published var hasTrueDepth = false // Indica se o dispositivo tem sensor TrueDepth
    @Published var hasLiDAR = false // Indica se o dispositivo tem sensor LiDAR

    /// Controle de frequência das atualizações (15 fps)
    private var lastPublishTime = Date.distantPast
    private let publishInterval: TimeInterval = 1.0 / 15.0
    
    // Compatibilidade com código antigo
    @Published var alignmentData: [String: Float] = [:] // Para compatiblidade com código antigo
    @Published var facePosition: [String: Float] = [:] // Para compatiblidade com código antigo

    
    // Configurações
    /// Distância mínima permitida em centímetros
    var minDistance: Float { DistanceLimits.minCm }
    /// Distância máxima permitida em centímetros
    var maxDistance: Float { DistanceLimits.maxCm }

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
        // A sincronização com a câmera é feita externamente para evitar ciclos de inicialização.
    }
    private func setupVerifications() {
        // Cria as verificações na ordem correta
        verifications = [
            Verification(id: 1, type: .faceDetection, isChecked: false),
            Verification(id: 2, type: .distance, isChecked: false),
            Verification(id: 3, type: .centering, isChecked: false),
            Verification(id: 4, type: .headAlignment, isChecked: false)
        ]
    }
    
    // Verifica se todas as verificações obrigatórias estão corretas
    var allVerificationsChecked: Bool {
        return faceDetected && distanceCorrect && faceAligned && headAligned
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

            // Atualiza o rastreamento das pupilas antes das demais verificações.
            self.updatePupilTracking(using: frame, faceAnchor: faceAnchor)

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

            // Conclui as verificações principais
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
            self.lastMeasuredDistance = 0
            self.pupilCenters = nil

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
            self.lastMeasuredDistance = 0
            self.pupilCenters = nil

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

    /// Atualiza o sensor ativo baseado no estado atual do `CameraManager`.
    /// - Parameter manager: Instância utilizada como fonte da configuração atual.
    func updateActiveSensor(using manager: CameraManager) {
        // Captura os estados atuais do hardware no momento da chamada.
        let prefersFrontSensor = manager.cameraPosition == .front
        let hasTrueDepthSupport = manager.hasTrueDepth
        let hasLiDARSupport = manager.hasLiDAR
        let usesARSession = manager.isUsingARSession

        // Resolve o sensor mais apropriado com base na disponibilidade do hardware.
        let resolvedSensor: SensorType

        if usesARSession {
            if prefersFrontSensor, hasTrueDepthSupport {
                resolvedSensor = .trueDepth
            } else if !prefersFrontSensor, hasLiDARSupport {
                resolvedSensor = .liDAR
            } else if hasTrueDepthSupport {
                resolvedSensor = .trueDepth
            } else if hasLiDARSupport {
                resolvedSensor = .liDAR
            } else {
                resolvedSensor = .none
            }
        } else if prefersFrontSensor, hasTrueDepthSupport {
            resolvedSensor = .trueDepth
        } else if !prefersFrontSensor, hasLiDARSupport {
            resolvedSensor = .liDAR
        } else if hasTrueDepthSupport {
            resolvedSensor = .trueDepth
        } else if hasLiDARSupport {
            resolvedSensor = .liDAR
        } else {
            resolvedSensor = .none
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let capabilitiesChanged = self.hasTrueDepth != hasTrueDepthSupport ||
                                      self.hasLiDAR != hasLiDARSupport

            // Publica as capacidades vigentes sempre na thread principal.
            self.hasTrueDepth = hasTrueDepthSupport
            self.hasLiDAR = hasLiDARSupport

            guard self.activeSensor != resolvedSensor else {
                if capabilitiesChanged {
                    self.updateVerificationStatus(throttled: false)
                }
                return
            }

            self.activeSensor = resolvedSensor
            self.clearSensorDependentState()
        }
    }

    /// Permite resetar todas as verificações externamente
    func reset() {
        resetAllVerifications()
        updateVerificationStatus(throttled: true)
    }

    /// Define a ordem preferencial de sensores, priorizando o ativo.
    /// - Parameters:
    ///   - requireFaceAnchor: Indica se TrueDepth depende de um `ARFaceAnchor` válido.
    ///   - faceAnchorAvailable: Informa se o anchor está disponível neste frame.
    /// - Returns: Sequência ordenada de sensores válidos.
    func preferredSensors(requireFaceAnchor: Bool = false, faceAnchorAvailable: Bool = true) -> [SensorType] {
        var orderedSensors: [SensorType] = []

        @discardableResult
        func addIfAvailable(_ sensor: SensorType) -> Bool {
            switch sensor {
            case .trueDepth:
                guard hasTrueDepth else { return false }
                if requireFaceAnchor && !faceAnchorAvailable { return false }
            case .liDAR:
                guard hasLiDAR else { return false }
            case .none:
                return false
            }

            if !orderedSensors.contains(sensor) {
                orderedSensors.append(sensor)
            }
            return true
        }

        let activeAdded = addIfAvailable(activeSensor)

        if !activeAdded {
            if activeSensor != .trueDepth {
                _ = addIfAvailable(.trueDepth)
            }
            if activeSensor != .liDAR {
                _ = addIfAvailable(.liDAR)
            }
        }

        if orderedSensors.isEmpty {
            _ = addIfAvailable(.trueDepth)
            _ = addIfAvailable(.liDAR)
        }

        return orderedSensors
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
        let publishWork = { [self] in
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

            currentStep = .completed

            // Atualiza a propriedade publicada
            verifications = updated
        }

        if Thread.isMainThread {
            publishWork()
        } else {
            DispatchQueue.main.async(execute: publishWork)
        }
    }

    /// Limpa estados dependentes do sensor ao alternar entre TrueDepth e LiDAR.
    private func clearSensorDependentState() {
        resetAllVerifications()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.alignmentData = [:]
            self.facePosition = [:]
            self.currentStep = .faceDetection
            self.updateVerificationStatus(throttled: false)
        }
    }
}


extension VerificationManager: @unchecked Sendable {}
