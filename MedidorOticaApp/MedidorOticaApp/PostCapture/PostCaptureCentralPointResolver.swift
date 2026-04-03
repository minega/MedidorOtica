//
//  PostCaptureCentralPointResolver.swift
//  MedidorOticaApp
//
//  Resolve o eixo X do PC usando a melhor referencia geometrica disponivel.
//

import CoreGraphics

// MARK: - Resolucao do PC
/// Decide o eixo X do PC combinando simetria facial, pupilas e ponte nasal.
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
        /// Mantem a ponte apenas como refinamento quando ela concorda com a simetria facial.
        static let bridgeToleranceRatio: CGFloat = 0.03
        /// Evita tolerancias pequenas demais em rostos muito estreitos.
        static let minimumTolerance: CGFloat = 0.008
        /// Mantem a linha principal mais fiel ao eixo optico das pupilas.
        static let pupilWeight: CGFloat = 2
        /// A linha mediana so ajuda quando as pupilas nao conseguem estabilizar o eixo.
        static let medianLineWeight: CGFloat = 1
        /// A ponte refina sem voltar a dominar o PC.
        static let bridgeBlendFactor: CGFloat = 0.25
    }

    // MARK: - Interface principal
    /// Resolve o eixo X final do PC priorizando a propria foto e usando a ponte apenas como refinamento.
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
        return clamped(candidate: refinedX,
                       within: normalizedBounds,
                       fallback: geometricBaseline)
    }

    // MARK: - Baselines geometricos
    /// Gera a linha media principal a partir da propria foto, sem deixar a ponte dominar o eixo.
    private static func resolvedGeometricBaseline(faceMidlineX: CGFloat,
                                                  pupilMidlineX: CGFloat?,
                                                  medianLineX: CGFloat?,
                                                  normalizedBounds: NormalizedRect) -> CGFloat {
        let fallbackX = normalizedBounds.x + (normalizedBounds.width * 0.5)
        let twoDimensionalBaseline = resolvedTwoDimensionalBaseline(faceMidlineX: faceMidlineX,
                                                                    pupilMidlineX: pupilMidlineX,
                                                                    medianLineX: medianLineX)
        return clamped(candidate: twoDimensionalBaseline ?? faceMidlineX,
                       within: normalizedBounds,
                       fallback: fallbackX)
    }

    /// Combina simetria facial e pupilas, usando a linha mediana apenas como apoio.
    private static func resolvedTwoDimensionalBaseline(faceMidlineX: CGFloat,
                                                       pupilMidlineX: CGFloat?,
                                                       medianLineX: CGFloat?) -> CGFloat? {
        if let pupilMidlineX {
            return ((pupilMidlineX * Constants.pupilWeight) + faceMidlineX) /
                (Constants.pupilWeight + 1)
        }

        if let medianLineX {
            return ((medianLineX * Constants.medianLineWeight) + faceMidlineX) /
                (Constants.medianLineWeight + 1)
        }

        return faceMidlineX
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
