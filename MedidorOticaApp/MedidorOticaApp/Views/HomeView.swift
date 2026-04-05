//
//  HomeView.swift
//  MedidorOticaApp
//
//  Tela inicial com fundo claro e botoes em vidro destacado.
//

import SwiftUI

struct HomeView: View {
    // MARK: - Estado
    @State private var isShowingCamera = false
    @State private var isShowingHistory = false

    // MARK: - Dependencias
    @EnvironmentObject private var historyManager: HistoryManager

    // MARK: - Tema
    private let textColor = Color(red: 0.12, green: 0.25, blue: 0.42)
    private let accentColor = Color(red: 0.27, green: 0.56, blue: 0.93)

    // MARK: - View
    var body: some View {
        ZStack {
            backgroundView
            headerLayer
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

// MARK: - Layout
private extension HomeView {
    /// Cria um fundo claro para valorizar o vidro dos botoes.
    var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.99, blue: 1.00),
                    Color(red: 0.92, green: 0.97, blue: 1.00),
                    Color(red: 0.97, green: 1.00, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.96))
                .frame(width: 390, height: 390)
                .blur(radius: 54)
                .offset(x: -120, y: -245)

            Circle()
                .fill(Color.cyan.opacity(0.20))
                .frame(width: 340, height: 340)
                .blur(radius: 82)
                .offset(x: 165, y: -110)

            Circle()
                .fill(accentColor.opacity(0.16))
                .frame(width: 360, height: 360)
                .blur(radius: 96)
                .offset(x: 165, y: 215)

            Circle()
                .fill(Color.mint.opacity(0.12))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: -150, y: 295)
        }
    }

    /// Abaixa o titulo para dar mais respiro no topo.
    var headerLayer: some View {
        titlePlaque
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 118)
            .padding(.horizontal, 24)
    }

    /// Mantem o CTA no centro com destaque maximo.
    var primaryActionLayer: some View {
        startMeasurementButton
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 26)
    }

    /// Posiciona o historico no rodape.
    var secondaryActionLayer: some View {
        historyButton
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
    }
}

// MARK: - Components
private extension HomeView {
    /// Enquadra o nome do app em uma placa leve de vidro.
    @ViewBuilder
    var titlePlaque: some View {
        Text("MEDIDOR ÓTICA")
            .font(.system(size: 28, weight: .black, design: .rounded))
            .tracking(3.8)
            .foregroundStyle(textColor)
            .minimumScaleFactor(0.8)
            .lineLimit(1)
            .padding(.vertical, 18)
            .padding(.horizontal, 24)
            .homeGlassSurface(cornerRadius: 28,
                              borderOpacity: 0.68,
                              tintOpacity: 0.24,
                              baseOpacity: 0.12,
                              highlightOpacity: 0.56,
                              interactive: false)
            .shadow(color: accentColor.opacity(0.08), radius: 16, x: 0, y: 8)
    }

    /// Destaca o CTA com vidro claro, alto relevo e borda mais evidente.
    @ViewBuilder
    var startMeasurementButton: some View {
        Button(action: openCamera) {
            VStack(spacing: 16) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 72, weight: .semibold))

                Text("INICIAR MEDIDAS")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(1.8)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(textColor)
            .frame(maxWidth: 316)
            .frame(minHeight: 214)
            .padding(.horizontal, 28)
        }
        .buttonStyle(.plain)
        .homeGlassSurface(cornerRadius: 34,
                          borderOpacity: 0.96,
                          tintOpacity: 0.36,
                          baseOpacity: 0.24,
                          highlightOpacity: 0.78,
                          interactive: true)
        .shadow(color: Color.white.opacity(0.74), radius: 8, x: 0, y: -2)
        .shadow(color: accentColor.opacity(0.18), radius: 24, x: 0, y: 14)
    }

    /// Mantem o botao secundario claro e consistente com o CTA.
    @ViewBuilder
    var historyButton: some View {
        Button(action: openHistory) {
            Label("Ver historico", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 72)
                .padding(.horizontal, 22)
        }
        .buttonStyle(.plain)
        .homeGlassSurface(cornerRadius: 30,
                          borderOpacity: 0.88,
                          tintOpacity: 0.30,
                          baseOpacity: 0.20,
                          highlightOpacity: 0.62,
                          interactive: true)
        .frame(maxWidth: 340)
        .shadow(color: Color.white.opacity(0.56), radius: 5, x: 0, y: -1)
        .shadow(color: accentColor.opacity(0.12), radius: 18, x: 0, y: 12)
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
    /// Aplica um vidro claro no iOS 26 e usa material brilhante como fallback.
    @ViewBuilder
    func homeGlassSurface(cornerRadius: CGFloat,
                          borderOpacity: Double,
                          tintOpacity: Double,
                          baseOpacity: Double,
                          highlightOpacity: Double,
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
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    .glassEffect(
                        .regular
                            .tint(Color.white.opacity(tintOpacity))
                            .interactive(),
                        in: shape
                    )
                    .overlay {
                        shape
                            .stroke(Color.white.opacity(borderOpacity), lineWidth: 1.8)
                    }
                    .overlay(alignment: .top) {
                        shape
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.98),
                                        Color.white.opacity(0.10)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.1
                            )
                    }
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
                                    Color.white.opacity(baseOpacity * 0.85),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    .glassEffect(
                        .regular
                            .tint(Color.white.opacity(tintOpacity)),
                        in: shape
                    )
                    .overlay {
                        shape
                            .stroke(Color.white.opacity(borderOpacity), lineWidth: 1.5)
                    }
                    .overlay(alignment: .top) {
                        shape
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.94),
                                        Color.white.opacity(0.10)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.0
                            )
                    }
            }
        } else {
            self
                .background {
                    shape.fill(Color.white.opacity(baseOpacity + 0.08))
                }
                .background(.ultraThinMaterial, in: shape)
                .background {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(highlightOpacity * 0.72),
                                Color.white.opacity(baseOpacity),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay {
                    shape
                        .stroke(Color.white.opacity(borderOpacity), lineWidth: 1.5)
                }
                .overlay(alignment: .top) {
                    shape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.92),
                                    Color.white.opacity(0.10)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.0
                        )
                }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(HistoryManager.shared)
    }
}
