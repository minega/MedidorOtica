//
//  PostCaptureCentralPointResolver.swift
//  MedidorOticaApp
//
//  Resolve o eixo X do PC usando a melhor referencia geometrica disponivel.
//

import CoreGraphics

// MARK: - Resolucao do PC
/// Decide o eixo X do PC combinando simetria facial, pupilas e suporte 3D do TrueDepth.
struct PostCaptureCentralPointResolver {
    // MARK: - Tipos auxiliares
    struct Candidates {
        let bridgeX: CGFloat?
        let captureX: CGFloat?
        let pupilMidlineX: CGFloat?
        let faceMidlineX: CGFloat
    }

    private enum Constants {
        /// Mantem a ponte apenas como refinamento quando ela concorda fortemente com a simetria facial.
        static let bridgeToleranceRatio: CGFloat = 0.03
        /// Evita tolerancias pequenas demais em rostos muito estreitos.
        static let minimumTolerance: CGFloat = 0.008
        /// Mantem a linha principal mais fiel ao eixo optico das pupilas.
        static let pupilWeight: CGFloat = 2
        /// A ponte refina o suficiente para devolver assimetria anatomica sem desestabilizar o PC.
        static let bridgeBlendFactor: CGFloat = 0.4
    }

    // MARK: - Interface principal
    /// Resolve o eixo X final do PC priorizando a linha media facial corrigida pelo TrueDepth.
    static func resolveX(using candidates: Candidates,
                         within normalizedBounds: NormalizedRect) -> CGFloat {
        let faceMidlineX = clamped(candidate: candidates.faceMidlineX,
                                   within: normalizedBounds)
        let pupilMidlineX = validated(candidate: candidates.pupilMidlineX,
                                      within: normalizedBounds)
        let bridgeX = validated(candidate: candidates.bridgeX,
                                within: normalizedBounds)

        let geometricBaseline = resolvedGeometricBaseline(faceMidlineX: faceMidlineX,
                                                          pupilMidlineX: pupilMidlineX,
                                                          normalizedBounds: normalizedBounds)

        guard let bridgeX else { return geometricBaseline }

        let tolerance = max(normalizedBounds.width * Constants.bridgeToleranceRatio,
                            Constants.minimumTolerance)
        guard abs(bridgeX - geometricBaseline) <= tolerance else {
            return geometricBaseline
        }

        let refinedX = geometricBaseline + ((bridgeX - geometricBaseline) * Constants.bridgeBlendFactor)
        return clamped(candidate: refinedX, within: normalizedBounds)
    }

    // MARK: - Baselines geometricos
    /// Gera a linha media principal a partir da propria foto, sem deixar a captura herdada enviesar o eixo X.
    private static func resolvedGeometricBaseline(faceMidlineX: CGFloat,
                                                  pupilMidlineX: CGFloat?,
                                                  normalizedBounds: NormalizedRect) -> CGFloat {
        let fallbackX = normalizedBounds.x + (normalizedBounds.width * 0.5)
        let twoDimensionalBaseline = resolvedTwoDimensionalBaseline(faceMidlineX: faceMidlineX,
                                                                    pupilMidlineX: pupilMidlineX)
        return clamped(candidate: twoDimensionalBaseline ?? faceMidlineX,
                       within: normalizedBounds,
                       fallback: fallbackX)
    }

    /// Combina simetria facial e pupilas, dando mais peso ao eixo optico dos olhos.
    private static func resolvedTwoDimensionalBaseline(faceMidlineX: CGFloat,
                                                       pupilMidlineX: CGFloat?) -> CGFloat? {
        guard let pupilMidlineX else { return faceMidlineX }
        return ((pupilMidlineX * Constants.pupilWeight) + faceMidlineX) /
            (Constants.pupilWeight + 1)
    }

    // MARK: - Validacoes
    /// Garante que o candidato esteja dentro do rosto recortado.
    private static func validated(candidate: CGFloat?,
                                  within normalizedBounds: NormalizedRect) -> CGFloat? {
        guard let candidate else { return nil }
        let range = normalizedBounds.x...(normalizedBounds.x + normalizedBounds.width)
        guard range.contains(candidate) else { return nil }
        return candidate
    }

    /// Limita qualquer valor ao recorte facial atual.
    private static func clamped(candidate: CGFloat,
                                within normalizedBounds: NormalizedRect,
                                fallback: CGFloat? = nil) -> CGFloat {
        let minimum = normalizedBounds.x
        let maximum = normalizedBounds.x + normalizedBounds.width
        guard minimum <= maximum else { return fallback ?? candidate }
        return min(max(candidate, minimum), maximum)
    }
}
