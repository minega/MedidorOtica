//
//  PostCaptureCentralPointResolver.swift
//  MedidorOticaApp
//
//  Resolve o eixo X do PC usando a linha média facial útil na altura óptica das pupilas.
//

import CoreGraphics

// MARK: - Resolução do PC
/// Decide o eixo X do PC combinando linha média facial, simetria pupilar e ponte nasal.
struct PostCaptureCentralPointResolver {
    // MARK: - Tipos auxiliares
    struct Candidates {
        let bridgeX: CGFloat?
        let captureX: CGFloat?
        let pupilMidlineX: CGFloat?
        let medianLineX: CGFloat?
        let faceMidlineX: CGFloat
    }

    private enum Constants {
        /// Mantém a ponte apenas como refinamento quando ela concorda fortemente com a linha média.
        static let bridgeToleranceRatio: CGFloat = 0.022
        /// Evita tolerâncias pequenas demais em rostos muito estreitos.
        static let minimumTolerance: CGFloat = 0.006
        /// A linha média anatômica é a referência principal do eixo X do PC.
        static let medianLineWeight: CGFloat = 4
        /// As pupilas corrigem a linha média quando a foto vier muito simétrica.
        static let pupilWeight: CGFloat = 2
        /// O contorno geral do rosto entra apenas como estabilizador fraco.
        static let faceWeight: CGFloat = 1
        /// A ponte apenas refina o eixo final, nunca domina o PC.
        static let bridgeBlendFactor: CGFloat = 0.18
    }

    // MARK: - Interface principal
    /// Resolve o eixo X final do PC priorizando a linha média facial corrigida pela própria foto.
    static func resolveX(using candidates: Candidates,
                         within normalizedBounds: NormalizedRect) -> CGFloat {
        let fallbackX = normalizedBounds.x + (normalizedBounds.width * 0.5)
        let faceMidlineX = clamped(candidate: candidates.faceMidlineX,
                                   within: normalizedBounds,
                                   fallback: fallbackX)
        let pupilMidlineX = validated(candidate: candidates.pupilMidlineX,
                                      within: normalizedBounds)
        let medianLineX = validated(candidate: candidates.medianLineX,
                                    within: normalizedBounds)
        let bridgeX = validated(candidate: candidates.bridgeX,
                                within: normalizedBounds)

        let geometricBaseline = resolvedGeometricBaseline(faceMidlineX: faceMidlineX,
                                                          pupilMidlineX: pupilMidlineX,
                                                          medianLineX: medianLineX,
                                                          normalizedBounds: normalizedBounds)

        guard let bridgeX else { return geometricBaseline }

        let tolerance = max(normalizedBounds.width * Constants.bridgeToleranceRatio,
                            Constants.minimumTolerance)
        guard abs(bridgeX - geometricBaseline) <= tolerance else {
            return geometricBaseline
        }

        let refinedX = geometricBaseline + ((bridgeX - geometricBaseline) * Constants.bridgeBlendFactor)
        return clamped(candidate: refinedX, within: normalizedBounds, fallback: geometricBaseline)
    }

    // MARK: - Baselines geométricos
    /// Gera a linha média principal a partir da banda óptica da própria foto.
    private static func resolvedGeometricBaseline(faceMidlineX: CGFloat,
                                                  pupilMidlineX: CGFloat?,
                                                  medianLineX: CGFloat?,
                                                  normalizedBounds: NormalizedRect) -> CGFloat {
        let weightedBaseline = weightedMean(faceMidlineX: faceMidlineX,
                                            pupilMidlineX: pupilMidlineX,
                                            medianLineX: medianLineX)
        return clamped(candidate: weightedBaseline ?? faceMidlineX,
                       within: normalizedBounds,
                       fallback: faceMidlineX)
    }

    /// Combina linha média anatômica, pupilas e contorno geral do rosto.
    private static func weightedMean(faceMidlineX: CGFloat,
                                     pupilMidlineX: CGFloat?,
                                     medianLineX: CGFloat?) -> CGFloat? {
        var weightedSum = faceMidlineX * Constants.faceWeight
        var totalWeight = Constants.faceWeight

        if let medianLineX {
            weightedSum += medianLineX * Constants.medianLineWeight
            totalWeight += Constants.medianLineWeight
        }

        if let pupilMidlineX {
            weightedSum += pupilMidlineX * Constants.pupilWeight
            totalWeight += Constants.pupilWeight
        }

        guard totalWeight > 0 else { return nil }
        return weightedSum / totalWeight
    }

    // MARK: - Validações
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
