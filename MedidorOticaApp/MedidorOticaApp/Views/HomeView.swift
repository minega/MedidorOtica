//
//  HomeView.swift
//  MedidorOticaApp
//
//  Tela inicial simplificada do aplicativo Medidor Ótica.
//  Apresenta uma interface limpa com opção para iniciar uma nova medição.
//

import SwiftUI

struct HomeView: View {
    @State private var isShowingCamera = false
    @State private var isShowingHistory = false
    @StateObject private var cameraManager = CameraManager.shared
    @EnvironmentObject private var historyManager: HistoryManager
    
    var body: some View {
        ZStack {
            // Fundo gradiente mais suave
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.8, green: 0.9, blue: 1.0), // Azul bem claro
                    Color(red: 0.9, green: 0.8, blue: 1.0)  // Roxo bem claro
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack {
                // Cabeçalho
                VStack(spacing: 8) {
                    Text("Medidor Ótica")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    
                    Text("Versão Simplificada")
                        .font(.title3)
                        .foregroundColor(.gray)
                        .padding(.bottom, 30)
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Botão Principal - Câmera
                Button(action: {
                    isShowingCamera = true
                }) {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 70))
                            .foregroundColor(.white)
                        
                        Text("INICIAR MEDIDAS")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 35)
                    .padding(.horizontal, 65)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.blue,
                                    Color.purple
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                    )
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .padding(.top, 60)
                }
                
                Spacer()
                
                // Botão de histórico
                VStack {
                    Divider()
                        .padding(.horizontal)
                    
                    Button(action: {
                        isShowingHistory = true
                    }) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title3)
                            Text("Ver Histórico")
                                .font(.headline)
                        }
                        .foregroundColor(.blue)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(12)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 20)
                    }
                }
            }
            .padding()
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraView()
                .environmentObject(historyManager)
        }
        .sheet(isPresented: $isShowingHistory) {
            HistoryView()
                .environmentObject(historyManager)
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
