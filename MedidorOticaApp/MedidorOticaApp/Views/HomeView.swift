//
//  HomeView.swift
//  MedidorOticaApp
//
//  Tela inicial com botoes refeitos usando os estilos nativos de Liquid Glass.
//

import SwiftUI

struct HomeView: View {
    // MARK: - Estado
    @State private var isShowingCamera = false
    @State private var isShowingHistory = false

    // MARK: - Dependencias
    @EnvironmentObject private var historyManager: HistoryManager

    // MARK: - Tema
    private let titleColor = Color(red: 0.15, green: 0.18, blue: 0.28)
    private let titlePlateStroke = Color.white.opacity(0.34)
    private let primaryPink = Color(red: 0.98, green: 0.52, blue: 0.76)
    private let primaryTextColor = Color(red: 0.40, green: 0.13, blue: 0.28)
    private let secondaryTextColor = Color(red: 0.22, green: 0.28, blue: 0.39)

    // MARK: - View
    var body: some View {
        ZStack {
            backgroundView
            contentLayer
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

// MARK: - Layout
private extension HomeView {
    /// Mantem a composicao centralizada e com espaco para o CTA principal.
    var contentLayer: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 120)

            titlePlaque

            Spacer(minLength: 58)

            buttonStack

            Spacer(minLength: 36)
        }
        .padding(.horizontal, 24)
    }

    /// Fecha levemente o fundo para valorizar o vidro claro.
    var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.90, green: 0.92, blue: 0.97),
                    Color(red: 0.84, green: 0.89, blue: 0.95),
                    Color(red: 0.88, green: 0.93, blue: 0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.80))
                .frame(width: 420, height: 420)
                .blur(radius: 58)
                .offset(x: -125, y: -245)

            Circle()
                .fill(Color.cyan.opacity(0.14))
                .frame(width: 350, height: 350)
                .blur(radius: 92)
                .offset(x: 175, y: -105)

            Circle()
                .fill(primaryPink.opacity(0.14))
                .frame(width: 380, height: 380)
                .blur(radius: 100)
                .offset(x: 165, y: 220)

            Circle()
                .fill(Color.mint.opacity(0.08))
                .frame(width: 320, height: 320)
                .blur(radius: 92)
                .offset(x: -150, y: 300)

            Rectangle()
                .fill(Color.black.opacity(0.05))
        }
    }
}

// MARK: - Components
private extension HomeView {
    /// Usa uma serif mais profissional sem aplicar Liquid Glass na camada de conteudo.
    @ViewBuilder
    var titlePlaque: some View {
        Text("MEDIDOR OTICA")
            .font(.system(size: 30, weight: .bold, design: .serif))
            .tracking(2.4)
            .foregroundStyle(titleColor)
            .minimumScaleFactor(0.84)
            .lineLimit(1)
            .padding(.vertical, 18)
            .padding(.horizontal, 28)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(titlePlateStroke, lineWidth: 1)
            )
            .shadow(color: Color.white.opacity(0.34), radius: 10, x: 0, y: -1)
            .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: 10)
    }

    /// Agrupa os botoes para o sistema compor o vidro de forma consistente.
    @ViewBuilder
    var buttonStack: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                VStack(spacing: 20) {
                    primaryActionButton
                    historyButton
                }
            }
            .environment(\.colorScheme, .light)
        } else {
            VStack(spacing: 20) {
                primaryActionButton
                historyButton
            }
        }
    }

    /// Refaz o CTA apenas com o estilo nativo `glassProminent`.
    @ViewBuilder
    var primaryActionButton: some View {
        Button(action: openCamera) {
            VStack(spacing: 16) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 70, weight: .semibold))

                Text("INICIAR MEDIDAS")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(1.8)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(primaryTextColor)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 206)
            .padding(.horizontal, 26)
        }
        .homePrimaryLiquidGlassStyle(tint: primaryPink)
        .shadow(color: primaryPink.opacity(0.18), radius: 24, x: 0, y: 16)
    }

    /// Mantem o historico em um botao simples com o vidro padrao da Apple.
    @ViewBuilder
    var historyButton: some View {
        Button(action: openHistory) {
            Label("Ver historico", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(secondaryTextColor)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 62)
                .padding(.horizontal, 20)
        }
        .homeSecondaryLiquidGlassStyle()
        .frame(maxWidth: 340)
    }
}

// MARK: - Actions
private extension HomeView {
    func openCamera() {
        isShowingCamera = true
    }

    func openHistory() {
        isShowingHistory = true
    }
}

// MARK: - Button Styles
private extension View {
    /// Aplica o CTA com o estilo nativo de maior destaque do Liquid Glass.
    @ViewBuilder
    func homePrimaryLiquidGlassStyle(tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 32))
                .tint(tint)
                .environment(\.colorScheme, .light)
        } else {
            self
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 32))
                .tint(tint)
        }
    }

    /// Aplica o estilo padrao de vidro da Apple para a acao secundaria.
    @ViewBuilder
    func homeSecondaryLiquidGlassStyle() -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 24))
                .environment(\.colorScheme, .light)
        } else {
            self
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 24))
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(HistoryManager.shared)
    }
}
