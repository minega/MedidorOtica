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
    @State private var orderNumber: String
    @State private var validationErrorMessage: String?
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
        self._orderNumber = State(initialValue: existingMeasurement?.orderNumber ?? "")
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
        .alert("Atenção", isPresented: Binding(get: {
            validationErrorMessage != nil
        }, set: { _ in
            validationErrorMessage = nil
        })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationErrorMessage ?? "")
        }
    }

    private var confirmationScreen: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, geometry.safeAreaInsets.top + 12)

                    Spacer(minLength: 16)

                    PostCaptureOverlayView(viewModel: viewModel)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .frame(height: geometry.size.height * 0.64)

                    Spacer(minLength: 12)

                    VStack(spacing: 20) {
                        Text(viewModel.stageInstructions)
                            .font(.body)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        confirmationActions
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 24))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.isProcessing {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    ProgressView("Processando rosto...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var standardScreen: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                header
                overlaySection(in: geometry)
                Spacer()
                VStack(spacing: 16) {
                    stageContent
                    bottomActions
                }
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
        let ratio: CGFloat = viewModel.isOnSummary ? 0.42 : 0.76
        let baseHeight = geometry.size.height * ratio
        let targetHeight = min(baseHeight, geometry.size.height * 0.78)

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
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    /// Painel exibido no resumo com métricas, identificação do cliente e ações finais.
    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().background(Color.white.opacity(0.2))

            Text("Resumo das Medidas")
                .font(.headline)
                .foregroundColor(.white)

            if let metrics = viewModel.metrics {
                summaryMetricsView(metrics)
            }

            summaryFormFields
            summaryActionButtons
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Campos que solicitam os dados necessários para salvar no histórico.
    private var summaryFormFields: some View {
        VStack(spacing: 12) {
            TextField("Nome do cliente", text: $clientName)
                .textFieldStyle(.roundedBorder)

            TextField("Número da OS", text: $orderNumber)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
        }
        .padding(.top, 4)
    }

    /// Conjunto de botões disponibilizados no resumo para compartilhar, revisar, salvar ou cancelar.
    private var summaryActionButtons: some View {
        VStack(spacing: 12) {
            Button(action: shareSummary) {
                Label("Compartilhar", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            HStack(spacing: 12) {
                Button(action: startReview) {
                    Label("Revisar", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Button(action: cancelSummary) {
                    Label("Cancelar", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            Button(action: saveMeasurement) {
                Label(existingMeasurement == nil ? "Salvar" : "Atualizar", systemImage: "tray.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }

    /// Apresenta as métricas finais seguindo o padrão solicitado: "Nome - OD/OE".
    private func summaryMetricsView(_ metrics: PostCaptureMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summaryLine(title: "Horizontal maior",
                             rightValue: metrics.rightEye.horizontalMaior,
                             leftValue: metrics.leftEye.horizontalMaior))

            Text(summaryLine(title: "Vertical maior",
                             rightValue: metrics.rightEye.verticalMaior,
                             leftValue: metrics.leftEye.verticalMaior))

            Text(summaryLine(title: "DNP",
                             rightValue: metrics.rightEye.dnp,
                             leftValue: metrics.leftEye.dnp))

            Text(summaryLine(title: "Altura pupilar",
                             rightValue: metrics.rightEye.alturaPupilar,
                             leftValue: metrics.leftEye.alturaPupilar))

            Text(summaryLine(title: "Ponte",
                             singleValue: metrics.ponte))
        }
        .foregroundColor(.white.opacity(0.9))
        .font(.subheadline)
        .fontWeight(.semibold)
    }

    /// Monta a string usada tanto no resumo visual quanto no compartilhamento.
    private func summaryLine(title: String,
                             rightValue: Double? = nil,
                             leftValue: Double? = nil,
                             singleValue: Double? = nil) -> String {
        if let singleValue {
            return "\(title) - \(formatValue(singleValue))"
        }

        if let rightValue, let leftValue {
            return "\(title) - \(formatValue(rightValue, suffix: "OD"))/\(formatValue(leftValue, suffix: "OE"))"
        }

        if let rightValue {
            return "\(title) - \(formatValue(rightValue, suffix: "OD"))"
        }

        if let leftValue {
            return "\(title) - \(formatValue(leftValue, suffix: "OE"))"
        }

        return "\(title) - -"
    }

    /// Formata um valor double para apresentação com unidade e sufixo opcional.
    private func formatValue(_ value: Double, suffix: String? = nil) -> String {
        let base = String(format: "%.1f mm", value)
        guard let suffix else { return base }
        return "\(base) \(suffix)"
    }

    @ViewBuilder
    private var bottomActions: some View {
        if viewModel.isOnSummary {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                Button(action: onRetake) {
                    Label("Refazer", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                if viewModel.canGoBack {
                    Button(action: viewModel.goBack) {
                        Label("Voltar", systemImage: "chevron.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray)
                }

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
        validationErrorMessage = nil
        let trimmedName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrder = orderNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            validationErrorMessage = "Preencha o nome do cliente antes de salvar no histórico."
            return
        }

        guard !trimmedOrder.isEmpty else {
            validationErrorMessage = "Informe o número da OS para salvar no histórico."
            return
        }

        viewModel.finalizeMetrics()

        guard let measurement = viewModel.buildMeasurement(clientName: trimmedName,
                                                           orderNumber: trimmedOrder) else {
            validationErrorMessage = "Não foi possível gerar o resumo das medidas."
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

    /// Retorna a etapa inicial para permitir que o usuário revise todas as marcações.
    private func startReview() {
        validationErrorMessage = nil
        viewModel.restartFlowFromBeginning()
    }

    /// Cancela o fluxo atual e fecha a tela sem salvar alterações.
    private func cancelSummary() {
        validationErrorMessage = nil
        dismiss()
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
        var lines: [String] = []

        let trimmedName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrder = orderNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedName.isEmpty {
            lines.append("Cliente: \(trimmedName)")
        }

        if !trimmedOrder.isEmpty {
            lines.append("OS: \(trimmedOrder)")
        }

        lines.append(contentsOf: [
            summaryLine(title: "Horizontal maior",
                        rightValue: metrics.rightEye.horizontalMaior,
                        leftValue: metrics.leftEye.horizontalMaior),
            summaryLine(title: "Vertical maior",
                        rightValue: metrics.rightEye.verticalMaior,
                        leftValue: metrics.leftEye.verticalMaior),
            summaryLine(title: "DNP",
                        rightValue: metrics.rightEye.dnp,
                        leftValue: metrics.leftEye.dnp),
            summaryLine(title: "Altura pupilar",
                        rightValue: metrics.rightEye.alturaPupilar,
                        leftValue: metrics.leftEye.alturaPupilar),
            summaryLine(title: "Ponte",
                        singleValue: metrics.ponte)
        ])

        return lines.joined(separator: "\n")
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
