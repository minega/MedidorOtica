//
//  PupilOverlay.swift
//  MedidorOticaApp
//
//  Desenha pontos vermelhos indicando a posição detectada das pupilas.
//

import SwiftUI

/// Visualização que exibe pontos nas posições das pupilas detectadas.
struct PupilOverlay: View {
    // MARK: - Propriedades
    @ObservedObject var verificationManager: VerificationManager

    /// Converte um ponto normalizado (0..1) das pupilas para a
    /// coordenada correta considerando cortes do preview.
    private func overlayPoint(_ point: CGPoint, in geo: GeometryProxy) -> CGPoint {
        let viewSize = geo.size
        let imageSize = verificationManager.cameraResolution

        guard imageSize != .zero else {
            return CGPoint(x: point.x * viewSize.width,
                           y: point.y * viewSize.height)
        }

        let viewAspect = viewSize.width / viewSize.height
        let imageAspect = imageSize.width / imageSize.height

        if imageAspect > viewAspect {
            // Corte nas laterais
            let scale = viewSize.height / imageSize.height
            let scaledWidth = imageSize.width * scale
            let xOffset = (scaledWidth - viewSize.width) / 2
            return CGPoint(x: point.x * scaledWidth - xOffset,
                           y: point.y * viewSize.height)
        } else {
            // Corte no topo ou base
            let scale = viewSize.width / imageSize.width
            let scaledHeight = imageSize.height * scale
            let yOffset = (scaledHeight - viewSize.height) / 2
            return CGPoint(x: point.x * viewSize.width,
                           y: point.y * scaledHeight - yOffset)
        }
    }

    // MARK: - Corpo da view
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let left = verificationManager.leftPupilPoint {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .position(overlayPoint(left, in: geo))
                }
                if let right = verificationManager.rightPupilPoint {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .position(overlayPoint(right, in: geo))
                }
            }
            .ignoresSafeArea() // Garante alinhamento com o preview da câmera
        }
        .allowsHitTesting(false)
    }
}
