//
//  MedidorOticaApp.swift
//  MedidorOticaApp
//
//  Ponto de entrada principal do aplicativo Medidor Ótica.
//  Versão simplificada para resolver problemas de compilação.
//

import SwiftUI

@main
struct MedidorOticaApp: App {
    // Inicializa os gerenciadores uma única vez
    @StateObject private var cameraManager = CameraManager.shared
    @StateObject private var historyManager = HistoryManager.shared
    
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(historyManager)
        }
    }
}
