//
//  HomeView.swift
//  MedidorOticaApp
//
//  Tela inicial com fundo levemente mais fechado e botoes em Liquid Glass claro.
//

import SwiftUI

struct HomeView: View {
    // MARK: - Estado
    @State private var isShowingCamera = false
    @State private var isShowingHistory = false

    // MARK: - Dependencias
    @EnvironmentObject private var historyManager: HistoryManager

    // MARK: - Tema
    private let titleColor = Color(red: 0.16, green: 0.20, blue: 0.30)
    private let secondaryTextColor = Color(red: 0.23, green: 0.29, blue: 0.40)
    private let primaryPink = Color(red: 0.96, green: 0.69, blue: 0.83)
    private let primaryTextColor = Color(red: 0.42, green: 0.16, blue: 0.31)

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
    /// Organiza a home com respiro no topo, CTA central e historico no rodape.
    var contentLayer: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 118)

            titlePlaque

            Spacer(minLength: 52)

            startMeasurementButton

            Spacer(minLength: 32)

            historyButton
                .padding(.bottom, 30)
        }
        .padding(.horizontal, 24)
    }

    /// Deixa o fundo claro, mas um pouco mais fechado para sustentar o vidro branco.
    var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.94, blue: 0.98),
                    Color(red: 0.86, green: 0.91, blue: 0.97),
                    Color(red: 0.90, green: 0.95, blue: 0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.82))
                .frame(width: 390, height: 390)
                .blur(radius: 56)
                .offset(x: -120, y: -245)

            Circle()
                .fill(Color.cyan.opacity(0.16))
                .frame(width: 340, height: 340)
                .blur(radius: 84)
                .offset(x: 165, y: -110)

            Circle()
                .fill(primaryPink.opacity(0.16))
                .frame(width: 360, height: 360)
                .blur(radius: 96)
                .offset(x: 170, y: 220)

            Circle()
                .fill(Color.mint.opacity(0.10))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: -150, y: 295)

            Rectangle()
                .fill(Color.black.opacity(0.04))
        }
    }
}

