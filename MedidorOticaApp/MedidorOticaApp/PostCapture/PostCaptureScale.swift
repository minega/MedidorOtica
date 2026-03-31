//
//  PostCaptureScale.swift
//  MedidorOticaApp
//
//  Estruturas responsáveis por definir a calibração e as conversões de escala pós-captura.
//

import CoreGraphics

// MARK: - Calibração Pós-Captura
/// Armazena os valores de referência utilizados para converter pontos normalizados em milímetros.
struct PostCaptureCalibration: Codable, Equatable {
    /// Valor em milímetros correspondente a toda a largura útil da imagem normalizada.
    var horizontalReferenceMM: Double
    /// Valor em milímetros correspondente a toda a altura útil da imagem normalizada.
    var verticalReferenceMM: Double

    /// Calibração padrão utilizada quando não é possível calcular valores reais.
    static let `default` = PostCaptureCalibration(horizontalReferenceMM: 120, verticalReferenceMM: 80)
}

// MARK: - Confiabilidade da calibração
extension PostCaptureCalibration {
    /// Indica se os valores foram obtidos com sensores de profundidade e fornecem precisão submilimétrica.
    var isReliable: Bool {
        guard horizontalReferenceMM.isFinite,
              verticalReferenceMM.isFinite,
              horizontalReferenceMM > 0,
              verticalReferenceMM > 0 else { return false }

        // Rejeita a calibração padrão pois ela não provém dos sensores TrueDepth/LiDAR.
        let matchesDefault = abs(horizontalReferenceMM - PostCaptureCalibration.default.horizontalReferenceMM) < 0.0001 &&
                             abs(verticalReferenceMM - PostCaptureCalibration.default.verticalReferenceMM) < 0.0001
        if matchesDefault { return false }

        // Aceita intervalo amplo, baseado em TrueDepth a 25–60 cm: mm/pixel típico ~0.03–0.6.
        let horizontalRange: ClosedRange<Double> = 50...900
        let verticalRange: ClosedRange<Double> = 50...900
        guard horizontalRange.contains(horizontalReferenceMM),
              verticalRange.contains(verticalReferenceMM) else { return false }

        // Evita proporções extremamente distorcidas.
        let ratio = horizontalReferenceMM / verticalReferenceMM
        return ratio.isFinite && ratio > 0.5 && ratio < 2.2
    }
}

// MARK: - Escala Local da Face
/// Amostra local da escala facial obtida do TrueDepth em um ponto projetado da imagem.
struct LocalFaceScaleSample: Codable, Equatable {
    var point: NormalizedPoint
    var horizontalReferenceMM: Double
    var verticalReferenceMM: Double
    var depthMM: Double
}

/// Mapa local de escala usado para compensar deformacao de perspectiva ao longo do rosto.
struct LocalFaceScaleCalibration: Codable, Equatable {
    var samples: [LocalFaceScaleSample]

    static let empty = LocalFaceScaleCalibration(samples: [])

    private enum LocalIntegration {
        static let minimumReliableSamples = 24
        static let integrationSegments = 48
    }

    /// Exige uma quantidade minima de amostras validas antes de ativar a medicao local.
    var isReliable: Bool {
        samples.count >= LocalIntegration.minimumReliableSamples
    }

    /// Consolida a malha local em uma calibração global de fallback para telas antigas do fluxo.
    var globalCalibration: PostCaptureCalibration? {
        guard isReliable else { return nil }
        guard let horizontal = robustMean(samples.map(\.horizontalReferenceMM)),
              let vertical = robustMean(samples.map(\.verticalReferenceMM)),
              horizontal.isFinite,
              vertical.isFinite,
              horizontal > 0,
              vertical > 0 else {
            return nil
        }

        return PostCaptureCalibration(horizontalReferenceMM: horizontal,
                                      verticalReferenceMM: vertical)
    }

    /// Retorna a referencia horizontal local mais coerente para o ponto informado.
    func horizontalReference(at point: NormalizedPoint,
                             fallback: Double) -> Double {
        weightedReference(at: point,
                          keyPath: \.horizontalReferenceMM,
                          fallback: fallback)
    }

    /// Retorna a referencia vertical local mais coerente para o ponto informado.
    func verticalReference(at point: NormalizedPoint,
                           fallback: Double) -> Double {
        weightedReference(at: point,
                          keyPath: \.verticalReferenceMM,
                          fallback: fallback)
    }

