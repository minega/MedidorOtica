//
//  PupilOverlay.swift
//  MedidorOticaApp
//
//  Sobreposição responsável por destacar as pupilas detectadas na câmera.
//

import SwiftUI

/// Desenha círculos alinhados às pupilas rastreadas pelo `VerificationManager`.
struct PupilOverlay: View {
    /// Gerenciador das verificações com as coordenadas das pupilas.
    @ObservedObject var verificationManager: VerificationManager
    /// Gerenciador da câmera para tratar espelhamento do preview.
    @ObservedObject var cameraManager: CameraManager

    /// Tamanho padrão dos indicadores desenhados sobre a imagem.
    private let indicatorSize: CGFloat = 18

    // MARK: - View Body

    var body: some View {
        GeometryReader { geometry in
            if let centers = verificationManager.pupilCenters {
                let normalizedPoints = [centers.left, centers.right]
                ForEach(normalizedPoints.indices, id: \.self) { index in
                    let normalizedPoint = normalizedPoints[index]
                    let position = convertToScreenPoint(normalizedPoint,
                                                        geometrySize: geometry.size)

                    PupilIndicator(index: index,
                                   position: position,
                                   size: indicatorSize)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Conversões de Coordenadas

    /// Converte um ponto normalizado (0...1) para coordenadas absolutas já com o espelhamento aplicado quando necessário.
    private func convertToScreenPoint(_ normalizedPoint: CGPoint, geometrySize: CGSize) -> CGPoint {
        let mirroredX = cameraManager.cameraPosition == .front ? 1 - normalizedPoint.x : normalizedPoint.x
        return CGPoint(x: mirroredX * geometrySize.width,
                       y: normalizedPoint.y * geometrySize.height)
    }
}

struct PupilOverlay_Previews: PreviewProvider {
    static var previews: some View {
        PupilOverlay(verificationManager: VerificationManager.shared,
                     cameraManager: CameraManager.shared)
            .background(Color.black)
    }
}

// MARK: - PupilIndicator

/// Indicador visual individual que destaca uma das pupilas detectadas.
fileprivate struct PupilIndicator: View {
    /// Índice que identifica se o indicador representa o olho esquerdo ou direito.
    let index: Int
    /// Posição absoluta onde o círculo deve ser desenhado na tela.
    let position: CGPoint
    /// Tamanho do círculo apresentado como indicador.
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color.red.opacity(0.85))
            .frame(width: size, height: size)
            .position(position)
            .shadow(color: .red.opacity(0.45), radius: 4)
            .accessibilityLabel(accessibilityText)
    }

    // MARK: - Acessibilidade

    /// Texto falado pelo VoiceOver para indicar qual pupila está destacada.
    private var accessibilityText: Text {
        let eyeName = index == 0 ? "esquerda" : "direita"
        return Text("Indicador de pupila \(eyeName)")
    }
}
