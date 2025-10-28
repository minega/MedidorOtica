//
//  UIImage+Orientation.swift
//  MedidorOticaApp
//
//  Utilitário para normalizar a orientação das imagens utilizadas no fluxo pós-captura.
//

import UIKit

// MARK: - Normalização de Orientação
extension UIImage {
    /// Retorna uma versão com orientação `.up`, preservando a escala original.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered
    }
}
