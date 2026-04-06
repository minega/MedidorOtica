//
//  AppGlass.swift
//  MedidorOticaApp
//
//  Utilitarios visuais para superfícies em estilo Liquid Glass com fallback seguro.
//

import SwiftUI

private struct AppGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let borderOpacity: Double
    let tintOpacity: Double
    let tintColor: Color
    let interactive: Bool
    let fallbackMaterial: Material

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                content
                    .glassEffect(
                        .regular
                            .tint(tintColor.opacity(tintOpacity))
                            .interactive(),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(borderOpacity), lineWidth: 1.5)
                    )
            } else {
                content
                    .glassEffect(
                        .regular
                            .tint(tintColor.opacity(tintOpacity)),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(borderOpacity), lineWidth: 1.3)
                    )
            }
        } else {
            content
                .background(
                    fallbackMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(borderOpacity), lineWidth: 1.3)
                )
        }
    }
}

extension View {
    /// Aplica o Liquid Glass quando disponivel e usa material nas versoes anteriores.
    func appGlassSurface(cornerRadius: CGFloat = 28,
                         borderOpacity: Double = 0.58,
                         tintOpacity: Double = 0.18,
                         tintColor: Color = .white,
                         interactive: Bool = true,
                         fallbackMaterial: Material = .ultraThinMaterial) -> some View {
        modifier(
            AppGlassSurfaceModifier(cornerRadius: cornerRadius,
                                    borderOpacity: borderOpacity,
                                    tintOpacity: tintOpacity,
                                    tintColor: tintColor,
                                    interactive: interactive,
                                    fallbackMaterial: fallbackMaterial)
        )
    }
}
