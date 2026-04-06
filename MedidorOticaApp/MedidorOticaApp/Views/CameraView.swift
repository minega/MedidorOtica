//
//  CameraView.swift
//  MedidorOticaApp
//
//  Tela de captura de imagem para medicoes de otica.
//

import SwiftUI
import AVFoundation
import UIKit
import ARKit

struct CameraView: View {
    // MARK: - Dependencias
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraManager = CameraManager.shared
    @StateObject private var verificationManager = VerificationManager.shared
    @EnvironmentObject private var historyManager: HistoryManager

    // MARK: - Estado de UI
    @State private var isAutoCaptureEnabled = true
    @State private var countdownValue = 0
    @State private var countdownTimer: Timer?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var capturedPhoto: CapturedPhoto?
    @State private var isProcessing = false
    @State private var showFlash = false
    @State private var showingResultView = false
    @State private var showVerifications = true
    @State private var cameraInitialized = false
    @State private var notificationObservers: [NSObjectProtocol] = []

    private let showDistanceOverlay = true

#if DEBUG
    private let showAlignmentDebugOverlay = true
#endif

    // MARK: - Feedback
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    // MARK: - Computadas
    private var captureEnabled: Bool {
        cameraManager.isCaptureReady && cameraInitialized && !isProcessing
    }

    private var shouldShowVerificationMenu: Bool {
        showVerifications
    }

    // MARK: - View
    var body: some View {
        ZStack {
            previewLayer
            flashOverlay
            ProgressOval(verificationManager: verificationManager,
                         showDistance: showDistanceOverlay)
            countdownOverlay
            debugOverlay
            controlsOverlay
        }
        .alert(alertMessage, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        }
        .fullScreenCover(isPresented: $showingResultView) {
            if let photo = capturedPhoto {
                PostCaptureFlowView(capturedPhoto: photo, onRetake: {
                    capturedPhoto = nil
                    showingResultView = false
                })
                .environmentObject(historyManager)
            }
        }
        .onAppear(perform: handleAppear)
        .onDisappear(perform: handleDisappear)
        .onChange(of: isAutoCaptureEnabled, perform: handleAutoCaptureChange)
        .onChange(of: cameraManager.captureState, perform: handleCaptureStateChange)
        .onChange(of: showingResultView, perform: handleResultPresentationChange)
    }

    // MARK: - Preview
    @ViewBuilder
    private var previewLayer: some View {
        Group {
            if cameraManager.isUsingARSession, let arSession = cameraManager.arSession {
                ARCameraPreview(session: arSession, delegate: cameraManager)
            } else {
                CameraPreview(session: cameraManager.session)
            }
        }
        .edgesIgnoringSafeArea(.all)
    }

    private var flashOverlay: some View {
        Group {
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
        }
    }

