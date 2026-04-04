//
//  ARStatusIndicator.swift
//  MedidorOticaApp
//
//  Indicador visual rapido de sessao AR, bootstrap do TrueDepth e deteccao de rosto.
//

import SwiftUI

/// Exibe o status resumido da sessao AR, do sensor TrueDepth e da deteccao de rosto.
struct ARStatusIndicator: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var verificationManager: VerificationManager

    var body: some View {
        HStack(spacing: 6) {
            statusDot(color: cameraManager.isUsingARSession ? .green : .red)
            statusDot(color: sensorColor)
            statusDot(color: verificationManager.faceDetected ? .green : .red)
        }
        .padding(.horizontal, 2)
    }

    private var sensorColor: Color {
        switch cameraManager.trueDepthState {
        case .sensorAlive:
            return .green
        case .recovering, .failed:
            return .orange
        default:
            return .red
        }
    }

    private func statusDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 11, height: 11)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.34), lineWidth: 0.6)
            )
    }
}
