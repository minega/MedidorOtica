//
//  HomeView.swift
//  MedidorOticaApp
//
//  Tela inicial com Liquid Glass nativo, CTA central e historico flutuando no rodape.
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
    private let primaryPink = Color(red: 0.98, green: 0.52, blue: 0.76)
    private let primaryTextColor = Color.white
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
    /// Mantem o CTA no centro e fixa o historico no rodape.
    var contentLayer: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 28) {
                    homeLayout
                }
                .environment(\.colorScheme, .light)
            } else {
                homeLayout
            }
        }
    }

    /// Fecha levemente o fundo e adiciona contraste local para o vidro aparecer.
    var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.86, green: 0.89, blue: 0.95),
                    Color(red: 0.80, green: 0.86, blue: 0.93),
                    Color(red: 0.85, green: 0.90, blue: 0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.80))
                .frame(width: 420, height: 420)
                .blur(radius: 58)
                .offset(x: -125, y: -245)

            RoundedRectangle(cornerRadius: 92, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.46),
                            Color.cyan.opacity(0.12),
                            primaryPink.opacity(0.16),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 400, height: 290)
                .blur(radius: 82)
                .offset(y: 94)

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

            RoundedRectangle(cornerRadius: 60, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.08),
                            primaryPink.opacity(0.12),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 330, height: 110)
                .blur(radius: 58)
                .offset(y: 336)

            Rectangle()
                .fill(Color.black.opacity(0.10))
        }
    }
}

// MARK: - Components
private extension HomeView {
    /// Mantem a organizacao principal e reserva espaco para o historico no rodape.
    var homeLayout: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 134)

                titlePlaque

                Spacer(minLength: 64)

                primaryActionButton

                Spacer(minLength: 162)
            }
            .padding(.horizontal, 24)

            historyButton
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
        }
    }

    /// Usa uma serif mais profissional com vidro branco real.
    @ViewBuilder
    var titlePlaque: some View {
        Text("MEDIDOR ÓTICA")
            .font(.system(size: 31, weight: .black, design: .serif))
            .tracking(2.8)
            .foregroundStyle(titleColor)
            .minimumScaleFactor(0.84)
            .lineLimit(1)
            .padding(.vertical, 18)
            .padding(.horizontal, 30)
            .environment(\.colorScheme, .light)
            .appGlassSurface(cornerRadius: 28,
                             borderOpacity: 0.22,
                             tintOpacity: 0.05,
                             tintColor: .white,
                             variant: .clear,
                             interactive: false,
                             fallbackMaterial: .thinMaterial)
            .shadow(color: Color.white.opacity(0.10), radius: 8, x: 0, y: -2)
            .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 14)
    }

    /// Mantem o CTA principal com a base nativa de maior destaque.
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

    /// Posiciona o historico como um vidro discreto e mais transparente no rodape.
    @ViewBuilder
    var historyButton: some View {
        Button(action: openHistory) {
            Label("Ver historico", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(secondaryTextColor)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 58)
                .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .light)
        .appGlassSurface(cornerRadius: 24,
                         borderOpacity: 0.12,
                         tintOpacity: 0.015,
                         tintColor: .white,
                         variant: .clear,
                         interactive: true,
                         fallbackMaterial: .ultraThinMaterial)
        .frame(maxWidth: 300)
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
                .tint(tint.opacity(0.82))
                .environment(\.colorScheme, .light)
        } else {
            self
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 32))
                .tint(tint)
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(HistoryManager.shared)
    }
}
