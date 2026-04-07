//
//  HistoryView.swift
//  MedidorOticaApp
//
//  Tela de historico com cards em vidro para consultar, compartilhar e editar medicoes salvas.
//

import SwiftUI

struct HistoryView: View {
    // MARK: - Dependencias
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyManager: HistoryManager

    // MARK: - Estado
    @State private var selectedMeasurement: Measurement?
    @State private var showingDetail = false
    @State private var editingMeasurement: Measurement?

    // MARK: - Tema
    private let textColor = Color(red: 0.15, green: 0.28, blue: 0.43)
    private let accentColor = Color(red: 0.28, green: 0.57, blue: 0.91)

    // MARK: - View
    var body: some View {
        ZStack {
            historyBackground

            VStack(spacing: 18) {
                header

                if historyManager.measurements.isEmpty {
                    emptyState
                } else {
                    measurementsList
                }
            }
            .padding(.top, 18)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingDetail) {
            if let measurement = selectedMeasurement {
                MeasurementDetailView(measurement: measurement) { measurement in
                    if measurement.getImage() != nil {
                        editingMeasurement = measurement
                    }
                }
                .environmentObject(historyManager)
            }
        }
        .fullScreenCover(item: $editingMeasurement) { measurement in
            if let image = measurement.getImage() {
                let photo = CapturedPhoto(image: image,
                                          calibration: measurement.postCaptureCalibration,
                                          localCalibration: measurement.postCaptureLocalCalibration ?? .empty,
                                          captureCentralPoint: measurement.postCaptureCaptureCentralPoint,
                                          eyeGeometrySnapshot: measurement.postCaptureEyeGeometrySnapshot)
                PostCaptureFlowView(capturedPhoto: photo,
                                    existingMeasurement: measurement,
                                    onRetake: {
                                        editingMeasurement = nil
                                    })
                .environmentObject(historyManager)
            } else {
                Text("Imagem indisponivel para edicao")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black)
            }
        }
    }
}

// MARK: - Layout
private extension HistoryView {
    /// Mantem o historico claro e leve, alinhado com a tela inicial.
    var historyBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.99, blue: 1.00),
                    Color(red: 0.91, green: 0.96, blue: 1.00),
                    Color(red: 0.95, green: 0.99, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.96))
                .frame(width: 380, height: 380)
                .blur(radius: 56)
                .offset(x: -120, y: -250)

            Circle()
                .fill(Color.cyan.opacity(0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 82)
                .offset(x: 150, y: -80)

            Circle()
                .fill(Color.blue.opacity(0.12))
                .frame(width: 340, height: 340)
                .blur(radius: 94)
                .offset(x: 140, y: 250)
        }
    }

    /// Destaca o titulo e mantem o fechamento facil no topo.
    var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("HISTORICO")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .tracking(2.8)
                    .foregroundStyle(textColor)

                Text("Consulte, compartilhe e reabra medicoes salvas.")
                    .font(.subheadline)
                    .foregroundStyle(textColor.opacity(0.72))
            }

            Spacer()

            Button(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(textColor)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)
            .appGlassSurface(cornerRadius: 18,
                             borderOpacity: 0.70,
                             tintOpacity: 0.22,
                             interactive: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
    }

    /// Reaproveita a lista do sistema, mas com cards personalizados e fundo transparente.
    var measurementsList: some View {
        List {
            ForEach(historyManager.measurements) { measurement in
                Button(action: {
                    selectedMeasurement = measurement
                    showingDetail = true
                }) {
                    MeasurementRow(measurement: measurement)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }
            .onDelete(perform: deleteMeasurement)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    /// Exibe um estado vazio mais convidativo quando ainda nao ha medicoes.
    var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(accentColor)

            Text("Nenhuma medicao salva")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(textColor)

            Text("As medicoes concluidas aparecerao aqui para consulta e nova revisao.")
                .font(.body)
                .foregroundStyle(textColor.opacity(0.70))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 34)
        .appGlassSurface(cornerRadius: 34,
                         borderOpacity: 0.62,
                         tintOpacity: 0.22,
                         interactive: false)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    /// Remove uma medicao do historico usando o comportamento ja existente.
    private func deleteMeasurement(at offsets: IndexSet) {
        for index in offsets {
            Task { await historyManager.removeMeasurement(at: index) }
        }
    }
}

// MARK: - Row
struct MeasurementRow: View {
    let measurement: Measurement

    private let titleColor = Color(red: 0.15, green: 0.28, blue: 0.43)
    private let accentColor = Color(red: 0.27, green: 0.56, blue: 0.91)

    var body: some View {
        HStack(spacing: 16) {
            thumbnail

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Text(measurement.clientName)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(titleColor)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    if !measurement.orderNumber.isEmpty {
                        HistoryBadge(text: "OS \(measurement.orderNumber)")
                    }
                }

                HStack(spacing: 10) {
                    HistoryAccentBadge(text: measurement.formattedDistanciaPupilar)

                    if let metrics = measurement.postCaptureMetrics {
                        HistoryBadge(text: "Ponte \(String(format: "%.1f mm", metrics.ponte))")
                    }
                }

                Text(measurement.formattedDate)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(titleColor.opacity(0.68))
            }

            Image(systemName: "chevron.right")
                .font(.headline.weight(.bold))
                .foregroundStyle(titleColor.opacity(0.55))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.32), in: Circle())
        }
        .padding(16)
        .appGlassSurface(cornerRadius: 30,
                         borderOpacity: 0.56,
                         tintOpacity: 0.22,
                         interactive: false)
        .shadow(color: accentColor.opacity(0.08), radius: 14, x: 0, y: 10)
    }

    /// Mantem a miniatura nitida e com proporcao agradavel.
    @ViewBuilder
    private var thumbnail: some View {
        if let image = measurement.getImage() {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.46), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.38))
                .frame(width: 84, height: 84)
                .overlay(
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(titleColor.opacity(0.45))
                )
        }
    }
}

