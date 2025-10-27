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

    var body: some View {
        GeometryReader { geometry in
            if let centers = verificationManager.pupilCenters {
                let points = [centers.left, centers.right]
                ForEach(Array(points.enumerated()), id: \.offset) { item in
                    let index = item.offset
                    let normalized = item.element
                    let mirroredX = cameraManager.cameraPosition == .front ? 1 - normalized.x : normalized.x
                    let position = CGPoint(x: mirroredX * geometry.size.width,
                                           y: normalized.y * geometry.size.height)

                    Circle()
                        .fill(Color.red.opacity(0.85))
                        .frame(width: indicatorSize, height: indicatorSize)
                        .position(position)
                        .shadow(color: .red.opacity(0.45), radius: 4)
                        .accessibilityLabel(Text("Indicador de pupila \(index == 0 ? \"esquerda\" : \"direita\")"))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct PupilOverlay_Previews: PreviewProvider {
    static var previews: some View {
        PupilOverlay(verificationManager: VerificationManager.shared,
                     cameraManager: CameraManager.shared)
            .background(Color.black)
    }
}
