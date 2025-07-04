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

    /// Cria e configura uma nova `ARSession` de acordo com o `CameraType`.
    func createARSession(for cameraType: CameraType) -> ARSession {
        arSession?.pause()
        let newSession = ARSession()
        arSession = newSession
        arSession?.delegate = self

        cameraPosition = cameraType == .front ? .front : .back

        let configuration: ARConfiguration
        var configurationError: String? = nil

        do {
            switch cameraType {
            case .front:
                guard ARFaceTrackingConfiguration.isSupported else {
                    configurationError = "Este dispositivo não suporta rastreamento facial (TrueDepth)."
                    throw NSError(domain: "ARError", code: 1001, userInfo: [NSLocalizedDescriptionKey: configurationError ?? "Erro desconhecido"])
                }
                let faceConfig = ARFaceTrackingConfiguration()
                faceConfig.maximumNumberOfTrackedFaces = 1
                if #available(iOS 13.0, *) { faceConfig.isLightEstimationEnabled = true }
                configuration = faceConfig
                print("Configurando sessão AR para rastreamento facial")
            case .back:
                guard ARWorldTrackingConfiguration.isSupported else {
                    configurationError = "Este dispositivo não suporta rastreamento de mundo."
                    throw NSError(domain: "ARError", code: 1002, userInfo: [NSLocalizedDescriptionKey: configurationError ?? "Erro desconhecido"])
                }
                let worldConfig = ARWorldTrackingConfiguration()
                if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                    worldConfig.sceneReconstruction = .mesh
                    worldConfig.frameSemantics.insert(.sceneDepth)
                    print("Configurando sessão AR com LiDAR para profundidade")
                }
                configuration = worldConfig
            }

            newSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            isUsingARSession = true
            print("Sessão AR configurada com sucesso para \(cameraType)")
        } catch {
            let errorMessage = configurationError ?? "Falha ao configurar a sessão AR: \(error.localizedDescription)"
            print(errorMessage)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("ARConfigurationFailed"),
                                                object: nil,
                                                userInfo: ["error": errorMessage])
            }
        }

        return newSession
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
        isUsingARSession = false

        VerificationManager.shared.reset()
    }

    private func stopARSession() {
        arSession?.pause()
        arSession?.delegate = nil
        arSession = nil
        print("Sessão AR parada e recursos liberados")
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