// MARK: - Detail
struct MeasurementDetailView: View {
    // MARK: - Dependencias
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyManager: HistoryManager

    // MARK: - Estado
    @State private var showingShareSheet = false

    let measurement: Measurement
    let onEdit: (Measurement) -> Void

    // MARK: - Tema
    private let textColor = Color(red: 0.15, green: 0.28, blue: 0.43)
    private let accentColor = Color(red: 0.27, green: 0.56, blue: 0.91)

    var body: some View {
        NavigationStack {
            ZStack {
                detailBackground

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        imageCard
                        summaryCard

                        if let metrics = measurement.postCaptureMetrics {
                            metricsCard(metrics: metrics)
                        }

                        actionsCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Detalhes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar", action: dismiss.callAsFunction)
                        .foregroundStyle(textColor)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let items = MeasurementShareFormatter().makeItems(for: measurement) {
                    ShareSheet(items: items)
                } else {
                    ShareUnavailableView()
                }
            }
        }
    }
}

// MARK: - Detail Layout
private extension MeasurementDetailView {
    /// Mantem o detalhe no mesmo universo claro do historico.
    var detailBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.99, blue: 1.00),
                Color(red: 0.91, green: 0.96, blue: 1.00),
                Color(red: 0.95, green: 0.99, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    /// Destaca a imagem capturada em um painel maior.
    @ViewBuilder
    var imageCard: some View {
        Group {
            if let image = measurement.getImage() {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.32))
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 42))
                            .foregroundStyle(textColor.opacity(0.38))
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .appGlassSurface(cornerRadius: 34,
                         borderOpacity: 0.58,
                         tintOpacity: 0.20,
                         interactive: false)
        .shadow(color: accentColor.opacity(0.08), radius: 18, x: 0, y: 12)
    }

    /// Resume os dados principais da medicao em linhas claras.
    var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Resumo da medicao")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(textColor)

            detailRow(title: "Cliente", value: measurement.clientName)
            detailRow(title: "DNP total", value: measurement.formattedDistanciaPupilar, emphasize: true)

            if !measurement.orderNumber.isEmpty {
                detailRow(title: "Numero da OS", value: measurement.orderNumber)
            }

            detailRow(title: "Data", value: measurement.formattedDate)
        }
        .padding(22)
        .appGlassSurface(cornerRadius: 30,
                         borderOpacity: 0.56,
                         tintOpacity: 0.20,
                         interactive: false)
    }

    /// Organiza as metricas finais em uma lista longa mas legivel.
    func metricsCard(metrics: PostCaptureMetrics) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Metricas")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(textColor)

            metricRow(title: "Horizontal Maior OD", value: metrics.rightEye.horizontalMaior)
            metricRow(title: "Horizontal Maior OE", value: metrics.leftEye.horizontalMaior)
            metricRow(title: "Vertical Maior OD", value: metrics.rightEye.verticalMaior)
            metricRow(title: "Vertical Maior OE", value: metrics.leftEye.verticalMaior)
            metricRow(title: "Ponte da Armacao", value: metrics.ponte)
            metricRow(title: "DNP Validada Perto OD", value: metrics.validatedDNP.rightNear)
            metricRow(title: "DNP Validada Perto OE", value: metrics.validatedDNP.leftNear)
            metricRow(title: "DNP Validada Longe OD", value: metrics.validatedDNP.rightFar)
            metricRow(title: "DNP Validada Longe OE", value: metrics.validatedDNP.leftFar)
            metricRow(title: "DNP Nariz Perto OD", value: metrics.noseDNP.rightNear)
            metricRow(title: "DNP Nariz Perto OE", value: metrics.noseDNP.leftNear)
            metricRow(title: "DNP Ponte Perto OD", value: metrics.bridgeDNP.rightNear)
            metricRow(title: "DNP Ponte Perto OE", value: metrics.bridgeDNP.leftNear)
            metricRow(title: "Altura Pupilar OD", value: metrics.rightEye.alturaPupilar)
            metricRow(title: "Altura Pupilar OE", value: metrics.leftEye.alturaPupilar)
            metricRow(title: "DNP Total Perto", value: metrics.distanciaPupilarTotal)
            metricRow(title: "DNP Total Longe", value: metrics.distanciaPupilarTotalFar)

            if let confidenceReason = metrics.farDNPConfidenceReason,
               metrics.farDNPConfidence < 0.65 {
                Text("Obs.: \(confidenceReason)")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(22)
        .appGlassSurface(cornerRadius: 30,
                         borderOpacity: 0.56,
                         tintOpacity: 0.20,
                         interactive: false)
    }

    /// Mantem as acoes principais sempre acessiveis no final do detalhe.
    var actionsCard: some View {
        VStack(spacing: 12) {
            Button(action: { showingShareSheet = true }) {
                Label("Compartilhar", systemImage: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 58)
            }
            .buttonStyle(.plain)
            .appGlassSurface(cornerRadius: 24,
                             borderOpacity: 0.72,
                             tintOpacity: 0.20,
                             interactive: true)

            if measurement.getImage() != nil {
                Button(action: {
                    dismiss()
                    onEdit(measurement)
                }) {
                    Label("Editar etapas", systemImage: "pencil.circle")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(textColor)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 58)
                }
                .buttonStyle(.plain)
                .appGlassSurface(cornerRadius: 24,
                                 borderOpacity: 0.72,
                                 tintOpacity: 0.24,
                                 interactive: true)
            }
        }
    }

    func detailRow(title: String, value: String, emphasize: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(textColor.opacity(0.70))

            Spacer(minLength: 10)

            Text(value)
                .font(.system(size: emphasize ? 19 : 17,
                              weight: emphasize ? .bold : .semibold,
                              design: .rounded))
                .foregroundStyle(emphasize ? accentColor : textColor)
                .multilineTextAlignment(.trailing)
        }
    }

    func metricRow(title: String, value: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(textColor.opacity(0.72))

            Spacer(minLength: 10)

            Text(String(format: "%.1f mm", value))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(accentColor)
        }
    }
}

