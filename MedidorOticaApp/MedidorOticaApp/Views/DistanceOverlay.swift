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
            Text(String(format: "%.1f cm", verificationManager.lastMeasuredDistance))
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .environment(\.colorScheme, .light)
                .appGlassSurface(cornerRadius: 10,
                                 borderOpacity: 0.14,
                                 tintOpacity: 0.24,
                                 tintColor: .black,
                                 variant: .regular,
                                 interactive: false,
                                 fallbackMaterial: .thinMaterial)
                .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 4)
        }
    }
}
