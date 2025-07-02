//
//  MeasurementResultView.swift
//  MedidorOticaApp
//
//  Tela de preview pós-captura que mostra a imagem com as medidas
//

import SwiftUI

struct MeasurementResultView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyManager: HistoryManager
    
    @State private var clientName: String = ""
    @State private var distanciaPupilar: Double = 65.0
    @State private var showingShareSheet = false
    @State private var showingAdjustmentView = false
    @State private var showingSaveAlert = false
    @State private var isSaved = false
    
    let capturedImage: UIImage
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Imagem capturada com medidas sobrepostas
                    ZStack {
                        Image(uiImage: capturedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(12)
                            .padding(.horizontal)
                        
                        // Pontos de medição (simulados)
                        GeometryReader { geometry in
                            let width = geometry.size.width
                            let height = geometry.size.height
                            
                            ZStack {
                                // Ponto esquerdo
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                    .position(x: width * 0.35, y: height * 0.5)
                                
                                // Ponto direito
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                    .position(x: width * 0.65, y: height * 0.5)
                                
                                // Linha entre os pontos
                                Path { path in
                                    path.move(to: CGPoint(x: width * 0.35, y: height * 0.5))
                                    path.addLine(to: CGPoint(x: width * 0.65, y: height * 0.5))
                                }
                                .stroke(Color.yellow, lineWidth: 2)
                            }
                        }
                    }
                    .padding(.top)
                    
                    // Informações da medição
                    VStack(spacing: 15) {
                        Text("Distância Pupilar")
                            .font(.headline)
                        
                        Text(String(format: "%.1f mm", distanciaPupilar))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        
                        // Ajuste manual da distância
                        HStack {
                            Text("Ajuste fino:")
                                .font(.subheadline)
                            
                            Slider(value: $distanciaPupilar, in: 50...80, step: 0.1)
                                .accentColor(.blue)
                            
                            Text(String(format: "%.1f", distanciaPupilar))
                                .font(.subheadline)
                                .frame(width: 40)
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Campo para nome do cliente
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nome do Cliente")
                            .font(.headline)
                        
                        TextField("Digite o nome do cliente", text: $clientName)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .autocapitalization(.words)
                    }
                    .padding(.horizontal)
                    
                    // Botões de ação
                    VStack(spacing: 15) {
                        // Botão para ajuste manual
                        Button(action: {
                            showingAdjustmentView = true
                        }) {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                Text("Ajuste Manual dos Pontos")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
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
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
                        // Botão para salvar
                        Button(action: {
                            saveMeasurement()
                        }) {
                            HStack {
                                Image(systemName: isSaved ? "checkmark.circle" : "square.and.arrow.down")
                                Text(isSaved ? "Salvo no Histórico" : "Salvar no Histórico")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isSaved ? Color.gray : Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isSaved)
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
                .padding(.bottom, 30)
            }
            .navigationBarTitle("Resultado da Medição", displayMode: .inline)
            .navigationBarItems(
                leading: Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.title3)
                }
            )
            .sheet(isPresented: $showingShareSheet) {
                // Compartilhamento da imagem com medidas
                let image = renderMeasurementImage()
                let text = "Medição de Distância Pupilar: \(String(format: "%.1f mm", distanciaPupilar))"
                ShareSheet(items: [image, text])
            }
            .alert(isPresented: $showingSaveAlert) {
                Alert(
                    title: Text("Nome do Cliente"),
                    message: Text("Por favor, insira o nome do cliente antes de salvar."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    // Salva a medição no histórico
    private func saveMeasurement() {
        guard !clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showingSaveAlert = true
            return
        }
        
        let measurement = Measurement(
            clientName: clientName,
            distanciaPupilar: distanciaPupilar,
            image: capturedImage
        )
        
        historyManager.addMeasurement(measurement)
        isSaved = true
    }
    
    // Renderiza a imagem com as medidas para compartilhamento
    private func renderMeasurementImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: capturedImage.size)
        
        let image = renderer.image { context in
            // Desenha a imagem original
            capturedImage.draw(in: CGRect(origin: .zero, size: capturedImage.size))
            
            let ctx = context.cgContext
            
            // Configura o estilo de desenho
            ctx.setStrokeColor(UIColor.yellow.cgColor)
            ctx.setLineWidth(5)
            
            // Posições dos pontos (simuladas)
            let leftX = capturedImage.size.width * 0.35
            let rightX = capturedImage.size.width * 0.65
            let y = capturedImage.size.height * 0.5
            
            // Desenha a linha entre os pontos
            ctx.move(to: CGPoint(x: leftX, y: y))
            ctx.addLine(to: CGPoint(x: rightX, y: y))
            ctx.strokePath()
            
            // Desenha os pontos
            ctx.setFillColor(UIColor.red.cgColor)
            ctx.fillEllipse(in: CGRect(x: leftX - 5, y: y - 5, width: 10, height: 10))
            ctx.fillEllipse(in: CGRect(x: rightX - 5, y: y - 5, width: 10, height: 10))
            
            // Adiciona o texto com a medida
            let text = "DP: \(String(format: "%.1f mm", distanciaPupilar))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 36),
                .foregroundColor: UIColor.white,
                .backgroundColor: UIColor.black.withAlphaComponent(0.5)
            ]
            
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (capturedImage.size.width - textSize.width) / 2,
                y: y + 20,
                width: textSize.width,
                height: textSize.height
            )
            
            text.draw(in: textRect, withAttributes: attributes)
        }
        
        return image
    }
}

// View para compartilhamento
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct MeasurementResultView_Previews: PreviewProvider {
    static var previews: some View {
        MeasurementResultView(capturedImage: UIImage(systemName: "person.fill")!)
            .environmentObject(HistoryManager.shared)
    }
}