// MARK: - Badges
private struct HistoryBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(red: 0.16, green: 0.28, blue: 0.42))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.46), in: Capsule())
    }
}

private struct HistoryAccentBadge: View {
    let text: String

    var body: some View {
        Text("DNP \(text)")
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(red: 0.22, green: 0.46, blue: 0.83))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.blue.opacity(0.10), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.blue.opacity(0.18), lineWidth: 1)
            )
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
            .environmentObject(HistoryManager.shared)
    }
}

// MARK: - Sharing Helpers
/// Formatter responsavel por montar o resumo textual da medicao para compartilhamento.
fileprivate struct MeasurementShareFormatter {
    /// Monta os itens a serem compartilhados na folha do sistema.
    /// - Parameter measurement: Medicao selecionada pelo usuario.
    /// - Returns: Array com a imagem da medicao e o texto resumido.
    func makeItems(for measurement: Measurement) -> [Any]? {
        guard let image = measurement.getImage() else { return nil }
        return [image, makeSummary(for: measurement)]
    }

    /// Cria o texto formatado com todas as metricas relevantes.
    /// - Parameter measurement: Medicao utilizada como fonte.
    /// - Returns: Texto pronto para ser compartilhado.
    func makeSummary(for measurement: Measurement) -> String {
        var lines: [String] = []
        lines.reserveCapacity(9)

        lines.append("Cliente: \(measurement.clientName)")

        if !measurement.orderNumber.isEmpty {
            lines.append("OS: \(measurement.orderNumber)")
        }

        lines.append("DNP total: \(measurement.formattedDistanciaPupilar)")
        lines.append("Data: \(measurement.formattedDate)")

        if let metrics = measurement.postCaptureMetrics {
            lines.append("Valores em mm - OD / OE")
            lines.append(contentsOf: metrics.compactSummaryLines())
        }

        return lines.joined(separator: "\n")
    }
}

/// Visao exibida quando a medicao nao possui imagem para compartilhar.
fileprivate struct ShareUnavailableView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("Nada para compartilhar agora.")
                .font(.headline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Text("Capture nova foto para compartilhar.")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.12))
    }
}
