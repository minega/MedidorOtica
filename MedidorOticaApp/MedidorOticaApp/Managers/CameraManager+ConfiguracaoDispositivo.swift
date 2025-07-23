//
//  CameraManager+ConfiguracaoDispositivo.swift
//  MedidorOticaApp
//
//  Extensão responsável por configurar a sessão de captura e lidar com
//  ajustes de hardware, como alternar câmeras e controlar o flash.
//

import AVFoundation
import ARKit

extension CameraManager {
    // MARK: - Configuração do Dispositivo
    /// Prepara a `AVCaptureSession` com os inputs e outputs necessários.
    func setupSession() {
        print("Configurando sessão da câmera...")

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.stopSessionIfRunning()
            self.printAvailableDevices()

            self.session.beginConfiguration()
            self.cleanupSession()

            if self.session.canSetSessionPreset(.high) {
                self.session.sessionPreset = .high
            }

            self.configureVideoInput()

            guard self.configurePhotoOutput() else {
                self.session.commitConfiguration()
                return
            }

            self.session.commitConfiguration()
            print("Configuração da sessão finalizada com sucesso")

            self.startSession()
        }
    }

    /// Alterna entre as câmeras frontal e traseira.
    func switchCamera() {
        isUsingARSession ? switchARPosition() : switchAVPosition()
    }

    /// Liga ou desliga o flash, caso disponível.
    func toggleFlash() {
        guard let device = videoDeviceInput?.device else { return }

        guard device.hasTorch, device.isTorchAvailable else {
            publishError(.deviceConfigurationFailed)
            return
        }

        do {
            try device.lockForConfiguration()

            isFlashOn.toggle()

            if device.isTorchModeSupported(isFlashOn ? .on : .off) {
                device.torchMode = isFlashOn ? .on : .off
            } else {
                isFlashOn = (device.torchMode == .on)
                publishError(.deviceConfigurationFailed)
            }

            device.unlockForConfiguration()
        } catch {
            publishError(.deviceConfigurationFailed)
        }
    }

    /// Configura a posição inicial da câmera e, opcionalmente, uma `ARSession`.
    func setup(position: AVCaptureDevice.Position, arSession: ARSession? = nil, completion: @escaping (Bool) -> Void) {
        cameraPosition = position
        self.arSession = arSession
        self.arSession?.delegate = self

        // Atualiza imediatamente o estado para evitar atraso na interface
        self.isUsingARSession = (arSession != nil)
        DispatchQueue.main.async {
            // Posta novamente na main para notificar observadores
            self.isUsingARSession = (arSession != nil)
        }

        isUsingARSession ? configureARSession(completion) : configureCaptureSession(completion)
    }

    private func configureARSession(_ completion: @escaping (Bool) -> Void) {
        print("Configurando com ARSession fornecida")
        completion(true)
    }

    private func configureCaptureSession(_ completion: @escaping (Bool) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.setupSession()
            DispatchQueue.main.async { completion(true) }
        }
    }

    // MARK: - Private Helpers
    private func stopSessionIfRunning() {
        if session.isRunning {
            session.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    private func printAvailableDevices() {
        print("Dispositivos de câmera disponíveis:")
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .unspecified
        )
        for device in discoverySession.devices {
            print("- \(device.localizedName) (posição: \(device.position == .front ? "frontal" : "traseira"))")
        }
    }

    private func configurePhotoOutput() -> Bool {
        guard session.canAddOutput(videoOutput) else {
            print("Erro: Não foi possível adicionar output de foto")
            publishError(.cannotAddOutput)
            return false
        }

        session.addOutput(videoOutput)
        if #available(iOS 16, *) {
            videoOutput.maxPhotoDimensions = CMVideoDimensions(width: 0, height: 0)
        } else {
            videoOutput.isHighResolutionCaptureEnabled = true
        }
        print("Output de foto adicionado com sucesso")

        if let connection = videoOutput.connection(with: .video) {
            connection.setPortraitOrientation()
            print("Orientação de vídeo configurada para portrait")
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = (cameraPosition == .front)
                print("Espelhamento de vídeo configurado: \(cameraPosition == .front)")
            }
        }

        return true
    }

    private func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            self.session.startRunning()

            DispatchQueue.main.async {
                self.isSessionRunning = true
            }

            print("Sessão da câmera iniciada após configuração")
        }
    }

    private func cameraDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: position
        )

        return discoverySession.devices.first
    }

    private func configureVideoInput() {
        guard let videoDevice = cameraDevice(for: cameraPosition) else {
            publishError(.cameraUnavailable)
            return
        }

        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)

            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput

                if let connection = videoOutput.connection(with: .video) {
                    connection.setPortraitOrientation()
                    if connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = (cameraPosition == .front)
                    }
                }
            } else {
                publishError(.cannotAddInput)
            }
        } catch {
            publishError(.createCaptureInput(error))
        }
    }

    private func switchARPosition() {
        cameraPosition = (cameraPosition == .front) ? .back : .front
        print("Nova posição da câmera: \(cameraPosition == .front ? "frontal" : "traseira")")

        if let arSession = arSession {
            let configuration = createARConfiguration()
            arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
    }

    private func switchAVPosition() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.session.beginConfiguration()

            if let currentInput = self.videoDeviceInput {
                self.session.removeInput(currentInput)
            }

            self.cameraPosition = (self.cameraPosition == .front) ? .back : .front

            self.configureVideoInput()

            self.session.commitConfiguration()

            print("Nova posição da câmera: \(self.cameraPosition == .front ? "frontal" : "traseira")")
        }
    }
}
