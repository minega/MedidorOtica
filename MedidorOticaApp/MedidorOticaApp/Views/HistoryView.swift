//
//  HistoryView.swift
//  MedidorOticaApp
//
//  Tela de histórico que mostra as medições salvas
//

import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyManager: HistoryManager
    @State private var selectedMeasurement: Measurement?
    @State private var showingDetail = false
    @State private var editingMeasurement: Measurement?

    var body: some View {
        VStack {
            // Cabeçalho
            HStack {
                Text("Histórico de Medições")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
            }
            .padding()
            
            if historyManager.measurements.isEmpty {
                // Mensagem quando não há medições
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 70))
                        .foregroundColor(.gray)
                    
                    Text("Nenhuma medição salva")
                        .font(.title3)
                        .foregroundColor(.gray)
                    
                    Text("As medições salvas aparecerão aqui")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxHeight: .infinity)
            } else {
                // Lista de medições
                List {
                    ForEach(historyManager.measurements) { measurement in
                        MeasurementRow(measurement: measurement)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMeasurement = measurement
                                showingDetail = true
                            }
                    }
                    .onDelete(perform: deleteMeasurement)
                }
                .listStyle(PlainListStyle())
            }
        }
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
                                          calibration: measurement.postCaptureCalibration)
                PostCaptureFlowView(capturedPhoto: photo,
                                    existingMeasurement: measurement,
                                    onRetake: {
                                        editingMeasurement = nil
                                    })
                .environmentObject(historyManager)
            } else {
                Text("Imagem indisponível para edição")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black)
            }
        }
    }
    
    // Remove uma medição do histórico
    private func deleteMeasurement(at offsets: IndexSet) {
        for index in offsets {
            Task { await historyManager.removeMeasurement(at: index) }
        }
    }
}

// Linha da lista de medições
struct MeasurementRow: View {
    let measurement: Measurement
    
    var body: some View {
        HStack(spacing: 15) {
            // Miniatura da imagem
            if let image = measurement.getImage() {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }
            
            // Informações da medição
            VStack(alignment: .leading, spacing: 4) {
                Text(measurement.clientName)
                    .font(.headline)

                if !measurement.orderNumber.isEmpty {
                    Text("OS: \(measurement.orderNumber)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Text("DP: \(measurement.formattedDistanciaPupilar)")
                    .font(.subheadline)
                    .foregroundColor(.blue)

                if let metrics = measurement.postCaptureMetrics {
                    Text("Ponte: \(String(format: "%.1f mm", metrics.ponte))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Text(measurement.formattedDate)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
    }
}

// Tela de detalhes da medição
struct MeasurementDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyManager: HistoryManager
    @State private var showingShareSheet = false

    let measurement: Measurement
    let onEdit: (Measurement) -> Void
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Imagem da medição
                    if let image = measurement.getImage() {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(12)
                            .padding(.horizontal)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(4/3, contentMode: .fit)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                            )
                            .padding(.horizontal)
                    }
                    
                    // Informações da medição
                    VStack(spacing: 15) {
                        // Nome do cliente
                        HStack {
                            Text("Cliente:")
                                .font(.headline)
                                .foregroundColor(.gray)
                            
                            Spacer()
                            
                            Text(measurement.clientName)
                                .font(.headline)
                        }
                        .padding(.horizontal)
                        
                        Divider()
                        
                        // Distância pupilar
                        HStack {
                            Text("Distância Pupilar:")
                                .font(.headline)
                                .foregroundColor(.gray)

                            Spacer()

                            Text(measurement.formattedDistanciaPupilar)
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal)

                        if !measurement.orderNumber.isEmpty {
                            Divider()

                            HStack {
                                Text("Número da OS:")
                                    .font(.headline)
                                    .foregroundColor(.gray)

                                Spacer()

                                Text(measurement.orderNumber)
                                    .font(.headline)
                            }
                            .padding(.horizontal)
                        }

                        Divider()

                        // Data da medição
                        HStack {
                            Text("Data:")
                                .font(.headline)
                                .foregroundColor(.gray)

                            Spacer()

                            Text(measurement.formattedDate)
                                .font(.headline)
                        }
                        .padding(.horizontal)

                        if let metrics = measurement.postCaptureMetrics {
                            Divider()

                            VStack(alignment: .leading, spacing: 10) {
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
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Botão para compartilhar
                    Button(action: {
                        showingShareSheet = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Compartilhar")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }

                    // Botão para editar etapas
                    if measurement.getImage() != nil {
                        Button(action: {
                            dismiss()
                            onEdit(measurement)
                        }) {
                            HStack {
                                Image(systemName: "pencil.circle")
                                Text("Editar etapas")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationBarTitle("Detalhes da Medição", displayMode: .inline)
            .navigationBarItems(
                trailing: Button(action: {
                    dismiss()
                }) {
                    Text("Fechar")
                }
            )
            .sheet(isPresented: $showingShareSheet) {
                if let items = MeasurementShareFormatter().makeItems(for: measurement) {
                    ShareSheet(items: items)
                } else {
                    ShareUnavailableView()
                }
            }
        }
    }

    private func metricRow(title: String, value: Double) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)

            Spacer()

            Text(String(format: "%.1f mm", value))
                .font(.subheadline)
                .foregroundColor(.blue)
        }
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
            .environmentObject(HistoryManager.shared)
    }
}

// MARK: - Sharing Helpers
/// Formatter responsável por montar o resumo textual da medição para compartilhamento.
fileprivate struct MeasurementShareFormatter {
    /// Monta os itens a serem compartilhados na folha do sistema.
    /// - Parameter measurement: Medição selecionada pelo usuário.
    /// - Returns: Array com a imagem da medição e o texto resumido.
    func makeItems(for measurement: Measurement) -> [Any]? {
        guard let image = measurement.getImage() else { return nil }
        return [image, makeSummary(for: measurement)]
    }

    /// Cria o texto formatado com todas as métricas relevantes.
    /// - Parameter measurement: Medição utilizada como fonte.
    /// - Returns: Texto pronto para ser compartilhado.
    func makeSummary(for measurement: Measurement) -> String {
        var lines: [String] = []
        lines.reserveCapacity(9)

        lines.append("Cliente: \(measurement.clientName)")

        if !measurement.orderNumber.isEmpty {
            lines.append("OS: \(measurement.orderNumber)")
        }

        lines.append("Distância Pupilar: \(measurement.formattedDistanciaPupilar)")
        lines.append("Data: \(measurement.formattedDate)")

        if let metrics = measurement.postCaptureMetrics {
            lines.append("Valores em mm — OD / OE")
            lines.append(contentsOf: metrics.compactSummaryLines())
        }

        return lines.joined(separator: "\n")
    }
}

/// Visão exibida quando a medição não possui imagem para compartilhar.
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