// MARK: - Components
private extension HomeView {
    /// Apresenta o nome do app em uma tipografia mais profissional e menos arredondada.
    @ViewBuilder
    var titlePlaque: some View {
        Text("MEDIDOR OTICA")
            .font(.system(size: 30, weight: .bold, design: .serif))
            .tracking(2.4)
            .foregroundStyle(titleColor)
            .minimumScaleFactor(0.8)
            .lineLimit(1)
            .padding(.vertical, 18)
            .padding(.horizontal, 26)
            .homeGlassSurface(cornerRadius: 26,
                              glassTint: .white,
                              tintOpacity: 0.30,
                              baseOpacity: 0.18,
                              highlightOpacity: 0.68,
                              borderOpacity: 0.28,
                              showsBorder: false,
                              sheenOpacity: 0.52,
                              interactive: false)
            .shadow(color: Color.white.opacity(0.38), radius: 10, x: 0, y: -1)
            .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: 10)
    }

    /// Usa um vidro rosa mais forte sem contorno aparente, seguindo o CTA principal.
    @ViewBuilder
    var startMeasurementButton: some View {
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
            .frame(maxWidth: 316)
            .frame(minHeight: 210)
            .padding(.horizontal, 28)
        }
        .buttonStyle(.plain)
        .homeGlassSurface(cornerRadius: 34,
                          glassTint: primaryPink,
                          tintOpacity: 0.72,
                          baseOpacity: 0.14,
                          highlightOpacity: 0.96,
                          borderOpacity: 0.0,
                          showsBorder: false,
                          sheenOpacity: 1.0,
                          interactive: true)
        .shadow(color: Color.white.opacity(0.52), radius: 14, x: 0, y: -3)
        .shadow(color: primaryPink.opacity(0.34), radius: 30, x: 0, y: 18)
    }

    /// Mantem o historico em um vidro branco mais discreto e padrao.
    @ViewBuilder
    var historyButton: some View {
        Button(action: openHistory) {
            Label("Ver historico", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundStyle(secondaryTextColor)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 62)
                .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .homeGlassSurface(cornerRadius: 24,
                          glassTint: .white,
                          tintOpacity: 0.12,
                          baseOpacity: 0.06,
                          highlightOpacity: 0.30,
                          borderOpacity: 0.18,
                          showsBorder: false,
                          sheenOpacity: 0.38,
                          interactive: true)
        .frame(maxWidth: 340)
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 8)
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

// MARK: - Glass Surface
private extension View {
    /// Mantem o vidro claro mesmo no modo noturno usando uma aparencia fixa clara.
    @ViewBuilder
    func homeGlassSurface(cornerRadius: CGFloat,
                          glassTint: Color,
                          tintOpacity: Double,
                          baseOpacity: Double,
                          highlightOpacity: Double,
                          borderOpacity: Double,
                          showsBorder: Bool,
                          sheenOpacity: Double,
                          interactive: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            if interactive {
                self
                    .background {
                        shape.fill(Color.white.opacity(baseOpacity))
                    }
                    .background {
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(highlightOpacity),
                                    Color.white.opacity(baseOpacity),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    .glassEffect(
                        .regular
                            .tint(glassTint.opacity(tintOpacity))
                            .interactive(),
                        in: shape
                    )
                    .overlay {
                        if showsBorder {
                            shape
                                .stroke(Color.white.opacity(borderOpacity), lineWidth: 1.2)
                        }
                    }
                    .overlay {
                        shape
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(highlightOpacity * 0.24 * sheenOpacity),
                                        Color.white.opacity(0.04),
                                        glassTint.opacity(tintOpacity * 0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(highlightOpacity * 0.72 * sheenOpacity),
                                        Color.white.opacity(0.0)
                                    ],
                                    center: .center,
                                    startRadius: 8,
                                    endRadius: 120
                                )
                            )
                            .frame(width: 210, height: 160)
                            .offset(x: -18, y: -28)
                            .mask(shape)
                    }
                    .overlay(alignment: .top) {
                        shape
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.90),
                                        Color.white.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.0
                            )
                            .opacity(showsBorder ? 1.0 : 0.82)
                    }
                    .environment(\.colorScheme, .light)
            } else {
                self
                    .background {
                        shape.fill(Color.white.opacity(baseOpacity))
                    }
                    .background {
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(highlightOpacity * 0.92),
                                    Color.white.opacity(baseOpacity * 0.90),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    .glassEffect(
                        .regular
                            .tint(glassTint.opacity(tintOpacity)),
                        in: shape
                    )
                    .overlay {
                        if showsBorder {
                            shape
                                .stroke(Color.white.opacity(borderOpacity), lineWidth: 1.0)
                        }
                    }
                    .overlay {
                        shape
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(highlightOpacity * 0.22 * sheenOpacity),
                                        Color.white.opacity(0.04),
                                        glassTint.opacity(tintOpacity * 0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(highlightOpacity * 0.64 * sheenOpacity),
                                        Color.white.opacity(0.0)
                                    ],
                                    center: .center,
                                    startRadius: 8,
                                    endRadius: 118
                                )
                            )
                            .frame(width: 210, height: 160)
                            .offset(x: -18, y: -28)
                            .mask(shape)
                    }
                    .overlay(alignment: .top) {
                        shape
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.88),
                                        Color.white.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.0
                            )
                            .opacity(showsBorder ? 1.0 : 0.78)
                    }
                    .environment(\.colorScheme, .light)
            }
        } else {
            self
                .background {
                    shape.fill(Color.white.opacity(baseOpacity + 0.12))
                }
                .background(.regularMaterial, in: shape)
                .background {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                glassTint.opacity(tintOpacity * 0.45),
                                Color.white.opacity(highlightOpacity * 0.62),
                                Color.white.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay {
                    if showsBorder {
                        shape
                            .stroke(Color.white.opacity(borderOpacity), lineWidth: 1.0)
                    }
                }
                .overlay {
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(highlightOpacity * 0.18 * sheenOpacity),
                                    Color.white.opacity(0.04),
                                    glassTint.opacity(tintOpacity * 0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(highlightOpacity * 0.58 * sheenOpacity),
                                    Color.white.opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: 116
                            )
                        )
                        .frame(width: 210, height: 160)
                        .offset(x: -18, y: -28)
                        .mask(shape)
                }
                .overlay(alignment: .top) {
                    shape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.84),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.0
                        )
                        .opacity(showsBorder ? 1.0 : 0.74)
                }
                .environment(\.colorScheme, .light)
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(HistoryManager.shared)
    }
}
