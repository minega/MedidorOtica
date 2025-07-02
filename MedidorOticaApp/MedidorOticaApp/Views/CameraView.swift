//
//  CameraView.swift
//  MedidorOticaApp
//
//  Tela de captura de imagem para medições de ótica.
//  Versão modularizada para melhor manutenção.
//

import SwiftUI
import AVFoundation
import Vision
import UIKit
import ARKit

struct CameraView: View {
    // MARK: - Propriedades
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraManager = CameraManager.shared
    @StateObject private var verificationManager = VerificationManager.shared
    
    // Estados da interface
    @State private var isCaptureEnabled = true
    @State private var isAutoCaptureEnabled = false
    @State private var instructionText = "Posicione seu rosto no oval"
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var capturedImage: UIImage?
    @State private var isProcessing = false
    @State private var showFlash = false
    @State private var showingResultView = false
    @State private var showVerifications = true // Mostrar verificações por padrão
    @State private var cameraInitialized = false
    
    // Timer para atualização das verificações
    @State private var verificationTimer: Timer? = nil
    
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
            // Preview da câmera
            CameraPreview(session: cameraManager.session)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    print("CameraView apareceu - iniciando câmera")
                    // Inicia as verificações e a câmera
                    setupCamera()
                    
                    // Configura o observador para notificações de erro da câmera
                    NotificationCenter.default.addObserver(
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
                }
                .onDisappear {
                    print("CameraView desapareceu - parando câmera")
                    // Para a câmera e limpa recursos
                    cameraManager.stop()
                    
                    // Remove os observadores
                    NotificationCenter.default.removeObserver(self)
                    
                    // Cancela o timer de verificações
                    verificationTimer?.invalidate()
                    verificationTimer = nil
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
            ProgressOval(verificationManager: verificationManager)
            
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
                        } else if !verificationManager.faceCentered {
                            alertMessage = "Centralize seu rosto no oval."
                        } else if !verificationManager.headAligned {
                            alertMessage = "Mantenha sua cabeça reta alinhada com a câmera."
                        } else if !verificationManager.gazeCorrect {
                            alertMessage = "Olhe diretamente para a câmera."
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
        .onDisappear {
            // Cancela o timer quando a view desaparece
            verificationTimer?.invalidate()
            verificationTimer = nil
        }
        // Alerta para mensagens de erro
        .alert(alertMessage, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        }
        // Navegação para a tela de resultados após captura
        .sheet(isPresented: $showingResultView) {
            // Implementação simplificada - apenas mostra a imagem capturada
            VStack {
                if let image = capturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
                
                Button("Fechar") {
                    showingResultView = false
                }
                .padding()
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
            let capabilities = self.verificationManager.checkDeviceCapabilities()

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
            let arSession = self.verificationManager.createARSession(for: cameraType)

            // Marca a câmera como inicializada antes da configuração para evitar chamadas redundantes
            DispatchQueue.main.async {
                self.cameraInitialized = true
            }

            // Configura a câmera com o sensor disponível
            // A configuração real é feita dentro dessa chamada, não precisamos chamar setupSession() separadamente
            self.cameraManager.setup(position: position, arSession: arSession) { success in
                if !success {
                    DispatchQueue.main.async {
                        self.alertMessage = "Não foi possível acessar a câmera."
                        self.showingAlert = true
                    }
                } else {
                    // Se tudo deu certo, iniciar o processamento (não precisamos chamar start() novamente)
                    DispatchQueue.main.async {
                        print("Câmera configurada com sucesso, iniciando processamento")
                        self.configureCameraProcessing()
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
        
        // Verifica permissões da câmera
        checkCameraPermissions { success in
            if success {
                // Configura o processamento real de frames da câmera apenas se a permissão foi concedida
                self.configureCameraProcessing()
            }
        }
    }
    
    // Verifica as permissões da câmera
    private func checkCameraPermissions(completion: @escaping (Bool) -> Void) {
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch cameraAuthStatus {
        case .authorized:
            print("Permissão de câmera já concedida")
            cameraManager.setupSession()
            completion(true)
        case .notDetermined:
            print("Solicitando permissão de câmera")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    print("Permissão de câmera concedida")
                    DispatchQueue.main.async { [self] in
                        cameraManager.setupSession()
                        completion(true)
                    }
                } else {
                    print("Permissão de câmera negada")
                    DispatchQueue.main.async { [self] in
                        showPermissionDeniedAlert()
                        completion(false)
                    }
                }
            }
        case .denied, .restricted:
            print("Permissão de câmera negada ou restrita")
            DispatchQueue.main.async { [self] in
                showPermissionDeniedAlert()
                completion(false)
            }
        @unknown default:
            // Lida com possíveis valores futuros do enum
            print("Status de autorização de câmera desconhecido: \(cameraAuthStatus)")
            DispatchQueue.main.async { [self] in
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
        cameraManager.capturePhoto { [self] image in
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

            // Atualiza as verificações em tempo real
            DispatchQueue.main.async {
                self.verificationManager.updateAllVerifications()
            }
        }
        
        // Timer auxiliar para garantir atualização da interface a cada 500ms
        // Não usamos [weak self] aqui porque CameraView é um struct (tipo de valor)
        if verificationTimer == nil {
            verificationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                DispatchQueue.main.async {
                    self.verificationManager.updateAllVerifications()
                }
            }
        }
    }
}

// MARK: - Preview Provider
struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView()
    }
}

// Os componentes foram movidos para:
// - CameraComponents.swift: CameraPreview, ProgressOval, EllipticalProgressBar, CameraHighlight
// - CameraInstructions.swift: CameraInstructions, VerificationMenu
