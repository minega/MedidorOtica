//
//  ARStatusIndicator.swift
//  MedidorOticaApp
//
//  Indicador visual de status da sessão AR e detecção de rosto.
//  Exibe duas bolinhas lado a lado: uma para a ARSession e outra para o rosto.
//
import SwiftUI

/// Exibe o status da sessão AR e da detecção de rosto.
/// A primeira bolinha indica a ARSession e a segunda se um rosto está visível.
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
                .fill(verificationManager.faceDetected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
        }
        .padding(.horizontal, 4)
    }
}

