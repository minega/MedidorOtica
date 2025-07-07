//
//  ARStatusIndicator.swift
//  MedidorOticaApp
//
//  Pequeno indicador visual que mostra se a sessão AR está ativa.
//  Pode ser habilitado ou removido facilmente.
//
import SwiftUI

/// Mostra um círculo verde se a sessão AR está ativa, vermelho caso contrário.
struct ARStatusIndicator: View {
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        Circle()
            .fill(cameraManager.isUsingARSession ? Color.green : Color.red)
            .frame(width: 12, height: 12)
            .padding(.leading, 4)
    }
}

