//
//  CameraManager+ControleSessao.swift
//  MedidorOticaApp
//
//  Controle do ciclo de vida da sessao de medicao.
//

import AVFoundation
import ARKit

extension CameraManager {
    // MARK: - Sessao de medicao
    /// Inicia a sessao principal de medicao no sensor informado.
    func startMeasurementSession(cameraType: CameraType,
                                 rearDepthMode: RearDepthMode = .liDAR,
                                 completion: @escaping (Bool) -> Void) {
        switch cameraType {
        case .front:
            startTrueDepthMeasurementSession(completion: completion)
        case .back:
            switch rearDepthMode {
            case .liDAR:
                startRearLiDARMeasurementSession(completion: completion)
            case .estimatedDepth:
                startRearDepthFallbackMeasurementSession(completion: completion)
            }
        }
    }

    /// Inicia a sessao principal de medicao usando TrueDepth.
    func startMeasurementSession(completion: @escaping (Bool) -> Void) {
        startMeasurementSession(cameraType: .front, completion: completion)
    }

    /// Inicia a sessao principal de medicao usando TrueDepth.
    private func startTrueDepthMeasurementSession(completion: @escaping (Bool) -> Void) {
        guard canStartTrueDepthMeasurement() else {
            completion(false)
            return
        }

        stop()
        beginPreparingCapture()

        let newSession = ARSession()
        newSession.delegate = self

        arSession = newSession
        cameraPosition = .front
        isUsingARSession = true
        isUsingRearDepthFallbackSession = false
        isSessionRunning = true
        clearError()
        prepareTrueDepthBootstrap(resetRecoveryAttempt: true)

        let configuration = createMeasurementConfiguration()
        newSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        VerificationManager.shared.updateActiveSensor(using: self)
        updateLensMonitoring(for: .front)
        completion(true)
    }

    /// Inicia a sessao traseira com LiDAR para o motor proprio de medicao.
    private func startRearLiDARMeasurementSession(completion: @escaping (Bool) -> Void) {
        guard canStartRearLiDARMeasurement() else {
            completion(false)
            return
        }

        stop()
        beginPreparingCapture()

        let newSession = ARSession()
        newSession.delegate = self

        arSession = newSession
        cameraPosition = .back
        isUsingARSession = true
        isUsingRearDepthFallbackSession = false
        isSessionRunning = true
        clearError()

        let configuration = createRearLiDARMeasurementConfiguration()
        newSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        VerificationManager.shared.updateActiveSensor(using: self)
        updateLensMonitoring(for: .back)
        completion(true)
    }