    /// Integra a escala local ao longo de um segmento horizontal.
    func horizontalMillimeters(between first: CGFloat,
                               and second: CGFloat,
                               at y: CGFloat,
                               fallbackReference: Double) -> Double {
        integratedDistance(from: NormalizedPoint(x: first, y: y),
                           to: NormalizedPoint(x: second, y: y),
                           fallbackReference: fallbackReference,
                           keyPath: \.horizontalReferenceMM)
    }

    /// Integra a escala local ao longo de um segmento vertical.
    func verticalMillimeters(between first: CGFloat,
                             and second: CGFloat,
                             at x: CGFloat,
                             fallbackReference: Double) -> Double {
        integratedDistance(from: NormalizedPoint(x: x, y: first),
                           to: NormalizedPoint(x: x, y: second),
                           fallbackReference: fallbackReference,
                           keyPath: \.verticalReferenceMM)
    }

    private func integratedDistance(from start: NormalizedPoint,
                                    to end: NormalizedPoint,
                                    fallbackReference: Double,
                                    keyPath: KeyPath<LocalFaceScaleSample, Double>) -> Double {
        let clampedStart = start.clamped()
        let clampedEnd = end.clamped()
        let segments = LocalIntegration.integrationSegments

        return (0..<segments).reduce(0) { partial, index in
            let t0 = CGFloat(index) / CGFloat(segments)
            let t1 = CGFloat(index + 1) / CGFloat(segments)
            let point0 = interpolatedPoint(from: clampedStart, to: clampedEnd, progress: t0)
            let point1 = interpolatedPoint(from: clampedStart, to: clampedEnd, progress: t1)
            let midpoint = interpolatedPoint(from: point0, to: point1, progress: 0.5)
            let localReference = weightedReference(at: midpoint,
                                                   keyPath: keyPath,
                                                   fallback: fallbackReference)
            return partial + (Double(segmentLength(from: point0, to: point1)) * localReference)
        }
    }

    private func weightedReference(at point: NormalizedPoint,
                                   keyPath: KeyPath<LocalFaceScaleSample, Double>,
                                   fallback: Double) -> Double {
        guard !samples.isEmpty else { return fallback }

        let clampedPoint = point.clamped()
        var nearestSample: LocalFaceScaleSample?
        var nearestDistance = Double.greatestFiniteMagnitude
        var weightedSum = 0.0
        var totalWeight = 0.0

        for sample in samples {
            let currentDistance = distance(from: sample.point, to: clampedPoint)
            if currentDistance < nearestDistance {
                nearestDistance = currentDistance
                nearestSample = sample
            }

            let weight = 1.0 / pow(max(currentDistance, 0.0005), 2.0)
            weightedSum += sample[keyPath: keyPath] * weight
            totalWeight += weight
        }

        if nearestDistance <= 0.0005, let nearestSample {
            return nearestSample[keyPath: keyPath]
        }

        guard totalWeight > 0 else { return fallback }
        return weightedSum / totalWeight
    }

    private func interpolatedPoint(from start: NormalizedPoint,
                                   to end: NormalizedPoint,
                                   progress: CGFloat) -> NormalizedPoint {
        NormalizedPoint(x: start.x + ((end.x - start.x) * progress),
                        y: start.y + ((end.y - start.y) * progress))
    }

    private func segmentLength(from start: NormalizedPoint,
                               to end: NormalizedPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func distance(from first: NormalizedPoint,
                          to second: NormalizedPoint) -> Double {
        Double(hypot(first.x - second.x, first.y - second.y))
    }

    private func robustMean(_ values: [Double]) -> Double? {
        let valid = values.filter { $0.isFinite }.sorted()
        guard !valid.isEmpty else { return nil }

        let trimCount = Int(Double(valid.count) * 0.10)
        let usable = Array(valid.dropFirst(trimCount).dropLast(trimCount))
        let valuesToUse = usable.isEmpty ? valid : usable
        let sum = valuesToUse.reduce(0, +)
        return sum / Double(valuesToUse.count)
    }
}

// MARK: - Conversões de Escala
/// Responsável por converter valores milimétricos para o espaço normalizado (0...1).
struct PostCaptureScale {
    /// Calibração de origem utilizada para garantir a conversão precisa.
    let calibration: PostCaptureCalibration
    /// Escala local derivada da malha 3D do TrueDepth para compensar perspectiva.
    let localCalibration: LocalFaceScaleCalibration
    /// Referência horizontal em milímetros para o intervalo normalizado completo.
    let horizontalReferenceMM: CGFloat
    /// Referência vertical em milímetros para o intervalo normalizado completo.
    let verticalReferenceMM: CGFloat

