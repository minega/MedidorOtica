//
//  CameraComponents.swift
//  MedidorOticaApp
//
//  Componentes visuais reutilizáveis para a câmera
//

import SwiftUI
import AVFoundation
import ARKit

// MARK: - Preview da câmera
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        print("Criando visualização da câmera...")
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black
        
        // Cria a camada de preview da câmera
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.name = "CameraPreviewLayer"
        
        // Configura a orientação
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        
        // Adiciona a camada à view
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Atualiza o tamanho da view
        uiView.frame = UIScreen.main.bounds
        
        // Encontra a camada de preview existente
        if let layer = uiView.layer.sublayers?.first(where: { $0.name == "CameraPreviewLayer" }) as? AVCaptureVideoPreviewLayer {
            // Atualiza a sessão e o frame
            layer.session = session
            layer.frame = uiView.bounds
            
            // Atualiza a orientação
            if let connection = layer.connection, connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        } else {
            // Se não encontrou a camada, cria uma nova
            // Remove todas as camadas existentes primeiro
            uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            
            // Cria uma nova camada
            let newLayer = AVCaptureVideoPreviewLayer(session: session)
            newLayer.frame = uiView.bounds
            newLayer.videoGravity = .resizeAspectFill
            newLayer.name = "CameraPreviewLayer"
            
            if let connection = newLayer.connection, connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            
            uiView.layer.addSublayer(newLayer)
        }
    }
}

// MARK: - Preview para ARSession
/// Exibe a visualização de uma `ARSession` mantendo o `delegate` informado.
struct ARCameraPreview: UIViewRepresentable {
    let session: ARSession
    let delegate: ARSessionDelegate

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: UIScreen.main.bounds)
        view.session = session
        // Garante que o delegate permaneça atribuído ao CameraManager
        view.session.delegate = delegate
        view.automaticallyUpdatesLighting = true
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        uiView.session = session
        uiView.session.delegate = delegate
        uiView.frame = UIScreen.main.bounds
    }
}

// MARK: - Barra de progresso em forma de elipse
struct EllipticalProgressBar: Shape {
    var progress: CGFloat // 0.0 a 1.0
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Determina o ângulo final baseado no progresso (2*PI radianos = círculo completo)
        let endAngle = 2 * .pi * progress
        
        // Cria uma elipse parcial baseada no progresso
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radiusWidth = rect.width / 2
        let radiusHeight = rect.height / 2
        
        // Caso especial: quando o progresso é 0, não desenha nada
        if progress <= 0 {
            return path
        }
        
        // Caso especial: quando o progresso é completo, desenha uma elipse inteira
        if progress >= 1.0 {
            path.addEllipse(in: rect)
            return path
        }
        
        // Começa do topo (posição 12 horas = -π/2)
        let startAngle: CGFloat = -(.pi / 2)
        
        // Move para o ponto inicial
        let startX = center.x + radiusWidth * cos(startAngle)
        let startY = center.y + radiusHeight * sin(startAngle)
        path.move(to: CGPoint(x: startX, y: startY))
        
        // Adiciona arco baseado no progresso
        for angle in stride(from: startAngle, through: startAngle + endAngle, by: 0.01) {
            let x = center.x + radiusWidth * cos(angle)
            let y = center.y + radiusHeight * sin(angle)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        return path
    }
    
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
}

// MARK: - Destaque visual para a câmera
struct CameraHighlight: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Círculo pulsante ao redor da posição da câmera
            Circle()
                .stroke(Color.green, lineWidth: 2)
                .frame(width: 50, height: 50)
                .scaleEffect(isAnimating ? 1.3 : 1.0)
                .opacity(isAnimating ? 0.5 : 1.0)
                // Posiciona o destaque onde está a câmera/Dynamic Island
                .position(x: UIScreen.main.bounds.width / 2, y: 25) // Ajuste esta posição conforme necessário
                .animation(
                    Animation.easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: true),
                    value: isAnimating
                )
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Oval com barra de progresso
struct ProgressOval: View {
    /// Observa o `VerificationManager` para desenhar a barra de progresso dinâmicamente
    @ObservedObject var verificationManager: VerificationManager
    /// Define se a distância deve ser exibida abaixo do oval.
    var showDistance: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Oval completo branco como base
                Ellipse()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 300, height: 400)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Barra de progresso verde que vai se preenchendo
                // Calcula a porcentagem de preenchimento baseada nas verificações concluídas
                let completedCount = verificationManager.verifications.prefix(5).filter { $0.isChecked }.count
                let totalCount = 5.0 // Total de verificações que consideramos (1, 2, 3, 4 e 7)
                let progressPercentage = CGFloat(completedCount) / totalCount
                
                // Oval de progresso parcialmente desenhado
                EllipticalProgressBar(progress: progressPercentage)
                    .stroke(Color.green, lineWidth: 3)
                    .frame(width: 300, height: 400)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // Distância exibida abaixo do oval, caso habilitada
                if showDistance {
                    DistanceOverlay(verificationManager: verificationManager)
                        .position(x: geometry.size.width / 2,
                                  y: geometry.size.height / 2 + 230)
                }
            }
        }
    }
}
