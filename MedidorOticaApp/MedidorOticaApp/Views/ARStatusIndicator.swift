//
//  ARStatusIndicator.swift
//  MedidorOticaApp
//
//  Indicador visual de status da sessão AR, detecção de rosto e da armação.
//  Exibe três bolinhas: ARSession, rosto detectado e armação detectada.
//
import SwiftUI

/// Exibe o status da sessão AR, da detecção de rosto e da armação.
/// A ordem das bolinhas é: ARSession, rosto detectado e armação detectada.
struct ARStatusIndicator: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var verificationManager: VerificationManager

    // MARK: - View
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(cameraManager.isUsingARSession ? Color.green : Color.red)
                .frame(width: 12, height: 12)

            Circle()
                // Verde quando o rosto é detectado, vermelho caso contrário
                .fill(verificationManager.faceDetected ? Color.green : Color.red)
                .frame(width: 12, height: 12)

            Circle()
                // Verde quando a armação é detectada, vermelho caso contrário
                .fill(verificationManager.frameDetected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
        }
        .padding(.horizontal, 4)
    }
}

