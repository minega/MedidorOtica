//
//  VerificationManager.swift
//  MedidorOticaApp
//
//  Gerenciador central das verificacoes de medicao optica.
//

import Foundation
import AVFoundation
import ARKit
import Combine

/// Gerencia todas as verificacoes de medicao optica.
final class VerificationManager: ObservableObject {
    static let shared = VerificationManager()

    // MARK: - Publicacao
    @Published var verifications: [Verification] = []
    @Published var currentStep: VerificationStep = .idle
    @Published var faceDetected = false
    @Published var distanceCorrect = false
    @Published var faceAligned = false
    @Published var headAligned = false
    @Published var lastMeasuredDistance: Float = 0.0
    @Published var projectedFaceTooSmall = false
    @Published var projectedFaceWidthRatio: Float = 0.0
    @Published var projectedFaceHeightRatio: Float = 0.0
    @Published var hasTrueDepth = false
    @Published var hasLiDAR = false
    @Published var alignmentData: [String: Float] = [:]
    @Published var facePosition: [String: Float] = [:]
    @Published private(set) var activeSensor: SensorType = .none
    @Published private(set) var latestEvaluation: VerificationFrameEvaluation = .empty

    /// Callback disparado sempre que uma nova avaliacao consistente e aplicada.
    var evaluationHandler: ((VerificationFrameEvaluation) -> Void)?

    // MARK: - Sensor
    /// Representa o sensor ativo para as verificacoes AR.
    enum SensorType {
        case none
        case trueDepth
        case liDAR
    }

    // MARK: - Configuracao
    private var lastPublishTime = Date.distantPast
    private let publishInterval: TimeInterval = 1.0 / 15.0
    private let processingQueue = DispatchQueue(label: "com.oticaManzolli.verification.queue",
                                                qos: .userInitiated)
    private let processingGateQueue = DispatchQueue(label: "com.oticaManzolli.verification.gate")
    private var isProcessingFrame = false
    private var trueDepthGateOpen = false
    private var lastFrameTime = Date.distantPast
    private let frameInterval: TimeInterval = 1.0 / 15.0

    // MARK: - Distancia
    var minDistance: Float { DistanceLimits.minCm }
    var maxDistance: Float { DistanceLimits.maxCm }

    // MARK: - Inicializacao
    private init() {
        setupVerifications()
    }

    // MARK: - Estado composto
    /// Verifica se todas as verificacoes obrigatorias estao corretas.
    var allVerificationsChecked: Bool {
        guard activeSensor != .trueDepth || trueDepthGateOpen else { return false }
        return faceDetected && distanceCorrect && faceAligned && headAligned
    }

    // MARK: - Processamento de frame
    /// Processa um `ARFrame` realizando todas as verificacoes sequenciais.
    func processARFrame(_ frame: ARFrame) {
        guard canProcessCurrentSensorFrame() else { return }
        guard reserveProcessingSlot(at: Date()) else { return }

        if case .limited = frame.camera.trackingState {
            print("Aviso: rastreamento limitado - resultados podem ser imprecisos")
        }

        processingQueue.async { [weak self] in
            guard let self else { return }
            defer { self.releaseProcessingSlot() }

            let evaluation = self.makeEvaluation(from: frame)
            DispatchQueue.main.async { [weak self] in
                self?.apply(evaluation: evaluation)
            }
        }
    }

