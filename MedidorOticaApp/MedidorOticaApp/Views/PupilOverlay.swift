//
//  PupilOverlay.swift
//  MedidorOticaApp
//
//  Desenha pontos vermelhos indicando a posição detectada das pupilas.
//

import SwiftUI

/// Overlay para depuração da detecção de pupilas.
struct PupilOverlay: View {
    @ObservedObject var verificationManager: VerificationManager

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let left = verificationManager.leftPupilPoint {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .position(x: left.x * geo.size.width,
                                  y: left.y * geo.size.height)
                }
                if let right = verificationManager.rightPupilPoint {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .position(x: right.x * geo.size.width,
                                  y: right.y * geo.size.height)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
