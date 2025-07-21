//
//  ARStatusIndicator.swift
//  MedidorOticaApp
//
//  Indicador visual de status da sessão AR, detecção de rosto e direção do olhar.
//  Exibe três bolinhas: ARSession, rosto detectado e olhar para a câmera.
//
import SwiftUI

/// Exibe o status da sessão AR, da detecção de rosto e do olhar.
/// A ordem das bolinhas é: ARSession, rosto detectado e olhar alinhado.
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
                // Verde quando o olhar está alinhado, vermelho caso contrário
                .fill(verificationManager.gazeCorrect ? Color.green : Color.red)
                .frame(width: 12, height: 12)
        }
        .padding(.horizontal, 4)
    }
}

