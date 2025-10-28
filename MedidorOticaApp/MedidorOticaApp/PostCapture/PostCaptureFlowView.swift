//
//  PostCaptureFlowView.swift
//  MedidorOticaApp
//
//  Interface principal do fluxo pós-captura com etapas navegáveis e resumo final.
//

import SwiftUI

// MARK: - Fluxo Pós-Captura
struct PostCaptureFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyManager: HistoryManager

    @StateObject private var viewModel: PostCaptureViewModel
    @State private var clientName: String
    @State private var showingSaveError = false
    @State private var showingShareSheet = false
    @State private var renderedOverlay: UIImage?

    let onRetake: () -> Void
    private let existingMeasurement: Measurement?

    // MARK: - Inicialização
    init(capturedImage: UIImage,
         existingMeasurement: Measurement? = nil,
         onRetake: @escaping () -> Void) {
        self._viewModel = StateObject(wrappedValue: PostCaptureViewModel(image: capturedImage,
                                                                         existingMeasurement: existingMeasurement))
        self._clientName = State(initialValue: existingMeasurement?.clientName ?? "")
        self.onRetake = onRetake
        self.existingMeasurement = existingMeasurement
    }

    // MARK: - View
    var body: some View {
        Group {
            if viewModel.currentStage == .confirmation {
                confirmationScreen
            } else {
                standardScreen
            }
        }
        .background(Color.black.opacity(0.95).ignoresSafeArea())
        .alert("Erro ao processar", isPresented: Binding(get: {
            viewModel.errorMessage != nil
        }, set: { _ in
            viewModel.errorMessage = nil
        })) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = renderedOverlay,
               let metrics = viewModel.metrics {
                let description = shareDescription(from: metrics)
                ShareSheet(items: [image, description])
            }
        }
        .alert("Informe o nome do cliente", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Preencha o nome antes de salvar no histórico.")
        }
    }

    private var confirmationScreen: some View {
        ZStack {
            PostCaptureOverlayView(viewModel: viewModel)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Spacer()

                Text(viewModel.stageInstructions)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)

                confirmationActions
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if viewModel.isProcessing {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                ProgressView("Processando rosto...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .foregroundColor(.white)
            }
        }
    }

    private var standardScreen: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                header
                overlaySection(in: geometry)
                stageContent
                Spacer()
                bottomActions
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pós-Captura")
                    .font(.title2)
                    .foregroundColor(.white)
                    .fontWeight(.bold)

                if viewModel.showEyeLabel {
                    Text("Olho \(viewModel.currentEye.rawValue) • \(viewModel.currentStage.description)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    Text(viewModel.currentStage.description)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    /// Botões exibidos na etapa inicial para refazer ou iniciar as marcações.
    private var confirmationActions: some View {
        HStack(spacing: 12) {
            Button(action: onRetake) {
                Label("Refazer", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Button(action: viewModel.advanceStage) {
                Label("Iniciar", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(viewModel.isProcessing)
        }
    }

    private func overlaySection(in geometry: GeometryProxy) -> some View {
        let ratio: CGFloat = viewModel.isOnSummary ? 0.45 : 0.62
        let baseHeight = geometry.size.height * ratio
        let targetHeight = min(baseHeight, 460)

        return ZStack {
            if viewModel.isProcessing {
                ProgressView("Processando foto...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PostCaptureOverlayView(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity,
               minHeight: targetHeight,
               maxHeight: targetHeight)
        .background(Color.gray.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.3), value: viewModel.currentStage)
    }

    @ViewBuilder
    private var stageContent: some View {
        if viewModel.isOnSummary {
            summaryContent
        } else {
            Text(viewModel.stageInstructions)
                .font(.body)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().background(Color.white.opacity(0.2))

            Text("Resumo das Medidas")
                .font(.headline)
                .foregroundColor(.white)

            if let metrics = viewModel.metrics {
                summaryMetricsView(metrics)
            }

            TextField("Nome do cliente", text: $clientName)
                .textFieldStyle(.roundedBorder)
                .padding(.top, 8)

            HStack(spacing: 12) {
                Button(action: shareSummary) {
                    Label("Compartilhar", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button(action: saveMeasurement) {
                    Label(existingMeasurement == nil ? "Salvar" : "Atualizar", systemImage: "tray.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func summaryMetricsView(_ metrics: PostCaptureMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            metricRow(title: "Horizontal Maior OD", value: metrics.rightEye.horizontalMaior)
            metricRow(title: "Horizontal Maior OE", value: metrics.leftEye.horizontalMaior)
            metricRow(title: "Vertical Maior OD", value: metrics.rightEye.verticalMaior)
            metricRow(title: "Vertical Maior OE", value: metrics.leftEye.verticalMaior)
            metricRow(title: "Ponte da Armação", value: metrics.ponte)
            metricRow(title: "DNP OD", value: metrics.rightEye.dnp)
            metricRow(title: "DNP OE", value: metrics.leftEye.dnp)
            metricRow(title: "Altura Pupilar OD", value: metrics.rightEye.alturaPupilar)
            metricRow(title: "Altura Pupilar OE", value: metrics.leftEye.alturaPupilar)
            metricRow(title: "DP Total", value: metrics.distanciaPupilarTotal)
        }
    }

    private func metricRow(title: String, value: Double) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            Text(String(format: "%.1f mm", value))
                .foregroundColor(.yellow)
                .fontWeight(.semibold)
        }
    }

    private var bottomActions: some View {
        HStack(spacing: 12) {
            Button(action: onRetake) {
                Label("Refazer", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)

            if viewModel.canGoBack && !viewModel.isOnSummary {
                Button(action: viewModel.goBack) {
                    Label("Voltar", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray)
            }

            if !viewModel.isOnSummary {
                Button(action: viewModel.advanceStage) {
                    Label(viewModel.currentStage == .confirmation ? "Iniciar" : "Próximo",
                          systemImage: viewModel.currentStage == .confirmation ? "play.fill" : "chevron.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(viewModel.isProcessing)
            }
        }
    }

    // MARK: - Ações
    private func saveMeasurement() {
        showingSaveError = false
        viewModel.finalizeMetrics()
        guard let measurement = viewModel.buildMeasurement(clientName: clientName) else {
            showingSaveError = true
            return
        }

        Task {
            if let existingMeasurement {
                await historyManager.updateMeasurement(measurement)
            } else {
                await historyManager.addMeasurement(measurement)
            }
            await MainActor.run {
                dismiss()
            }
        }
    }

    private func shareSummary() {
        viewModel.finalizeMetrics()
        guard let metrics = viewModel.metrics else { return }
        let renderer = ImageRenderer(content: shareSnapshotView(metrics: metrics))
        renderer.scale = UIScreen.main.scale
        renderedOverlay = renderer.uiImage
        if renderedOverlay != nil {
            showingShareSheet = true
        }
    }

    private func shareDescription(from metrics: PostCaptureMetrics) -> String {
        "Horizontal OD: \(String(format: "%.1f", metrics.rightEye.horizontalMaior)) mm\n" +
        "Horizontal OE: \(String(format: "%.1f", metrics.leftEye.horizontalMaior)) mm\n" +
        "Vertical OD: \(String(format: "%.1f", metrics.rightEye.verticalMaior)) mm\n" +
        "Vertical OE: \(String(format: "%.1f", metrics.leftEye.verticalMaior)) mm\n" +
        "Ponte: \(String(format: "%.1f", metrics.ponte)) mm\n" +
        "DNP Total: \(String(format: "%.1f", metrics.distanciaPupilarTotal)) mm"
    }

    @ViewBuilder
    private func shareSnapshotView(metrics: PostCaptureMetrics) -> some View {
        VStack(spacing: 24) {
            PostCaptureOverlayView(viewModel: viewModel)
                .frame(width: 600, height: 600)
                .clipShape(RoundedRectangle(cornerRadius: 24))

            VStack(alignment: .leading, spacing: 12) {
                Text("Resumo Pós-Captura")
                    .font(.title2)
                    .foregroundColor(.white)
                    .bold()

                summaryMetricsView(metrics)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .padding(40)
        .background(Color.black)
    }
}
