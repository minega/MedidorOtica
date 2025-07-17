//
//  DistanceOverlay.swift
//  MedidorOticaApp
//
//  Exibe a distância atual entre o usuário e a câmera.
//  Pode ser facilmente ativada ou removida.
//

import SwiftUI

/// View opcional que mostra a distância medida.
struct DistanceOverlay: View {
    @ObservedObject var verificationManager: VerificationManager

    // MARK: - View
    var body: some View {
        if verificationManager.faceDetected {
            // Mostra a distância somente enquanto o rosto está rastreado
            Text(String(format: "%.1f cm", verificationManager.lastMeasuredDistance))
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
        }
    }
}
