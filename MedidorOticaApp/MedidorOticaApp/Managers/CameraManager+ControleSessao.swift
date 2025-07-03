//
//  CameraManager+ControleSessao.swift
//  MedidorOticaApp
//
//  Extensão dedicada ao controle do ciclo de vida da sessão da câmera ou
//  da ARSession utilizada pelo aplicativo.
//

import AVFoundation
import ARKit

extension CameraManager {
    // MARK: - Controle de Sessão
    /// Inicia a sessão de captura ou a sessão AR.
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

            arSession.delegate = self

            arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            self.isSessionRunning = true
            print("Sessão AR iniciada com sucesso")
        }
    }

    func createARConfiguration() -> ARConfiguration {
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
        return ARWorldTrackingConfiguration()
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

    /// Encerra a sessão de captura ou AR em execução.
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

    func cleanupSession() {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
        videoDeviceInput = nil
    }
}