    /// Inicia a sessao traseira separada com AVDepthData, sem LiDAR.
    private func startRearDepthFallbackMeasurementSession(completion: @escaping (Bool) -> Void) {
        guard canStartRearDepthFallbackMeasurement() else {
            completion(false)
            return
        }

        stop()
        beginPreparingCapture()

        sessionQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            self.cleanupSession()
            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(.high) {
                self.session.sessionPreset = .high
            }

            guard let device = RearDepthFallbackMeasurementEngine.supportedDepthDevice(),
                  self.configureRearDepthFallbackInput(device: device),
                  self.rearDepthCaptureCoordinator.configure(session: self.session,
                                                             device: device,
                                                             frameHandler: { [weak self] frame in
                                                                 self?.handleRearDepthFallbackFrame(frame)
                                                             }) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.publishError(.cameraUnavailable)
                    completion(false)
                }
                return
            }

            self.session.commitConfiguration()
            self.session.startRunning()

            DispatchQueue.main.async {
                let started = self.session.isRunning
                self.cameraPosition = .back
                self.isUsingARSession = false
                self.isUsingRearDepthFallbackSession = started
                self.isSessionRunning = started
                self.clearError()
                VerificationManager.shared.updateActiveSensor(using: self)
                self.updateLensMonitoring(for: .back)
                completion(started)
            }
        }
    }

    /// Cria a configuracao principal da sessao TrueDepth.
    func createMeasurementConfiguration() -> ARFaceTrackingConfiguration {
        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1
        if #available(iOS 13.0, *) {
            configuration.isLightEstimationEnabled = true
        }
        return configuration
    }

    /// Cria a configuracao traseira com profundidade de cena habilitada.
    func createRearLiDARMeasurementConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        if #available(iOS 14.0, *),
           ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        } else if #available(iOS 13.4, *) {
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
        }
        if #available(iOS 13.0, *) {
            configuration.environmentTexturing = .automatic
        }
        return configuration
    }

    /// Cria uma nova `ARSession` para compatibilidade com chamadas legadas.
    func createARSession(for cameraType: CameraType) -> ARSession {
        let session = ARSession()
        session.delegate = self
        return session
    }

    /// Encerra a sessao ativa e limpa o pipeline associado.
    func stop() {
        if isUsingARSession {
            stopARSession()
        } else if isUsingRearDepthFallbackSession {
            stopRearDepthFallbackSession()
        } else if isSessionRunning {
            stopCaptureSession()
        }

        isSessionRunning = false
        isUsingARSession = false
        isUsingRearDepthFallbackSession = false
        resetCapturePipeline(resetCalibration: true)
        prepareTrueDepthBootstrap(resetRecoveryAttempt: true)
        setCaptureState(.idle, hint: "Camera parada.", progress: 0)
        VerificationManager.shared.reset()
        updateLensMonitoring(for: cameraPosition)
    }

    /// Reinicia a sessao atual apos interrupcoes ou falhas do ARKit.
    func restartSession(recoveryReason: TrueDepthBlockReason? = nil) {
        if isUsingRearDepthFallbackSession {
            guard hasRearDepthFallback else {
                stop()
                return
            }

            startMeasurementSession(cameraType: .back, rearDepthMode: .estimatedDepth) { _ in }
            return
        }

        if cameraPosition == .back {
            guard hasLiDAR else {
                stop()
                return
            }

            guard let arSession else {
                startMeasurementSession(cameraType: .back) { _ in }
                return
            }

            beginPreparingCapture()
            arSession.run(createRearLiDARMeasurementConfiguration(),
                          options: [.resetTracking, .removeExistingAnchors])
            isUsingARSession = true
            isSessionRunning = true
            return
        }

        guard cameraPosition == .front, hasTrueDepth else {
            stop()
            return
        }

        guard let arSession else {
            startMeasurementSession(cameraType: .front) { _ in }
            return
        }

        beginPreparingCapture()
        prepareTrueDepthBootstrap(resetRecoveryAttempt: recoveryReason == nil,
                                  recoveryReason: recoveryReason)
        arSession.run(createMeasurementConfiguration(),
                      options: [.resetTracking, .removeExistingAnchors])
        isUsingARSession = true
        isSessionRunning = true
    }

    // MARK: - Helpers
    private func canStartTrueDepthMeasurement() -> Bool {
        guard isFrontCameraEnabled else {
            notifyUnsupportedDevice(reason: "A camera frontal foi desabilitada manualmente.")
            return false
        }

        guard hardwareHasTrueDepth, ARFaceTrackingConfiguration.isSupported else {
            notifyUnsupportedDevice(reason: "Este dispositivo nao possui sensor TrueDepth compativel.")
            return false
        }

        return true
    }

    private func canStartRearLiDARMeasurement() -> Bool {
        guard hardwareHasLiDAR, RearLiDARMeasurementEngine.isSupported else {
            notifyUnsupportedDevice(reason: "Este dispositivo nao possui LiDAR traseiro compativel.",
                                    sensor: "LiDAR")
            return false
        }

        return true
    }

    private func canStartRearDepthFallbackMeasurement() -> Bool {
        guard hasRearDepthFallback,
              RearDepthFallbackMeasurementEngine.isSupported else {
            notifyUnsupportedDevice(reason: "Este dispositivo nao fornece profundidade traseira por camera dupla.",
                                    sensor: "Depth")
            return false
        }

        return true
    }

    private func notifyUnsupportedDevice(reason: String,
                                        sensor: String = "TrueDepth") {
        publishError(.cameraUnavailable)
        NotificationCenter.default.post(name: NSNotification.Name("DeviceNotCompatible"),
                                        object: nil,
                                        userInfo: ["reason": reason,
                                                   "sensor": sensor])
    }

    private func stopARSession() {
        arSession?.pause()
        arSession?.delegate = nil
        arSession = nil
    }

    private func stopRearDepthFallbackSession() {
        rearDepthCaptureCoordinator.reset()
        if session.isRunning {
            session.stopRunning()
        }
        cleanupSession()
        latestRearDepthFrame = nil
    }

    private func stopCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            self.cleanupSession()
        }
    }

    func cleanupSession() {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
        videoDeviceInput = nil
    }

    private func configureRearDepthFallbackInput(device: AVCaptureDevice) -> Bool {
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                publishError(.cannotAddInput)
                return false
            }

            session.addInput(input)
            videoDeviceInput = input
            return true
        } catch {
            publishError(.createCaptureInput(error))
            return false
        }
    }

    private func handleRearDepthFallbackFrame(_ frame: RearDepthFrame) {
        latestRearDepthFrame = frame
        lastFrameTimestamp = frame.timestamp
        VerificationManager.shared.processRearDepthFrame(frame)
    }
}