    /// Diâmetro padrão da pupila utilizado para desenhar o marcador.
    static let pupilDiameterMM: CGFloat = 2
    /// Altura ampliada das barras horizontais exibidas durante o ajuste vertical para facilitar o encaixe.
    static let verticalBarHeightMM: CGFloat = 75
    /// Comprimento ampliado das barras verticais exibidas durante o ajuste horizontal para maior precisão.
    static let horizontalBarLengthMM: CGFloat = 90
    /// Deslocamento nasal inicial solicitado pelo time de ótica.
    static let nasalOffsetMM: CGFloat = 9
    /// Deslocamento temporal inicial solicitado pelo time de ótica.
    static let temporalOffsetMM: CGFloat = 60
    /// Deslocamento inferior inicial para o ajuste das barras horizontais.
    static let inferiorOffsetMM: CGFloat = 25
    /// Deslocamento superior inicial para o ajuste das barras horizontais.
    static let superiorOffsetMM: CGFloat = 15

    /// Inicializa a escala garantindo que os valores sejam positivos.
    init(calibration: PostCaptureCalibration = .default,
         localCalibration: LocalFaceScaleCalibration = .empty) {
        self.calibration = calibration
        self.localCalibration = localCalibration
        self.horizontalReferenceMM = max(CGFloat(calibration.horizontalReferenceMM), 1)
        self.verticalReferenceMM = max(CGFloat(calibration.verticalReferenceMM), 1)
    }

    /// Informa se a calibração associada atende aos critérios de confiabilidade.
    var isReliable: Bool {
        calibration.isReliable || localCalibration.isReliable
    }

    /// Converte um valor em milímetros para escala horizontal normalizada (0...1).
    func normalizedHorizontal(_ millimeters: CGFloat) -> CGFloat {
        guard horizontalReferenceMM > 0 else { return 0 }
        let normalized = millimeters / horizontalReferenceMM
        return min(max(normalized, 0), 1)
    }

    /// Converte um valor em milímetros para escala horizontal normalizada respeitando a escala local.
    func normalizedHorizontal(_ millimeters: CGFloat,
                              at point: NormalizedPoint) -> CGFloat {
        guard localCalibration.isReliable else {
            return normalizedHorizontal(millimeters)
        }
        let reference = CGFloat(localCalibration.horizontalReference(at: point,
                                                                    fallback: Double(horizontalReferenceMM)))
        guard reference > 0 else { return normalizedHorizontal(millimeters) }
        let normalized = millimeters / reference
        return min(max(normalized, 0), 1)
    }

    /// Converte um valor em milímetros para escala vertical normalizada (0...1).
    func normalizedVertical(_ millimeters: CGFloat) -> CGFloat {
        guard verticalReferenceMM > 0 else { return 0 }
        let normalized = millimeters / verticalReferenceMM
        return min(max(normalized, 0), 1)
    }

    /// Converte um valor em milímetros para escala vertical normalizada respeitando a escala local.
    func normalizedVertical(_ millimeters: CGFloat,
                            at point: NormalizedPoint) -> CGFloat {
        guard localCalibration.isReliable else {
            return normalizedVertical(millimeters)
        }
        let reference = CGFloat(localCalibration.verticalReference(at: point,
                                                                  fallback: Double(verticalReferenceMM)))
        guard reference > 0 else { return normalizedVertical(millimeters) }
        let normalized = millimeters / reference
        return min(max(normalized, 0), 1)
    }

    /// Mede um segmento horizontal em milímetros usando a escala local quando ela estiver disponível.
    func horizontalMillimeters(between first: CGFloat,
                               and second: CGFloat,
                               at y: CGFloat) -> Double {
        guard localCalibration.isReliable else {
            return Double(abs(first - second)) * Double(horizontalReferenceMM)
        }
        return localCalibration.horizontalMillimeters(between: first,
                                                      and: second,
                                                      at: y,
                                                      fallbackReference: Double(horizontalReferenceMM))
    }

    /// Mede um segmento vertical em milímetros usando a escala local quando ela estiver disponível.
    func verticalMillimeters(between first: CGFloat,
                             and second: CGFloat,
                             at x: CGFloat) -> Double {
        guard localCalibration.isReliable else {
            return Double(abs(first - second)) * Double(verticalReferenceMM)
        }
        return localCalibration.verticalMillimeters(between: first,
                                                    and: second,
                                                    at: x,
                                                    fallbackReference: Double(verticalReferenceMM))
    }
}
