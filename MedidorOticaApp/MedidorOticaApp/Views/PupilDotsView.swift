//
//  PupilDotsView.swift
//  MedidorOticaApp
//
//  Exibe pontos vermelhos representando as pupilas detectadas.
//

import SwiftUI

/// Overlay simples para indicar a posição das pupilas.
struct PupilDotsView: View {
    @ObservedObject var verificationManager: VerificationManager

    private func convert(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let left = verificationManager.leftPupilPoint {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .position(convert(left, in: geo.size))
                }
                if let right = verificationManager.rightPupilPoint {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .position(convert(right, in: geo.size))
                }
            }
            .allowsHitTesting(false)
        }
    }
}
