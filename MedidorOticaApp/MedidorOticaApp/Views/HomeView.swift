//
//  HomeView.swift
//  MedidorOticaApp
//
//  Tela inicial com fundo claro, titulo enquadrado e acoes em estilo Liquid Glass.
//

import SwiftUI

struct HomeView: View {
    // MARK: - Estado
    @State private var isShowingCamera = false
    @State private var isShowingHistory = false

    // MARK: - Dependencias
    @EnvironmentObject private var historyManager: HistoryManager

    // MARK: - Tema
    private let textColor = Color(red: 0.14, green: 0.27, blue: 0.43)
    private let accentColor = Color(red: 0.31, green: 0.55, blue: 0.92)

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
    /// Cria um fundo claro para valorizar os vidros e deixar a tela mais leve.
    var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.98, blue: 1.00),
                    Color(red: 0.90, green: 0.96, blue: 1.00),
                    Color(red: 0.95, green: 0.99, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 360, height: 360)
                .blur(radius: 48)
                .offset(x: -125, y: -235)

            Circle()
                .fill(Color.cyan.opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 72)
                .offset(x: 155, y: -120)

            Circle()
                .fill(Color.blue.opacity(0.14))
                .frame(width: 340, height: 340)
                .blur(radius: 92)
                .offset(x: 155, y: 210)

            Circle()
                .fill(Color.mint.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 84)
                .offset(x: -145, y: 285)
        }
    }

    /// Abaixa o titulo e enquadra o nome do app para ele respirar melhor no topo.
    var headerLayer: some View {
        titlePlaque
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 104)
            .padding(.horizontal, 24)
    }

    /// Mantem a acao principal no centro com area visual mais robusta.
    var primaryActionLayer: some View {
        startMeasurementButton
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 26)
    }

    /// Mantem o historico no rodape com o mesmo idioma visual.
    var secondaryActionLayer: some View {
        historyButton
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
    }
}

// MARK: - Components
private extension HomeView {
    /// Usa uma placa em vidro para destacar o nome do app.
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
                              borderOpacity: 0.60,
                              interactive: false)
            .shadow(color: accentColor.opacity(0.08), radius: 16, x: 0, y: 8)
    }

    /// Amplia o icone e deixa o botao principal mais quadrado e com vidro mais alto.
    @ViewBuilder
    var startMeasurementButton: some View {
        Button(action: openCamera) {
            VStack(spacing: 18) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 58, weight: .semibold))

                Text("INICIAR MEDIDAS")
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .tracking(1.6)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(textColor)
            .frame(maxWidth: 304)
            .frame(minHeight: 194)
            .padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
        .homeGlassSurface(cornerRadius: 38,
                          borderOpacity: 0.82,
                          interactive: true)
        .shadow(color: Color.white.opacity(0.48), radius: 2, x: 0, y: 0)
        .shadow(color: accentColor.opacity(0.14), radius: 22, x: 0, y: 14)
    }

    /// Aumenta a altura do historico e reforca a borda para combinar com o CTA.
    @ViewBuilder
    var historyButton: some View {
        Button(action: openHistory) {
            Label("Ver histórico", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 66)
                .padding(.horizontal, 22)
        }
        .buttonStyle(.plain)
        .homeGlassSurface(cornerRadius: 28,
                          borderOpacity: 0.72,
                          interactive: true)
        .frame(maxWidth: 340)
        .shadow(color: accentColor.opacity(0.10), radius: 18, x: 0, y: 12)
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
    /// Aplica o vidro nativo do iOS 26 e usa material como fallback nas versoes anteriores.
    @ViewBuilder
    func homeGlassSurface(cornerRadius: CGFloat,
                          borderOpacity: Double,
                          interactive: Bool) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self
                    .glassEffect(
                        .regular
                            .tint(.white.opacity(0.18))
                            .interactive(),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(borderOpacity), lineWidth: 1.6)
                    )
            } else {
                self
                    .glassEffect(
                        .regular
                            .tint(.white.opacity(0.18)),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(borderOpacity), lineWidth: 1.4)
                    )
            }
        } else {
            self
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(borderOpacity), lineWidth: 1.4)
                )
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(HistoryManager.shared)
    }
}