    private var countdownOverlay: some View {
        Group {
            if countdownValue > 0 {
                VStack(spacing: 16) {
                    Text("Agora olhe para a camera")
                        .font(.title2)
                        .foregroundColor(.white)

                    Text("Mantenha o celular parado")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))

                    Text("\(countdownValue)")
                        .font(.system(size: 72, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
    }

    @ViewBuilder
    private var debugOverlay: some View {
#if DEBUG
        if showAlignmentDebugOverlay {
            HeadAlignmentDebugOverlay(verificationManager: verificationManager)
                .padding(12)
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity,
                       alignment: .topLeading)
                .transition(.opacity)
        }
#endif
    }

    // MARK: - Controles
    private var controlsOverlay: some View {
        VStack {
            topBar

            if shouldShowVerificationMenu {
                VerificationMenu(verificationManager: verificationManager)
                    .padding(.top, 8)
            }

            CameraInstructions(verificationManager: verificationManager,
                               cameraManager: cameraManager)

            Spacer()
            captureButton
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            cameraTopButton(systemName: "xmark", foregroundColor: .white) {
                dismiss()
            }

            Spacer()

            cameraTopControlGroup
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var cameraTopControlGroup: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    cameraTopButton(systemName: isAutoCaptureEnabled ? "timer.circle.fill" : "timer.circle",
                                    foregroundColor: isAutoCaptureEnabled ? Color(red: 0.35, green: 0.82, blue: 0.52) : .white) {
                        isAutoCaptureEnabled.toggle()
                    }

                    cameraTopButton(systemName: cameraManager.isFlashOn ? "bolt.fill" : "bolt.slash",
                                    foregroundColor: cameraManager.isFlashOn ? Color(red: 1.0, green: 0.87, blue: 0.34) : .white) {
                        cameraManager.toggleFlash()
                    }
                }
            }
            .environment(\.colorScheme, .light)
        } else {
            HStack(spacing: 12) {
                cameraTopButton(systemName: isAutoCaptureEnabled ? "timer.circle.fill" : "timer.circle",
                                foregroundColor: isAutoCaptureEnabled ? Color(red: 0.35, green: 0.82, blue: 0.52) : .white) {
                    isAutoCaptureEnabled.toggle()
                }

                cameraTopButton(systemName: cameraManager.isFlashOn ? "bolt.fill" : "bolt.slash",
                                foregroundColor: cameraManager.isFlashOn ? Color(red: 1.0, green: 0.87, blue: 0.34) : .white) {
                    cameraManager.toggleFlash()
                }
            }
        }
    }

