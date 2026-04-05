//
//  DistanceOverlay.swift
//  MedidorOticaApp
//
//  Exibe a distancia atual entre o sensor e o plano do PC.
//

import SwiftUI

/// View opcional que mostra a distancia medida.
struct DistanceOverlay: View {
    @ObservedObject var verificationManager: VerificationManager

    // MARK: - View
    var body: some View {
        if verificationManager.faceDetected {
            Text(String(format: "%.1f cm ate o PC", verificationManager.lastMeasuredDistance))
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
        }
    }
}
