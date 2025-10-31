//
//  PostCaptureFlowView.swift
//  MedidorOticaApp
//
//  Interface principal do fluxo pós-captura com etapas navegáveis e resumo final.
//

import SwiftUI
import UIKit

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
    init(capturedPhoto: CapturedPhoto,
         existingMeasurement: Measurement? = nil,
         onRetake: @escaping () -> Void) {
        self._viewModel = StateObject(wrappedValue: PostCaptureViewModel(photo: capturedPhoto,
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
                let description = metrics.shareDescription(clientName: clientName,
                                                           orderNumber: orderNumber)
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
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        header
                        overlaySection(in: geometry)
                        stageContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, geometry.safeAreaInsets.top + 16)
                    .padding(.bottom, viewModel.isOnSummary ? geometry.safeAreaInsets.bottom + 32 : 32)
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                if !viewModel.isOnSummary {
                    bottomActionsView()
                        .padding(.horizontal, 20)
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 24))
                        .background(Color.black.opacity(0.001))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Resumo das Medidas")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("Confira, edite e salve as informações antes de finalizar.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
            }

            if let metrics = viewModel.metrics {
                SummaryMetricsSection(metrics: metrics)
            }

            summaryFormFields
            summaryActionButtons
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color.white.opacity(0.12),
                                             Color.white.opacity(0.04)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }

    /// Campos que solicitam os dados necessários para salvar no histórico.
    private var summaryFormFields: some View {
        VStack(spacing: 14) {
            SummaryInputField(placeholder: "Nome do cliente",
                              text: $clientName,
                              keyboardType: .default,
                              capitalization: .words,
                              disableAutocorrection: false)

            SummaryInputField(placeholder: "Número da OS",
                              text: $orderNumber,
                              keyboardType: .numbersAndPunctuation)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
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

                SummaryMetricsSection(metrics: metrics)
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

// MARK: - Ações auxiliares
private extension PostCaptureFlowView {
    /// Conjunto de botões inferiores exibidos durante as etapas intermediárias.
    @ViewBuilder
    func bottomActionsView() -> some View {
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
}

// MARK: - Componentes de resumo
/// Estiliza cada valor numérico com um chip arredondado para fácil leitura.
private struct SummaryValueChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.body, design: .rounded).monospacedDigit())
            .foregroundColor(.white)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
    }
}

/// Conjunto que organiza e exibe as métricas calculadas no formato "Nome - OD/OE".
private struct SummaryMetricsSection: View {
    let metrics: PostCaptureMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Valores em mm — OD / OE")
                .font(.caption)
                .foregroundColor(.white.opacity(0.65))

            ForEach(metrics.summaryEntries()) { entry in
                SummaryMetricCard(entry: entry)
            }
        }
    }

    /// Cartão responsável por aplicar o padrão textual e visual de cada medida.
    private struct SummaryMetricCard: View {
        let entry: PostCaptureMetrics.SummaryMetricEntry

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(headerText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .monospacedDigit()

                content
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }

        private var headerText: String {
            "\(entry.title) - \(entry.compactDisplay(using: PostCaptureMetrics.summaryNumberFormatter))"
        }

        @ViewBuilder
        private var content: some View {
            if entry.hasPair {
                HStack(spacing: 12) {
                    if let value = entry.rightValue.map(formattedMetricValue) {
                        SummaryValueChip(text: value)
                    }

                    Text("/")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.5))

                    if let value = entry.leftValue.map(formattedMetricValue) {
                        SummaryValueChip(text: value)
                    }
                }
            } else if let value = entry.singleValue.map(formattedMetricValue) {
                SummaryValueChip(text: value)
            } else {
                Text("-")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.6))
            }
        }

        private func formattedMetricValue(_ value: Double) -> String {
            PostCaptureMetrics.summaryNumberFormatter.string(from: NSNumber(value: value))
            ?? String(format: "%.1f", value)
        }
    }
}

/// Campo reutilizável utilizado no formulário de identificação do resumo final.
private struct SummaryInputField: View {
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType
    let capitalization: TextInputAutocapitalization
    let disableAutocorrection: Bool

    init(placeholder: String,
         text: Binding<String>,
         keyboardType: UIKeyboardType,
         capitalization: TextInputAutocapitalization = .never,
         disableAutocorrection: Bool = true) {
        self.placeholder = placeholder
        self._text = text
        self.keyboardType = keyboardType
        self.capitalization = capitalization
        self.disableAutocorrection = disableAutocorrection
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(disableAutocorrection)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .foregroundColor(.white)
            .tint(.purple)
    }
}