    private func cameraTopButton(systemName: String,
                                 foregroundColor: Color,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .light)
        .appGlassSurface(cornerRadius: 26,
                         borderOpacity: 0.18,
                         tintOpacity: 0.16,
                         tintColor: .white,
                         variant: .regular,
                         interactive: true,
                         fallbackMaterial: .thinMaterial)
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 8)
    }

    private var captureButton: some View {
        Button(action: capturePhoto) {
            ZStack {
                Capsule()
                    .fill(captureEnabled ?
                          AnyShapeStyle(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]),
                                                       startPoint: .leading,
                                                       endPoint: .trailing)) :
                            AnyShapeStyle(Color.gray))
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

    // MARK: - Ciclo de vida
    private func handleAppear() {
        setupCamera()
        registerObservers()
    }

    private func handleDisappear() {
        cancelCountdown(refreshState: false)
        cameraManager.stop()
        cameraInitialized = false
        notificationObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    private func handleAutoCaptureChange(_ isEnabled: Bool) {
        if isEnabled {
            attemptAutoCountdown()
        } else {
            cancelCountdown()
        }
    }

    private func handleCaptureStateChange(_ state: CameraCaptureState) {
        switch state {
        case .stableReady:
            attemptAutoCountdown()
        case .countdown:
            break
        case .capturing, .captured, .checking(_), .error(_), .idle, .preparing:
            cancelCountdown(refreshState: false)
        }
    }

    private func handleResultPresentationChange(_ isShowing: Bool) {
        if isShowing {
            cancelCountdown(refreshState: false)
            cameraManager.stop()
            cameraInitialized = false
            return
        }

        guard !cameraManager.isSessionRunning else { return }
        DispatchQueue.main.async {
            setupCamera()
        }
    }

    // MARK: - Setup
    private func setupCamera() {
        if cameraInitialized {
            cameraManager.stop()
            cameraInitialized = false
        }

        checkCameraPermissions { permissionGranted in
            guard permissionGranted else { return }

            cameraManager.checkAvailableSensors()
            guard cameraManager.hasTrueDepth else {
                alertMessage = "Este dispositivo nao possui o sensor TrueDepth necessario para a medicao."
                showingAlert = true
                return
            }

            cameraManager.startMeasurementSession { success in
                DispatchQueue.main.async {
                    if success {
                        cameraInitialized = true
                        configureCameraProcessing()
                    } else {
                        alertMessage = "Nao foi possivel acessar a camera."
                        showingAlert = true
                    }
                }
            }
        }
    }

    private func configureCameraProcessing() {
        cameraManager.outputDelegate = { frame in
            verificationManager.processARFrame(frame)
        }
    }

    private func registerObservers() {
        registerCameraErrorObserver()
        registerARConfigurationObserver()
        registerARErrorObserver()
        registerCompatibilityObserver()
    }

    private func registerCameraErrorObserver() {
        let token = NotificationCenter.default.addObserver(forName: .cameraError,
                                                           object: nil,
                                                           queue: .main) { notification in
            guard let error = notification.userInfo?["error"] as? CameraError else { return }
            Task { @MainActor in
                handleCameraError(error)
            }
        }
        notificationObservers.append(token)
    }

    private func registerARConfigurationObserver() {
        let token = NotificationCenter.default.addObserver(forName: NSNotification.Name("ARConfigurationFailed"),
                                                           object: nil,
                                                           queue: .main) { notification in
            let message = notification.userInfo?["error"] as? String
            Task { @MainActor in
                if let message {
                    alertMessage = message
                } else {
                    alertMessage = "Falha ao configurar ARSession."
                }
                cameraManager.stop()
                showingAlert = true
            }
        }
        notificationObservers.append(token)
    }

    private func registerARErrorObserver() {
        let token = NotificationCenter.default.addObserver(forName: .arSessionError,
                                                           object: nil,
                                                           queue: .main) { notification in
            let message = notification.userInfo?["message"] as? String
            Task { @MainActor in
                if let message {
                    alertMessage = message
                } else {
                    alertMessage = "A sessao de AR apresentou um erro."
                }
                showingAlert = true
            }
        }
        notificationObservers.append(token)
    }

    private func registerCompatibilityObserver() {
        let token = NotificationCenter.default.addObserver(forName: NSNotification.Name("DeviceNotCompatible"),
                                                           object: nil,
                                                           queue: .main) { notification in
            let reason = notification.userInfo?["reason"] as? String
            let sensor = notification.userInfo?["sensor"] as? String
            Task { @MainActor in
                if let reason {
                    alertMessage = "Dispositivo nao compativel: \(reason)"
                } else if let sensor {
                    alertMessage = "Dispositivo nao possui o sensor \(sensor) necessario."
                } else {
                    alertMessage = "Dispositivo nao compativel com as medicoes."
                }
                showingAlert = true
            }
        }
        notificationObservers.append(token)
    }

    private func checkCameraPermissions(completion: @escaping (Bool) -> Void) {
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch cameraAuthStatus {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        completion(true)
                    } else {
                        showPermissionDeniedAlert()
                        completion(false)
                    }
                }
            }
        case .denied, .restricted:
            showPermissionDeniedAlert()
            completion(false)
        @unknown default:
            showPermissionDeniedAlert()
            completion(false)
        }
    }

    private func showPermissionDeniedAlert() {
        alertMessage = "O acesso a camera e necessario para fazer medicoes. Ative a permissao nas configuracoes do dispositivo."
        showingAlert = true
    }

    private func handleCameraError(_ error: CameraError) {
        if case .missingTrueDepthData = error,
           let hint = cameraManager.latestCalibrationFailureHint() {
            alertMessage = "\(error.localizedDescription)\n\(hint)"
        } else {
            alertMessage = error.localizedDescription
        }

        showingAlert = true
        isProcessing = false
    }

    // MARK: - Captura
    private func capturePhoto() {
        guard !isProcessing else { return }
        guard captureEnabled else {
            alertMessage = manualCaptureBlockMessage()
            showingAlert = true
            notificationGenerator.notificationOccurred(.warning)
            return
        }

        cancelCountdown(refreshState: false)
        impactGenerator.impactOccurred()
        isProcessing = true
        showFlash = true

        cameraManager.capturePhoto { photo in
            DispatchQueue.main.async {
                isProcessing = false

                if let photo {
                    capturedPhoto = photo
                    showingResultView = true
                    return
                }

                if cameraManager.error == nil {
                    alertMessage = "Nao foi possivel capturar a imagem. Tente novamente."
                    showingAlert = true
                }
                notificationGenerator.notificationOccurred(.error)
            }
        }
    }

    private func manualCaptureBlockMessage() -> String {
        if !cameraInitialized {
            return "A camera ainda esta iniciando. Aguarde o preview estabilizar."
        }

        if !cameraManager.isTrueDepthSensorAlive {
            return cameraManager.trueDepthHint()
        }

        if !verificationManager.faceDetected {
            return "Encaixe testa, olhos e queixo dentro do oval."
        }

        if !verificationManager.distanceCorrect {
            return verificationManager.lastMeasuredDistance < verificationManager.minDistance ?
                "Afaste um pouco o rosto para entrar na faixa ideal." :
                "Aproxime um pouco o rosto para entrar na faixa ideal."
        }

        if !verificationManager.faceAligned {
            return "Ajuste o celular ate o nariz ficar exatamente no centro do oval."
        }

        if !verificationManager.headAligned {
            if let snapshot = verificationManager.headPoseSnapshot,
               let adjustment = HeadPoseInstructionBuilder.adjustment(from: snapshot) {
                return adjustment.instruction
            }

            if cameraManager.captureState == .checking(.headPoseUnavailable) {
                return "Mostre testa, olhos e queixo para medir os eixos da cabeca."
            }
            return "Corrija primeiro o eixo indicado na instrucao da tela antes da captura."
        }

        return cameraManager.captureHint
    }

    // MARK: - Contagem automatica
    private func attemptAutoCountdown() {
        guard isAutoCaptureEnabled else { return }
        guard cameraManager.captureState == .stableReady else { return }
        guard countdownTimer == nil else { return }
        startCountdown()
    }

    private func startCountdown() {
        guard isAutoCaptureEnabled else { return }
        cancelCountdown(refreshState: false)
        countdownValue = 3
        cameraManager.setCountdownActive(true)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1,
                                              repeats: true) { timer in
            if countdownValue > 1 {
                countdownValue -= 1
                return
            }

            timer.invalidate()
            countdownTimer = nil
            countdownValue = 0
            capturePhoto()
        }
    }

    private func cancelCountdown(refreshState: Bool = true) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownValue = 0
        if refreshState {
            cameraManager.setCountdownActive(false)
        }
    }
}

