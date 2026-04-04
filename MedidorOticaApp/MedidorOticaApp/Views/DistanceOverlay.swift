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
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .appGlassSurface(cornerRadius: 16,
                                 borderOpacity: 0.58,
                                 tintOpacity: 0.14,
                                 interactive: false)
        }
    }
}
