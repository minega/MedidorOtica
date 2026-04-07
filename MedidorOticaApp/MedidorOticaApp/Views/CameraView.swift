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
    private let showPupilTrackingOverlay = true

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
            if showPupilTrackingOverlay {
                PupilTrackingOverlay(pupilPoints: verificationManager.previewPupilPoints)
            }
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
        HStack {
            cameraTopButton(systemName: "xmark", foregroundColor: .white) {
                dismiss()
            }

            Spacer()

            cameraTopButton(systemName: isAutoCaptureEnabled ? "timer.circle.fill" : "timer.circle",
                            foregroundColor: isAutoCaptureEnabled ? .green : .white) {
                isAutoCaptureEnabled.toggle()
            }

            cameraTopButton(systemName: cameraManager.isFlashOn ? "bolt.fill" : "bolt.slash",
                            foregroundColor: cameraManager.isFlashOn ? .yellow : .white) {
                cameraManager.toggleFlash()
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
    }

    private func cameraTopButton(systemName: String,
                                 foregroundColor: Color,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .light)
        .appGlassSurface(cornerRadius: 22,
                         borderOpacity: 0.14,
                         tintOpacity: 0.32,
                         tintColor: .black,
                         variant: .regular,
                         interactive: true,
                         fallbackMaterial: .thinMaterial)
        .clipShape(Circle())
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 4)
    }

    private var captureButton: some View {
        Button(action: capturePhoto) {
            ZStack {
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.1)
                } else {
                    Text("Capturar")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .frame(width: 140, height: 50)
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .light)
        .appGlassSurface(cornerRadius: 25,
                         borderOpacity: 0.16,
                         tintOpacity: captureEnabled ? 0.28 : 0.18,
                         tintColor: .black,
                         variant: .regular,
                         interactive: captureEnabled,
                         fallbackMaterial: .thinMaterial)
        .opacity(captureEnabled ? 1 : 0.84)
        .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 6)
    }

    // MARK: - Ciclo de vida
    private func handleAppear() {
        setupCamera()
        registerObservers()
    }

    private func handleDisappear() {
        cameraManager.stop()
        cameraInitialized = false
        notificationObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    private func handleAutoCaptureChange(_ isEnabled: Bool) {
        if isEnabled {
            attemptAutoCapture()
        }
    }

    private func handleCaptureStateChange(_ state: CameraCaptureState) {
        switch state {
        case .stableReady:
            attemptAutoCapture()
        case .countdown:
            break
        case .capturing, .captured, .checking(_), .error(_), .idle, .preparing:
            break
        }
    }

    private func handleResultPresentationChange(_ isShowing: Bool) {
        if isShowing {
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

    // MARK: - Captura automatica
    private func attemptAutoCapture() {
        guard isAutoCaptureEnabled else { return }
        guard cameraManager.captureState == .stableReady else { return }
        guard !isProcessing else { return }
        DispatchQueue.main.async {
            guard isAutoCaptureEnabled else { return }
            guard cameraManager.captureState == .stableReady else { return }
            guard !isProcessing else { return }
            capturePhoto()
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
