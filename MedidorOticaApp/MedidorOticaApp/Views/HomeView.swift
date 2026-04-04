//
//  HomeView.swift
//  MedidorOticaApp
//
//  Tela inicial com acao principal centralizada e botoes alinhados ao visual Liquid Glass.
//

import SwiftUI

struct HomeView: View {
    // MARK: - Estado
    @State private var isShowingCamera = false
    @State private var isShowingHistory = false

    // MARK: - Dependencias
    @EnvironmentObject private var historyManager: HistoryManager

    // MARK: - View
    var body: some View {
        ZStack {
            backgroundView
            headerView
            primaryActionLayer
            secondaryActionLayer
        }
        .ignoresSafeArea()
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

// MARK: - Subviews
private extension HomeView {
    /// Mantem um fundo rico em cor para valorizar os controles em vidro.
    var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.10, blue: 0.18),
                    Color(red: 0.04, green: 0.22, blue: 0.31),
                    Color(red: 0.07, green: 0.14, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.cyan.opacity(0.24))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: -150, y: -240)

            Circle()
                .fill(Color.blue.opacity(0.20))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: 150, y: 120)

            Circle()
                .fill(Color.mint.opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 110)
                .offset(x: -110, y: 280)
        }
    }

    /// Exibe apenas o nome do app, sem subtitulos extras.
    var headerView: some View {
        Text("Medidor Ótica")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 72)
            .padding(.horizontal, 24)
    }

    /// Posiciona a acao principal exatamente no centro da tela.
    var primaryActionLayer: some View {
        startMeasurementButton
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 28)
    }

    /// Mantem o acesso ao historico discreto no rodape.
    var secondaryActionLayer: some View {
        historyButton
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
    }

    /// Usa o estilo nativo de Liquid Glass no iOS 26 e um fallback em material nas versoes anteriores.
    @ViewBuilder
    var startMeasurementButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: openCamera) {
                VStack(spacing: 14) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 34, weight: .semibold))
                    Text("Iniciar medidas")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: 260)
                .padding(.vertical, 24)
                .padding(.horizontal, 28)
            }
            .buttonStyle(.glassProminent)
        } else {
            Button(action: openCamera) {
                VStack(spacing: 14) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 34, weight: .semibold))
                    Text("Iniciar medidas")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: 260)
                .padding(.vertical, 24)
                .padding(.horizontal, 28)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
            }
            .buttonStyle(.plain)
        }
    }

    /// O botao secundario tambem adota vidro, mas com menor destaque visual.
    @ViewBuilder
    var historyButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: openHistory) {
                Label("Ver histórico", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
            }
            .buttonStyle(.glass)
        } else {
            Button(action: openHistory) {
                Label("Ver histórico", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Acoes
private extension HomeView {
    func openCamera() {
        isShowingCamera = true
    }

    func openHistory() {
        isShowingHistory = true
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(HistoryManager.shared)
    }
}
