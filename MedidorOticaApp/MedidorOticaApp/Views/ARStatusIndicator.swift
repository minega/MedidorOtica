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
        HStack(spacing: 4) {
            Circle()
                .fill(cameraManager.isUsingARSession ? Color.green : Color.red)
                .frame(width: 12, height: 12)

            Circle()
                .fill(sensorColor)
                .frame(width: 12, height: 12)

            Circle()
                .fill(verificationManager.faceDetected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
        }
        .padding(.horizontal, 4)
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
}
