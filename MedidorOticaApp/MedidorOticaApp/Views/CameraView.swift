//
//  CameraView.swift
//  MedidorOticaApp
//
//  Tela de captura de imagem para medições de ótica.
//  Versão modularizada para melhor manutenção.
//

import SwiftUI
import AVFoundation
import UIKit
import ARKit

struct CameraView: View {
    // MARK: - Propriedades
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraManager = CameraManager.shared
    @StateObject private var verificationManager = VerificationManager.shared
    @EnvironmentObject private var historyManager: HistoryManager
    
    // Estados da interface
    @State private var isAutoCaptureEnabled = true
    @State private var countdownValue = 0
    @State private var countdownTimer: Timer?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var capturedImage: UIImage?
    @State private var isProcessing = false
    @State private var showFlash = false
    @State private var showingResultView = false
    @State private var showVerifications = true // Mostrar verificações por padrão
    @State private var cameraInitialized = false
    /// Define se o medidor de distância deve ser exibido.
    private let showDistanceOverlay = true
    /// Define se o indicador de status AR deve ser exibido.
    private let showARStatusIndicator = true


    // Observadores de notificações adicionados dinamicamente
    @State private var notificationObservers: [NSObjectProtocol] = []
    
    
    // Feedback tátil
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    // MARK: - Computadas
    // Verifica se todas as verificações estão corretas
    private var allVerificationsChecked: Bool {
        return verificationManager.allVerificationsChecked
    }
    
    // MARK: - View principal
    var body: some View {
        ZStack {
            // Preview da câmera ou AR
            Group {
                if cameraManager.isUsingARSession, let arSession = cameraManager.arSession {
                    ARCameraPreview(session: arSession, delegate: cameraManager)
                } else {
                    CameraPreview(session: cameraManager.session)
                }
            }
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                    print("CameraView apareceu - iniciando câmera")
                    // Inicia as verificações e a câmera
                    setupCamera()
                    
                    // Observador de erros da câmera
                    let camToken = NotificationCenter.default.addObserver(
                        forName: .cameraError,
                        object: nil,
                        queue: .main
                    ) { notification in
                        if let error = notification.userInfo?["error"] as? CameraError {
                            self.alertMessage = error.localizedDescription
                            self.showingAlert = true
                            self.isProcessing = false
                        }
                    }
                    notificationObservers.append(camToken)

                    // Observa falhas na configuração da sessão AR
                    let configToken = NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("ARConfigurationFailed"),
                        object: nil,
                        queue: .main
                    ) { notification in
                        if let message = notification.userInfo?["error"] as? String {
                            self.alertMessage = message
                        } else {
                            self.alertMessage = "Falha ao configurar ARSession."
                        }
                        self.cameraManager.stop()
                        self.showingAlert = true
                    }
                    notificationObservers.append(configToken)

                    // Observa erros de execução da sessão AR
                    let arToken = NotificationCenter.default.addObserver(
                        forName: .arSessionError,
                        object: nil,
                        queue: .main
                    ) { notification in
                        if let message = notification.userInfo?["message"] as? String {
                            self.alertMessage = message
                        } else {
                            self.alertMessage = "A sessão de AR apresentou um erro."
                        }
                        self.cameraManager.stop()
                        self.showingAlert = true
                    }
                    notificationObservers.append(arToken)
            }
            .onDisappear {
                print("CameraView desapareceu - parando câmera")
                // Para a câmera e limpa recursos
                cameraManager.stop()

                // Remove todos os observadores registrados
                notificationObservers.forEach {
                    NotificationCenter.default.removeObserver($0)
                }
                notificationObservers.removeAll()
            }

            if verificationManager.pupilCenters != nil {
                PupilOverlay(verificationManager: verificationManager,
                             cameraManager: cameraManager)
                    .edgesIgnoringSafeArea(.all)
            }

