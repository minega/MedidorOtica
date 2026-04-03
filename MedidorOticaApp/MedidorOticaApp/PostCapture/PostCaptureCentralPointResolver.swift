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
        /// Mantem a ponte apenas como refinamento quando ela concorda com a simetria facial.
        static let bridgeToleranceRatio: CGFloat = 0.05
        /// Evita tolerancias pequenas demais em rostos muito estreitos.
        static let minimumTolerance: CGFloat = 0.02
        /// O ponto 3D do TrueDepth recebe mais peso quando concorda com a geometria 2D.
        static let captureWeight: CGFloat = 2
    }

    // MARK: - Interface principal
    /// Resolve o eixo X final do PC priorizando a linha media facial corrigida pelo TrueDepth.
    static func resolveX(using candidates: Candidates,
                         within normalizedBounds: NormalizedRect) -> CGFloat {
        let faceMidlineX = clamped(candidate: candidates.faceMidlineX,
                                   within: normalizedBounds)
        let pupilMidlineX = validated(candidate: candidates.pupilMidlineX,
                                      within: normalizedBounds)
        let captureX = validated(candidate: candidates.captureX,
                                 within: normalizedBounds)
        let bridgeX = validated(candidate: candidates.bridgeX,
                                within: normalizedBounds)

        let geometricBaseline = resolvedGeometricBaseline(faceMidlineX: faceMidlineX,
                                                          pupilMidlineX: pupilMidlineX,
                                                          captureX: captureX,
                                                          normalizedBounds: normalizedBounds)

        guard let bridgeX else { return geometricBaseline }

        let tolerance = max(normalizedBounds.width * Constants.bridgeToleranceRatio,
                            Constants.minimumTolerance)
        guard abs(bridgeX - geometricBaseline) <= tolerance else {
            return geometricBaseline
        }

        return (bridgeX + geometricBaseline) * 0.5
    }

    // MARK: - Baselines geometricos
    /// Gera a linha media principal a partir do rosto, pupilas e suporte 3D coerente.
    private static func resolvedGeometricBaseline(faceMidlineX: CGFloat,
                                                  pupilMidlineX: CGFloat?,
                                                  captureX: CGFloat?,
                                                  normalizedBounds: NormalizedRect) -> CGFloat {
        let fallbackX = normalizedBounds.x + (normalizedBounds.width * 0.5)
        let twoDimensionalBaseline = resolvedTwoDimensionalBaseline(faceMidlineX: faceMidlineX,
                                                                    pupilMidlineX: pupilMidlineX)

        guard let captureX else {
            return twoDimensionalBaseline ?? faceMidlineX
        }

        guard let twoDimensionalBaseline else { return captureX }

        let tolerance = max(normalizedBounds.width * Constants.bridgeToleranceRatio,
                            Constants.minimumTolerance)
        guard abs(captureX - twoDimensionalBaseline) <= tolerance else {
            return twoDimensionalBaseline
        }

        let weighted = (twoDimensionalBaseline + (captureX * Constants.captureWeight)) /
            (1 + Constants.captureWeight)
        return clamped(candidate: weighted, within: normalizedBounds, fallback: fallbackX)
    }

    /// Combina rosto e pupilas sem deixar um unico landmark dominar a linha media.
    private static func resolvedTwoDimensionalBaseline(faceMidlineX: CGFloat,
                                                       pupilMidlineX: CGFloat?) -> CGFloat? {
        guard let pupilMidlineX else { return faceMidlineX }
        return (faceMidlineX + pupilMidlineX) * 0.5
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
