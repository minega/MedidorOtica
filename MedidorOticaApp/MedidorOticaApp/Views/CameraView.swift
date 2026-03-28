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
    private let showARStatusIndicator = true
    private let showCaptureDiagnostics = true

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
        .onChange(of: isAutoCaptureEnabled) { _, isEnabled in
            handleAutoCaptureChange(isEnabled)
        }
        .onChange(of: cameraManager.captureState) { _, state in
            handleCaptureStateChange(state)
        }
        .onChange(of: showingResultView) { _, isShowing in
            handleResultPresentationChange(isShowing)
        }
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
        if showCaptureDiagnostics {
            CaptureDiagnosticsOverlay(cameraManager: cameraManager)
                .padding(.horizontal, 12)
                .padding(.top, 82)
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity,
                       alignment: .topLeading)
        }

#if DEBUG
        if showAlignmentDebugOverlay {
            HeadAlignmentDebugOverlay(verificationManager: verificationManager)
                .padding(12)
                .padding(.top, 220)
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
            }

            CameraInstructions(verificationManager: verificationManager,
                               cameraManager: cameraManager)

            Spacer()
            captureButton
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
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

            Button(action: { isAutoCaptureEnabled.toggle() }) {
                Image(systemName: isAutoCaptureEnabled ? "timer.circle.fill" : "timer.circle")
                    .font(.title3)
                    .foregroundColor(isAutoCaptureEnabled ? .green : .white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }

            Button(action: { cameraManager.toggleFlash() }) {
                Image(systemName: cameraManager.isFlashOn ? "bolt.fill" : "bolt.slash")
                    .font(.title3)
                    .foregroundColor(cameraManager.isFlashOn ? .yellow : .white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
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
            Task { @MainActor in
                if let message = notification.userInfo?["error"] as? String {
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
            Task { @MainActor in
                if let message = notification.userInfo?["message"] as? String {
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
            Task { @MainActor in
                if let reason = notification.userInfo?["reason"] as? String {
                    alertMessage = "Dispositivo nao compativel: \(reason)"
                } else if let sensor = notification.userInfo?["sensor"] as? String {
                    alertMessage = "Dispositivo nao possui o sensor \(sensor) necessario."
                } else {
                    alertMessage = "Dispositivo nao compativel com as medicoes."
                }
                showingAlert = true
            }
        }
        notificationObservers.append(token)
    }

    private func checkCameraPermissions(completion: @MainActor @escaping (Bool) -> Void) {
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch cameraAuthStatus {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
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
            Task { @MainActor in
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
        if let detail = cameraManager.captureDiagnostics.failureDetail,
           !detail.blockingHint.isEmpty {
            return detail.blockingHint
        }

        if !cameraManager.captureDiagnostics.blockingHint.isEmpty {
            return cameraManager.captureDiagnostics.blockingHint
        }

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
            if verificationManager.projectedFaceTooSmall {
                return "Aproxime o rosto ate os olhos ocuparem melhor o oval."
            }
            return verificationManager.lastMeasuredDistance < verificationManager.minDistance ?
                "Afaste um pouco o rosto para entrar na faixa ideal." :
                "Aproxime um pouco o rosto para entrar na faixa ideal."
        }

        if !verificationManager.faceAligned {
            return "Ajuste o celular ate o nariz ficar exatamente no centro do oval."
        }

        if !verificationManager.headAligned {
            return "Nivele os olhos e mantenha a cabeca reta antes da captura."
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
            Task { @MainActor in
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
        let roll = verificationManager.alignmentData["roll"] ?? 0
        let yaw = verificationManager.alignmentData["yaw"] ?? 0
        let pitch = verificationManager.alignmentData["pitch"] ?? 0

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

// MARK: - Diagnostico da captura
/// Painel temporario exibido no TestFlight para acelerar a depuracao em hardware real.
struct CaptureDiagnosticsOverlay: View {
    @ObservedObject var cameraManager: CameraManager

    private var snapshot: CaptureDiagnosticsSnapshot {
        cameraManager.captureDiagnostics
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Diagnostico da Captura")
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)

            line("Etapa", value: snapshot.overallStep == .idle ? "Inicializando" : title(for: snapshot.overallStep))
            line("Motivo", value: snapshot.failureDetail?.diagnosticLabel ?? snapshot.blockingReason?.shortMessage ?? "Pronto")
            line("Instrucao", value: snapshot.blockingHint.isEmpty ? "Aguardando frame valido" : snapshot.blockingHint)
            line("TrueDepth", value: title(for: snapshot.trueDepthState))
            line("Calibracao", value: snapshot.calibrationReady ? "OK" : (snapshot.calibrationHint ?? "Pendente"))
            line("Estabilidade", value: "\(snapshot.stableSampleCount)/\(snapshot.requiredStableSampleCount)")

            if let headDiagnostic = snapshot.headAlignmentDiagnostic,
               let primary = headDiagnostic.primaryFailure {
                line("Subchecagem", value: primary.title)
                line("Valor", value: formattedMetric(primary))
                line("Faixa", value: formattedRange(primary))
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.72))
        .cornerRadius(10)
        .frame(maxWidth: 320, alignment: .leading)
        .accessibilityLabel("Painel de diagnostico detalhado da captura")
    }

    private func line(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundColor(.white.opacity(0.65))
            Text(value)
                .font(.caption)
                .foregroundColor(.white)
        }
    }

    private func formattedMetric(_ metric: VerificationMetricDiagnostic) -> String {
        guard let value = metric.currentValue else { return "Sem leitura confiavel" }
        return "\(String(format: "%.1f", value))\(metric.unit)"
    }

    private func formattedRange(_ metric: VerificationMetricDiagnostic) -> String {
        guard let range = metric.targetRange else { return "Sem faixa definida" }
        return "\(String(format: "%.1f", range.lowerBound)) a \(String(format: "%.1f", range.upperBound))\(metric.unit)"
    }

    private func title(for step: VerificationStep) -> String {
        switch step {
        case .idle:
            return "Inicializando"
        case .faceDetection:
            return "Rosto"
        case .distance:
            return "Distancia"
        case .centering:
            return "Centralizacao"
        case .headAlignment:
            return "Alinhamento"
        case .completed:
            return "Pronto"
        }
    }

    private func title(for state: TrueDepthBootstrapState) -> String {
        switch state {
        case .startingSession:
            return "Iniciando"
        case .waitingForFaceAnchor:
            return "Aguardando rosto"
        case .waitingForEyeProjection:
            return "Aguardando olhos"
        case .waitingForDepthConsistency:
            return "Aguardando malha"
        case .sensorAlive:
            return "Sensor vivo"
        case .recovering(let attempt):
            return "Recuperando (\(attempt))"
        case .failed(let reason):
            return "Falhou: \(reason.shortMessage)"
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