            // Overlay de flash ao tirar foto
            if showFlash {
                Color.white
                    .edgesIgnoringSafeArea(.all)
                    .opacity(0.7)
                    .animation(.easeOut(duration: 0.3), value: showFlash)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showFlash = false
                        }
                    }
            }
            
            // Oval centralizado com barra de progresso
            ProgressOval(verificationManager: verificationManager,
                         showDistance: showDistanceOverlay)

            if countdownValue > 0 {
                VStack(spacing: 16) {
                    Text("Olhe para a câmera")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("\(countdownValue)")
                        .font(.system(size: 72, weight: .bold))
                        .foregroundColor(.white)
                }
            }


            
            // Overlay de controles (usando um VStack para elementos de interface)
            VStack {
                // Barra superior com botões
                HStack {
                    // Botão de fechar
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }

                    if showARStatusIndicator {
                        ARStatusIndicator(cameraManager: cameraManager,
                                         verificationManager: verificationManager)
                    }

                    Spacer()

                    // Botão de captura automática
                    Button(action: {
                        isAutoCaptureEnabled.toggle()
                    }) {
                        Image(systemName: isAutoCaptureEnabled ? "timer.circle.fill" : "timer.circle")
                            .font(.title3)
                            .foregroundColor(isAutoCaptureEnabled ? .green : .white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }

                    // Botão de flash
                    Button(action: {
                        cameraManager.toggleFlash()
                    }) {
                        Image(systemName: cameraManager.isFlashOn ? "bolt.fill" : "bolt.slash")
                            .font(.title3)
                            .foregroundColor(cameraManager.isFlashOn ? .yellow : .white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    
                    // Botão para alternar câmera
                    Button(action: {
                        cameraManager.switchCamera()
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                }
                .padding()
                .background(Color.black.opacity(0.3))
                
                // Menu de verificações (canto direito)
                if showVerifications {
                    VerificationMenu(verificationManager: verificationManager)
                }
                
                // Instruções detalhadas usando o componente dedicado
                CameraInstructions(verificationManager: verificationManager)
                
                Spacer()
                
                // Botão de captura na parte inferior (em formato de pílula)
                Button(action: {
                    // Só permite captura se todas as verificações obrigatórias estiverem concluídas
                    if verificationManager.allVerificationsChecked {
                        capturePhoto()
                    } else {
                        // Feedback específico baseado na verificação que está falhando
                        if !verificationManager.faceDetected {
                            alertMessage = "Posicione seu rosto para ser detectado."
                        } else if !verificationManager.distanceCorrect {
                            if verificationManager.lastMeasuredDistance < verificationManager.minDistance {
                                alertMessage = "Aproxime-se da câmera."
                            } else {
                                alertMessage = "Afaste-se da câmera."
                            }
                        } else if !verificationManager.faceAligned {
                            alertMessage = "Centralize seu rosto no oval."
                        } else if !verificationManager.headAligned {
                            alertMessage = "Mantenha sua cabeça reta alinhada com a câmera."
                        }
                        showingAlert = true
                        notificationGenerator.notificationOccurred(.warning)
                    }
                }) {
                    ZStack {
                        Capsule()
                            .fill(allVerificationsChecked ?
                                  AnyShapeStyle(LinearGradient(
                                      gradient: Gradient(colors: [Color.blue, Color.purple]),
                                      startPoint: .leading,
                                      endPoint: .trailing
                                  )) : AnyShapeStyle(Color.gray))
                            .frame(width: 140, height: 50)
                            .shadow(color: .black.opacity(0.2), radius: 3)
                        
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                        } else {
                            Text("Capturar")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        // Alerta para mensagens de erro
        .alert(alertMessage, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        }
        // Navegação para a tela de resultados após captura
        .sheet(isPresented: $showingResultView) {
            if let image = capturedImage {
                MeasurementResultView(capturedImage: image)
                    .environmentObject(historyManager)
            }
        }
        .onChange(of: allVerificationsChecked) { checked in
            if checked && isAutoCaptureEnabled && countdownTimer == nil {
                startCountdown()
            }
        }
    }
    
    // MARK: - Métodos auxiliares
    
    // Configura a câmera e as verificações reais
    func setupCamera() {
        // Se a câmera já está inicializada, apenas a reinicia
        if cameraInitialized {
            print("Câmera já inicializada, reiniciando...")
            cameraManager.stop()
            cameraInitialized = false
            
            // Pequeno atraso para garantir que a câmera foi parada corretamente
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.setupCamera()
            }
            return
        }
        
        print("Iniciando configuração da câmera")
        
        // Verificamos primeiro as permissões da câmera - essa deve ser a primeira etapa
        checkCameraPermissions { permissionGranted in
            guard permissionGranted else {
                print("Permissão da câmera negada")
                return
            }
            
            print("Permissão da câmera concedida, continuando configuração")
            
            // Verifica os sensores disponíveis no dispositivo
            self.cameraManager.checkAvailableSensors()
            let capabilities = (hasTrueDepth: self.cameraManager.hasTrueDepth,
                                hasLiDAR: self.cameraManager.hasLiDAR)

            // Seleciona o tipo de câmera de acordo com os sensores disponíveis
            let cameraType: CameraType
            let position: AVCaptureDevice.Position

            if capabilities.hasTrueDepth {
                cameraType = .front
                position = .front
            } else if capabilities.hasLiDAR {
                cameraType = .back
                position = .back
            } else {
                // Nenhum sensor compatível encontrado
                DispatchQueue.main.async {
                    self.alertMessage = "Este dispositivo não possui sensores TrueDepth ou LiDAR necessários para as medições."
                    self.showingAlert = true
                }
                return
            }

            // Configura a AR Session
            let arSession = self.cameraManager.createARSession(for: cameraType)

            // Configura a câmera com o sensor disponível
            // A configuração real é feita dentro dessa chamada, não precisamos chamar setupSession() separadamente
            self.cameraManager.setup(position: position, arSession: arSession) { success in
                DispatchQueue.main.async {
                    if success {
                        print("Câmera configurada com sucesso, iniciando processamento")
                        self.cameraInitialized = true
                        self.configureCameraProcessing()
                    } else {
                        self.alertMessage = "Não foi possível acessar a câmera."
                        self.showingAlert = true
                    }
                }
            }
        }
        
        // Registra para notificações de compatibilidade do dispositivo
        NotificationCenter.default.addObserver(forName: NSNotification.Name("DeviceNotCompatible"),
                                               object: nil,
                                               queue: .main) { notification in
            if let reason = notification.userInfo?["reason"] as? String {
                self.alertMessage = "Dispositivo não compatível: \(reason)"
            } else if let sensor = notification.userInfo?["sensor"] as? String {
                self.alertMessage = "Dispositivo não possui o sensor \(sensor) necessário."
            } else {
                self.alertMessage = "Dispositivo não compatível com as medições."
            }
            self.showingAlert = true
        }
        
    }
    
    // Verifica as permissões da câmera
    private func checkCameraPermissions(completion: @escaping (Bool) -> Void) {
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch cameraAuthStatus {
        case .authorized:
            print("Permissão de câmera já concedida")
            completion(true)
        case .notDetermined:
            print("Solicitando permissão de câmera")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    print("Permissão de câmera concedida")
                    DispatchQueue.main.async {
                        completion(true)
                    }
                } else {
                    print("Permissão de câmera negada")
                    DispatchQueue.main.async {
                        showPermissionDeniedAlert()
                        completion(false)
                    }
                }
            }
        case .denied, .restricted:
            print("Permissão de câmera negada ou restrita")
            DispatchQueue.main.async {
                showPermissionDeniedAlert()
                completion(false)
            }
        @unknown default:
            // Lida com possíveis valores futuros do enum
            print("Status de autorização de câmera desconhecido: \(cameraAuthStatus)")
            DispatchQueue.main.async {
                showPermissionDeniedAlert()
                completion(false)
            }
        }
    }
    
    private func showPermissionDeniedAlert() {
        alertMessage = "O acesso à câmera é necessário para fazer medições. Por favor, ative a permissão nas configurações do dispositivo."
        showingAlert = true
    }
    
    private func handleCameraError(_ error: CameraError) {
        alertMessage = error.localizedDescription
        showingAlert = true
        isProcessing = false
    }
    
    func capturePhoto() {
        // Verifica se a captura está habilitada e pronta
        guard !isProcessing else {
            print("Processo de captura já em andamento, ignorando...")
            return
        }

        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownValue = 0
        
        // Verifica se todas as condições para captura foram atendidas
        guard allVerificationsChecked else {
            print("Nem todas as verificações foram completadas, ignorando...")
            notificationGenerator.notificationOccurred(.warning)
            alertMessage = "Ajuste a posição de acordo com as instruções antes de capturar."
            showingAlert = true
            return
        }
        
        // Verifica se a câmera está inicializada
        guard cameraInitialized else {
            print("Câmera não inicializada, tentando inicializar...")
            setupCamera() // Tenta inicializar a câmera
            
            // Notifica o usuário e evita continuar a captura
            notificationGenerator.notificationOccurred(.error)
            alertMessage = "Aguarde a inicialização da câmera e tente novamente."
            showingAlert = true
            return
        }
        
        // Feedback tátil ao usuário
        impactGenerator.impactOccurred()
        
        // Marca o início do processamento
        isProcessing = true
        showFlash = true
        
        // Tenta capturar a foto com tratamento de erro
        print("Iniciando captura de foto...")
        cameraManager.capturePhoto { image in
            // Certifica-se de processar na thread principal
            DispatchQueue.main.async {
                // Marca o fim do processamento
                isProcessing = false
                
                if let image = image {
                    print("Imagem capturada com sucesso, tamanho: \(image.size.width) x \(image.size.height)")
                    capturedImage = image
                    showingResultView = true
                } else {
                    print("Falha ao capturar imagem")
                    alertMessage = "Não foi possível capturar a imagem. Tente novamente."
                    showingAlert = true
                    notificationGenerator.notificationOccurred(.error)
                }
            }
        }
    }
    
    // Configura o processamento real dos frames da câmera
    func configureCameraProcessing() {
        // Processa cada ARFrame recebido da câmera
        cameraManager.outputDelegate = { frame in
            self.verificationManager.processARFrame(frame)
        }
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownValue = 5
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if countdownValue > 1 {
                countdownValue -= 1
            } else {
                timer.invalidate()
                countdownTimer = nil
                countdownValue = 0
                capturePhoto()
            }
        }
    }
}

// MARK: - Preview Provider
struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView()
            .environmentObject(HistoryManager.shared)
    }
}

// Os componentes foram movidos para:
// - CameraComponents.swift: CameraPreview, ProgressOval, EllipticalProgressBar, CameraHighlight
// - CameraInstructions.swift: CameraInstructions, VerificationMenu
