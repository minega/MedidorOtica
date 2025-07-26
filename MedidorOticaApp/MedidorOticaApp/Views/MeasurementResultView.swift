//
//  MeasurementResultView.swift
//  MedidorOticaApp
//
//  Tela de preview pós-captura que mostra a imagem com as medidas
//

import SwiftUI
import Vision

struct MeasurementResultView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyManager: HistoryManager

    // MARK: - Propriedades
    @State private var clientName: String = ""
    @State private var distanciaPupilar: Double = 65.0
    @State private var showingShareSheet = false
    @State private var showingAdjustmentView = false
    @State private var showingSaveAlert = false
    @State private var isSaved = false

    /// Pontos detectados automaticamente na imagem
    @State private var landmarks: FrameLandmarks?

    let capturedImage: UIImage

    // MARK: - View
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

                        // Pontos detectados automaticamente
                        if let landmarks {
                            GeometryReader { geo in
                                let w = geo.size.width
                                let h = geo.size.height

                                // Linhas de extremidades
                                Path { path in
                                    path.move(to: CGPoint(x: landmarks.leftLineX * w, y: 0))
                                    path.addLine(to: CGPoint(x: landmarks.leftLineX * w, y: h))
                                }
                                .stroke(Color.green, lineWidth: 2)

                                Path { path in
                                    path.move(to: CGPoint(x: landmarks.rightLineX * w, y: 0))
                                    path.addLine(to: CGPoint(x: landmarks.rightLineX * w, y: h))
                                }
                                .stroke(Color.green, lineWidth: 2)

                                Path { path in
                                    path.move(to: CGPoint(x: 0, y: landmarks.topLineY * h))
                                    path.addLine(to: CGPoint(x: w, y: landmarks.topLineY * h))
                                }
                                .stroke(Color.green, lineWidth: 2)

                                Path { path in
                                    path.move(to: CGPoint(x: 0, y: landmarks.bottomLineY * h))
                                    path.addLine(to: CGPoint(x: w, y: landmarks.bottomLineY * h))
                                }
                                .stroke(Color.green, lineWidth: 2)

                                // Pupilas
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                    .position(x: landmarks.leftPupil.x * w, y: landmarks.leftPupil.y * h)

                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                    .position(x: landmarks.rightPupil.x * w, y: landmarks.rightPupil.y * h)
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

                        if let landmarks {
                            MeasurementTable(landmarks: landmarks, imageSize: capturedImage.size)
                        }
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
            .onAppear {
                detectLandmarks()
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
            .sheet(isPresented: $showingAdjustmentView) {
                if let _ = landmarks {
                    ManualAdjustmentView(
                        landmarks: Binding(
                            get: { landmarks! },
                            set: { landmarks = $0 }
                        ),
                        image: capturedImage
                    )
                }
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
    
    // MARK: - Métodos

    /// Salva a medição no histórico
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
        
        Task {
            await historyManager.addMeasurement(measurement)
            isSaved = true
        }
    }
    
    /// Renderiza a imagem com as medidas para compartilhamento
    private func renderMeasurementImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: capturedImage.size)

        let image = renderer.image { context in
            // Desenha a imagem original
            capturedImage.draw(in: CGRect(origin: .zero, size: capturedImage.size))

            let ctx = context.cgContext
            ctx.setStrokeColor(UIColor.yellow.cgColor)
            ctx.setLineWidth(5)

            // Utiliza os pontos detectados para desenhar a linha e marcadores
            if let marks = landmarks {
                let w = capturedImage.size.width
                let h = capturedImage.size.height

                let leftX = marks.leftPupil.x * w
                let rightX = marks.rightPupil.x * w
                let y = marks.leftPupil.y * h

                ctx.move(to: CGPoint(x: leftX, y: y))
                ctx.addLine(to: CGPoint(x: rightX, y: y))
                ctx.strokePath()

                ctx.setFillColor(UIColor.red.cgColor)
                ctx.fillEllipse(in: CGRect(x: leftX - 5, y: y - 5, width: 10, height: 10))
                ctx.fillEllipse(in: CGRect(x: rightX - 5, y: y - 5, width: 10, height: 10))
            }

            // Texto com a medida final
            let text = "DP: \(String(format: "%.1f mm", distanciaPupilar))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 36),
                .foregroundColor: UIColor.white,
                .backgroundColor: UIColor.black.withAlphaComponent(0.5)
            ]

            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (capturedImage.size.width - textSize.width) / 2,
                y: capturedImage.size.height * 0.55,
                width: textSize.width,
                height: textSize.height
            )

            text.draw(in: textRect, withAttributes: attributes)
        }

        return image
    }

    /// Detecta automaticamente pontos relevantes utilizando Vision
    private func detectLandmarks() {
        landmarks = FrameAnalyzer.analyze(image: capturedImage)
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

// MARK: - Preview
struct MeasurementResultView_Previews: PreviewProvider {
    static var previews: some View {
        MeasurementResultView(capturedImage: UIImage(systemName: "person.fill")!)
            .environmentObject(HistoryManager.shared)
    }
}
