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
                MeasurementDetailView(measurement: measurement)
                    .environmentObject(historyManager)
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
                
                Text("DP: \(measurement.formattedDistanciaPupilar)")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                
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
                // Compartilhamento da imagem e informações
                if let image = measurement.getImage() {
                    let text = "Cliente: \(measurement.clientName)\nDistância Pupilar: \(measurement.formattedDistanciaPupilar)\nData: \(measurement.formattedDate)"
                    ShareSheet(items: [image, text])
                }
            }
        }
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
            .environmentObject(HistoryManager.shared)
    }
}
