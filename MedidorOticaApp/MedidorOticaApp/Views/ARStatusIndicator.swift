//
//  ARStatusIndicator.swift
//  MedidorOticaApp
//
//  Indicador visual de status da sessão AR e detecção de rosto.
//  Exibe duas bolinhas: ARSession e rosto detectado.
//
import SwiftUI

/// Exibe o status da sessão AR e da detecção de rosto.
/// A ordem das bolinhas é: ARSession e rosto detectado.
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

        }
        .padding(.horizontal, 4)
    }
}

