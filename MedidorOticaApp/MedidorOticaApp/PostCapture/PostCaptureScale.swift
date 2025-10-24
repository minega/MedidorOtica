//
//  PostCaptureScale.swift
//  MedidorOticaApp
//
//  Constantes e conversões para transformar milímetros em valores normalizados.
//

import CoreGraphics

// MARK: - Escalas do Fluxo Pós-Captura
enum PostCaptureScale {
    static let horizontalReferenceMM: CGFloat = 120
    static let verticalReferenceMM: CGFloat = 80
    static let pupilDiameterMM: CGFloat = 2
    static let verticalBarHeightMM: CGFloat = 50
    static let horizontalBarLengthMM: CGFloat = 60
    static let nasalOffsetMM: CGFloat = 9
    static let horizontalGapMM: CGFloat = 50
    static let inferiorOffsetMM: CGFloat = 15
    static let superiorOffsetMM: CGFloat = 20

    /// Converte um valor em milímetros para escala horizontal normalizada (0...1).
    static func normalizedHorizontal(_ millimeters: CGFloat) -> CGFloat {
        guard horizontalReferenceMM > 0 else { return 0 }
        return millimeters / horizontalReferenceMM
    }

    /// Converte um valor em milímetros para escala vertical normalizada (0...1).
    static func normalizedVertical(_ millimeters: CGFloat) -> CGFloat {
        guard verticalReferenceMM > 0 else { return 0 }
        return millimeters / verticalReferenceMM
    }
}
