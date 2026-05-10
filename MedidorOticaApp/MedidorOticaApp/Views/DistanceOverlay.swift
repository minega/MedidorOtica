//
//  DistanceOverlay.swift
//  MedidorOticaApp
//
//  Exibe distancia medida ou encaixe visual conforme o sensor ativo.
//

import SwiftUI

/// View opcional que mostra a distancia medida ou o tamanho do rosto no Mono.
struct DistanceOverlay: View {
    @ObservedObject var verificationManager: VerificationManager

    // MARK: - View
    var body: some View {
        if verificationManager.faceDetected {
            Text(displayText)
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

    private var displayText: String {
        if verificationManager.activeSensor == .rearMonoBridge {
            let heightPercentage = max(0, Int(round(verificationManager.projectedFaceHeightRatio * 100)))
            return heightPercentage > 0 ? "Rosto \(heightPercentage)%" : "Rosto no oval"
        }

        return String(format: "%.1f cm", verificationManager.lastMeasuredDistance)
    }
}
