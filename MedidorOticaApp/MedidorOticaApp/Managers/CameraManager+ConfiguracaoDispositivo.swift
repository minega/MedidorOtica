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
    /// - Parameter completion: Callback informando se a configuração foi concluída com sucesso.
    func setupSession(completion: @escaping (Bool) -> Void) {
        print("Configurando sessão da câmera...")

        sessionQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            self.stopSessionIfRunning()
            self.printAvailableDevices()
            self.cleanupSession()

            var configurationSucceeded = true

            self.session.beginConfiguration()

            if self.session.canSetSessionPreset(.high) {
                self.session.sessionPreset = .high
            }

            if !self.configureVideoInput() {
                configurationSucceeded = false
            }

            if configurationSucceeded, !self.configurePhotoOutput() {
                configurationSucceeded = false
            }

            self.session.commitConfiguration()

            guard configurationSucceeded else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            print("Configuração da sessão finalizada com sucesso")
            self.startSession(completion: completion)
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
            print("Flash indisponível para o dispositivo atual")
            if isFlashOn { isFlashOn = false }
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
        if position == .front && !isFrontCameraEnabled {
            print("Câmera frontal solicitada, porém desabilitada. Utilizando câmera traseira.")
            cameraPosition = .back
        } else {
            cameraPosition = position
        }
        self.arSession = arSession
        self.arSession?.delegate = self

        // Atualiza imediatamente o estado para evitar atraso na interface
        self.isUsingARSession = (arSession != nil)
        DispatchQueue.main.async {
            // Posta novamente na main para notificar observadores
            self.isUsingARSession = (arSession != nil)
        }

        // Informa ao VerificationManager qual sensor foi selecionado
        VerificationManager.shared.updateActiveSensor(using: self)
        updateLensMonitoring(for: cameraPosition)

        isUsingARSession ? configureARSession(completion) : configureCaptureSession(completion)
    }

    private func configureARSession(_ completion: @escaping (Bool) -> Void) {
        print("Configurando com ARSession fornecida")
        completion(true)
    }

    private func configureCaptureSession(_ completion: @escaping (Bool) -> Void) {
        setupSession(completion: completion)
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

    private func startSession(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            self.session.startRunning()

            DispatchQueue.main.async {
                let started = self.session.isRunning
                self.isSessionRunning = started
                if started {
                    print("Sessão da câmera iniciada após configuração")
                } else {
                    print("Falha ao iniciar a sessão da câmera")
                }
                completion(started)
            }
        }
    }

    /// Retorna o dispositivo de captura para a posição indicada.
    /// - Parameters:
    ///   - position: Posição desejada (frontal ou traseira).
    ///   - ignoringFrontOverride: Define se o bloqueio manual da câmera frontal deve ser ignorado.
    func cameraDevice(for position: AVCaptureDevice.Position, ignoringFrontOverride: Bool = false) -> AVCaptureDevice? {
        if position == .front && !ignoringFrontOverride && !isFrontCameraEnabled {
            return nil
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: position
        )

        return discoverySession.devices.first
    }

    private func configureVideoInput() -> Bool {
        guard let videoDevice = cameraDevice(for: cameraPosition) else {
            publishError(.cameraUnavailable)
            return false
        }

        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)

            guard session.canAddInput(videoDeviceInput) else {
                publishError(.cannotAddInput)
                return false
            }

            session.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput

            if let connection = videoOutput.connection(with: .video) {
                connection.setPortraitOrientation()
                print("Orientação de vídeo configurada para portrait")
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = (cameraPosition == .front)
                    print("Espelhamento de vídeo configurado: \(cameraPosition == .front)")
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.updateLensMonitoring(for: self.cameraPosition)
            }

            return true
        } catch {
            publishError(.createCaptureInput(error))
            return false
        }
    }

    private func switchARPosition() {
        let newPosition: AVCaptureDevice.Position = (cameraPosition == .front) ? .back : .front

        if newPosition == .front && !isFrontCameraEnabled {
            print("Alternância ignorada: câmera frontal está desabilitada.")
            return
        }

        cameraPosition = newPosition
        print("Nova posição da câmera: \(cameraPosition == .front ? "frontal" : "traseira")")

        if let arSession = arSession {
            let configuration = createARConfiguration()
            arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }

        // Garante que o VerificationManager saiba qual sensor está ativo
        VerificationManager.shared.updateActiveSensor(using: self)
        updateLensMonitoring(for: cameraPosition)
    }

    private func switchAVPosition() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.session.beginConfiguration()

            let previousInput = self.videoDeviceInput
            if let currentInput = previousInput {
                self.session.removeInput(currentInput)
            }

            let previousPosition = self.cameraPosition
            self.cameraPosition = (self.cameraPosition == .front) ? .back : .front

            if self.cameraPosition == .front && !self.isFrontCameraEnabled {
                print("Alternância cancelada: câmera frontal está desabilitada.")
                self.cameraPosition = previousPosition
                if let previousInput, self.session.canAddInput(previousInput) {
                    self.session.addInput(previousInput)
                    self.videoDeviceInput = previousInput
                }
                self.session.commitConfiguration()
                return
            }

            let inputConfigured = self.configureVideoInput()

            if !inputConfigured {
                if let previousInput, self.session.canAddInput(previousInput) {
                    self.session.addInput(previousInput)
                    self.videoDeviceInput = previousInput
                }
                self.cameraPosition = previousPosition
            }

            self.session.commitConfiguration()

            if inputConfigured {
                print("Nova posição da câmera: \(self.cameraPosition == .front ? "frontal" : "traseira")")
            }

            // Sincroniza o sensor ativo após alternar a câmera de captura
            VerificationManager.shared.updateActiveSensor(using: self)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.updateLensMonitoring(for: self.cameraPosition)
            }
        }
    }
}