    /// Permite resetar todas as verificacoes externamente.
    func reset() {
        let work = { [self] in
            resetAllVerifications()
            latestEvaluation = .empty
            updateVerificationStatus(throttled: false)
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// Metodo publico para atualizar as verificacoes a partir de extensoes.
    func updateAllVerifications() {
        updateVerificationStatus(throttled: true)
    }

    /// Reavalia um frame especifico de forma sincrona para validar a captura final.
    func evaluationForCapture(_ frame: ARFrame) -> VerificationFrameEvaluation {
        guard canProcessCurrentSensorFrame() else { return .empty }
        return makeEvaluation(from: frame)
    }

    /// Abre ou fecha o gate do TrueDepth antes da publicacao das verificacoes.
    func setTrueDepthGate(isOpen: Bool) {
        let shouldReset = processingGateQueue.sync {
            guard trueDepthGateOpen != isOpen else { return false }
            trueDepthGateOpen = isOpen
            return !isOpen
        }

        guard shouldReset else { return }
        reset()
    }

    // MARK: - Gerenciamento de sensores
    /// Atualiza o sensor ativo baseado no estado atual do `CameraManager`.
    func updateActiveSensor(using manager: CameraManager) {
        if Thread.isMainThread {
            applyActiveSensor(using: manager)
        } else {
            DispatchQueue.main.async { [weak self, weak manager] in
                guard let self, let manager else { return }
                self.applyActiveSensor(using: manager)
            }
        }
    }

    /// Define a ordem preferencial de sensores, priorizando o ativo.
    func preferredSensors(requireFaceAnchor: Bool = false,
                          faceAnchorAvailable: Bool = true) -> [SensorType] {
        var orderedSensors: [SensorType] = []

        @discardableResult
        func addIfAvailable(_ sensor: SensorType) -> Bool {
            switch sensor {
            case .trueDepth:
                guard hasTrueDepth else { return false }
                guard !requireFaceAnchor || faceAnchorAvailable else { return false }
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
            if activeSensor != .trueDepth { _ = addIfAvailable(.trueDepth) }
            if activeSensor != .liDAR { _ = addIfAvailable(.liDAR) }
        }

        if orderedSensors.isEmpty {
            _ = addIfAvailable(.trueDepth)
            _ = addIfAvailable(.liDAR)
        }

        return orderedSensors
    }

    // MARK: - Atualizacao do menu
    /// Atualiza o status das verificacoes conforme os estados atuais.
    func updateVerificationStatus(throttled: Bool = false) {
        let publishWork = { [self] in
            if throttled {
                let now = Date()
                guard now.timeIntervalSince(lastPublishTime) >= publishInterval else { return }
                lastPublishTime = now
            }

            var updated = verifications
            mark(.faceDetection, as: faceDetected, in: &updated)
            guard faceDetected else {
                currentStep = .faceDetection
                markAll(after: .faceDetection, as: false, in: &updated)
                verifications = updated
                return
            }

            mark(.distance, as: distanceCorrect, in: &updated)
            guard distanceCorrect else {
                currentStep = .distance
                markAll(after: .distance, as: false, in: &updated)
                verifications = updated
                return
            }

            mark(.centering, as: faceAligned, in: &updated)
            guard faceAligned else {
                currentStep = .centering
                markAll(after: .centering, as: false, in: &updated)
                verifications = updated
                return
            }

            mark(.headAlignment, as: headAligned, in: &updated)
            guard headAligned else {
                currentStep = .headAlignment
                verifications = updated
                return
            }

            currentStep = .completed
            verifications = updated
        }

        if Thread.isMainThread {
            publishWork()
        } else {
            DispatchQueue.main.async(execute: publishWork)
        }
    }

    // MARK: - Inicializacao das verificacoes
    private func setupVerifications() {
        verifications = [
            Verification(id: 1, type: .faceDetection, isChecked: false),
            Verification(id: 2, type: .distance, isChecked: false),
            Verification(id: 3, type: .centering, isChecked: false),
            Verification(id: 4, type: .headAlignment, isChecked: false)
        ]
    }

    // MARK: - Avaliacao por frame
    private func makeEvaluation(from frame: ARFrame) -> VerificationFrameEvaluation {
        let trackingIsNormal = frame.camera.isTrackingNormal
        let faceAnchor = frame.anchors.compactMap { $0 as? ARFaceAnchor }.first
        let hasTrackedFaceAnchor = faceAnchor?.isTracked == true

        let faceDetected = checkFaceDetection(using: frame)
        guard faceDetected else {
            return VerificationFrameEvaluation(timestamp: frame.timestamp,
                                               trackingIsNormal: trackingIsNormal,
                                               hasTrackedFaceAnchor: hasTrackedFaceAnchor,
                                               faceDetected: false,
                                               distanceCorrect: false,
                                               faceAligned: false,
                                               headAligned: false)
        }

        let distanceCorrect = checkDistance(using: frame, faceAnchor: faceAnchor)
        guard distanceCorrect else {
            return VerificationFrameEvaluation(timestamp: frame.timestamp,
                                               trackingIsNormal: trackingIsNormal,
                                               hasTrackedFaceAnchor: hasTrackedFaceAnchor,
                                               faceDetected: true,
                                               distanceCorrect: false,
                                               faceAligned: false,
                                               headAligned: false)
        }

        let faceAligned = checkFaceCentering(using: frame, faceAnchor: faceAnchor)
        guard faceAligned else {
            return VerificationFrameEvaluation(timestamp: frame.timestamp,
                                               trackingIsNormal: trackingIsNormal,
                                               hasTrackedFaceAnchor: hasTrackedFaceAnchor,
                                               faceDetected: true,
                                               distanceCorrect: true,
                                               faceAligned: false,
                                               headAligned: false)
        }

        let headAligned = checkHeadAlignment(using: frame, faceAnchor: faceAnchor)
        return VerificationFrameEvaluation(timestamp: frame.timestamp,
                                           trackingIsNormal: trackingIsNormal,
                                           hasTrackedFaceAnchor: hasTrackedFaceAnchor,
                                           faceDetected: true,
                                           distanceCorrect: true,
                                           faceAligned: true,
                                           headAligned: headAligned)
    }

    private func apply(evaluation: VerificationFrameEvaluation) {
        faceDetected = evaluation.faceDetected
        distanceCorrect = evaluation.distanceCorrect
        faceAligned = evaluation.faceAligned
        headAligned = evaluation.headAligned
        latestEvaluation = evaluation

        if !evaluation.faceDetected {
            lastMeasuredDistance = 0
            projectedFaceTooSmall = false
            projectedFaceWidthRatio = 0
            projectedFaceHeightRatio = 0
            alignmentData = [:]
            facePosition = [:]
        } else if !evaluation.faceAligned {
            alignmentData = [:]
        }

        updateVerificationStatus(throttled: true)
        evaluationHandler?(evaluation)
    }

    // MARK: - Gate de processamento
    private func reserveProcessingSlot(at now: Date) -> Bool {
        processingGateQueue.sync {
            guard !isProcessingFrame else { return false }
            guard now.timeIntervalSince(lastFrameTime) >= frameInterval else { return false }
            isProcessingFrame = true
            lastFrameTime = now
            return true
        }
    }

    private func releaseProcessingSlot() {
        processingGateQueue.async { [weak self] in
            self?.isProcessingFrame = false
        }
    }

    private func canProcessCurrentSensorFrame() -> Bool {
        processingGateQueue.sync {
            activeSensor != .trueDepth || trueDepthGateOpen
        }
    }

    // MARK: - Estado derivado
    private func resetAllVerifications() {
        faceDetected = false
        distanceCorrect = false
        faceAligned = false
        headAligned = false
        lastMeasuredDistance = 0
        projectedFaceTooSmall = false
        projectedFaceWidthRatio = 0
        projectedFaceHeightRatio = 0
        alignmentData = [:]
        facePosition = [:]

        var updated = verifications
        for index in updated.indices {
            updated[index].isChecked = false
        }
        verifications = updated
    }

    private func applyActiveSensor(using manager: CameraManager) {
        let prefersFrontSensor = manager.cameraPosition == .front
        let hasTrueDepthSupport = manager.hasTrueDepth
        let hasLiDARSupport = manager.hasLiDAR
        let usesARSession = manager.isUsingARSession
        let resolvedSensor = resolveActiveSensor(prefersFrontSensor: prefersFrontSensor,
                                                 hasTrueDepthSupport: hasTrueDepthSupport,
                                                 hasLiDARSupport: hasLiDARSupport,
                                                 usesARSession: usesARSession)

        let capabilitiesChanged = hasTrueDepth != hasTrueDepthSupport ||
                                  hasLiDAR != hasLiDARSupport

        hasTrueDepth = hasTrueDepthSupport
        hasLiDAR = hasLiDARSupport

        guard activeSensor != resolvedSensor else {
            if capabilitiesChanged {
                updateVerificationStatus(throttled: false)
            }
            return
        }

        activeSensor = resolvedSensor
        clearSensorDependentState()
    }

    private func resolveActiveSensor(prefersFrontSensor: Bool,
                                     hasTrueDepthSupport: Bool,
                                     hasLiDARSupport: Bool,
                                     usesARSession: Bool) -> SensorType {
        if usesARSession {
            if prefersFrontSensor, hasTrueDepthSupport { return .trueDepth }
            if !prefersFrontSensor, hasLiDARSupport { return .liDAR }
        }

        if hasTrueDepthSupport { return .trueDepth }
        if hasLiDARSupport { return .liDAR }
        return .none
    }

    private func clearSensorDependentState() {
        processingGateQueue.sync {
            trueDepthGateOpen = false
        }
        resetAllVerifications()
        currentStep = .faceDetection
        updateVerificationStatus(throttled: false)
    }

    private func mark(_ type: VerificationType,
                      as isChecked: Bool,
                      in verifications: inout [Verification]) {
        guard let index = verifications.firstIndex(where: { $0.type == type }) else { return }
        verifications[index].isChecked = isChecked
    }

    private func markAll(after type: VerificationType,
                         as isChecked: Bool,
                         in verifications: inout [Verification]) {
        guard let typeIndex = verifications.firstIndex(where: { $0.type == type }) else { return }

        for index in verifications.indices where index > typeIndex {
            verifications[index].isChecked = isChecked
        }
    }
}

// MARK: - Concurrency
/// As leituras e publicacoes sao serializadas internamente pelas filas do manager.
extension VerificationManager: @unchecked Sendable {}

private extension ARCamera {
    /// Facilita a leitura do estado normal de rastreamento.
    var isTrackingNormal: Bool {
        if case .normal = trackingState {
            return true
        }
        return false
    }
}