#if DEBUG
//  HeadAlignmentDebugOverlay.swift
//  Painel rapido para mostrar angulos calculados durante os testes.
//

/// Overlay que apresenta as medicoes atuais de rotacao da cabeca para depuracao.
struct HeadAlignmentDebugOverlay: View {
    @ObservedObject var verificationManager: VerificationManager

    var body: some View {
        let snapshot = verificationManager.headPoseSnapshot
        let roll = snapshot?.rollDegrees ?? 0
        let yaw = snapshot?.yawDegrees ?? 0
        let pitch = snapshot?.pitchDegrees ?? 0

        VStack(alignment: .leading, spacing: 4) {
            Text("🔧 Depuracao Alinhamento")
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)

            debugRow(label: "Roll", value: roll)
            debugRow(label: "Yaw", value: yaw)
            debugRow(label: "Pitch", value: pitch)
        }
        .padding(10)
        .background(Color.black.opacity(0.65))
        .cornerRadius(8)
        .accessibilityLabel("Painel de depuracao do alinhamento da cabeca")
    }

    private func debugRow(label: String, value: Float) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(String(format: "% .1f°", value))
        }
        .font(.caption.monospacedDigit())
        .foregroundColor(.white)
    }
}
#endif

// MARK: - Preview Provider
struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView()
            .environmentObject(HistoryManager.shared)
    }
}
