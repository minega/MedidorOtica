//
//  PostCaptureMeasurementCalculator.swift
//  MedidorOticaApp
//
//  Calcula todas as métricas pós-captura utilizando valores normalizados e calibração real.
//

import Foundation
import CoreGraphics

// MARK: - Erros de cálculo
/// Possíveis falhas encontradas durante o cálculo das métricas finais.
enum PostCaptureMeasurementError: Error, Equatable {
    case unreliableCalibration
    case invalidGeometry(String)
    case implausibleMeasurement(String)
}

extension PostCaptureMeasurementError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreliableCalibration:
            return "Calibração inválida. Refaça a captura garantindo o uso dos sensores de profundidade."
        case .invalidGeometry(let message):
            return message
        case .implausibleMeasurement(let message):
            return message
        }
    }
}

// MARK: - Calculadora de Métricas Pós-Captura
/// Consolida os cálculos das medidas finais em milímetros garantindo o uso da calibração válida.
struct PostCaptureMeasurementCalculator {
    // MARK: - Dependências
    private let configuration: PostCaptureConfiguration
    private let centralPoint: NormalizedPoint
    private let scale: PostCaptureScale
    private let eyeGeometrySnapshot: CaptureEyeGeometrySnapshot?

    // MARK: - Inicialização
    init(configuration: PostCaptureConfiguration,
         centralPoint: NormalizedPoint,
         scale: PostCaptureScale,
         eyeGeometrySnapshot: CaptureEyeGeometrySnapshot? = nil) {
        self.configuration = configuration
        self.centralPoint = centralPoint.clamped()
        self.scale = scale
        self.eyeGeometrySnapshot = eyeGeometrySnapshot
    }

    // MARK: - Interface Pública
    /// Retorna `PostCaptureMetrics` calculado a partir da configuração atual, lançando erro quando a calibração não é confiável.
    func makeMetrics() throws -> PostCaptureMetrics {
        guard scale.isReliable else { throw PostCaptureMeasurementError.unreliableCalibration }

        let geometry = try PostCaptureMeasurementValidator(configuration: configuration,
                                                           centralPoint: centralPoint).validate()
        let normalizedRight = geometry.rightEye
        let normalizedLeft = geometry.leftEye

        let rightHorizontal = horizontalMillimeters(between: normalizedRight.temporalBarX,
                                                    and: normalizedRight.nasalBarX,
                                                    at: normalizedRight.pupil.y)
        let leftHorizontal = horizontalMillimeters(between: normalizedLeft.temporalBarX,
                                                   and: normalizedLeft.nasalBarX,
                                                   at: normalizedLeft.pupil.y)

        let rightVertical = verticalMillimeters(between: normalizedRight.inferiorBarY,
                                                and: normalizedRight.superiorBarY,
                                                at: normalizedRight.pupil.x)
        let leftVertical = verticalMillimeters(between: normalizedLeft.inferiorBarY,
                                               and: normalizedLeft.superiorBarY,
                                               at: normalizedLeft.pupil.x)

        let rightDNP = horizontalMillimeters(between: normalizedRight.pupil.x,
                                             and: centralPoint.x,
                                             at: midpoint(normalizedRight.pupil.y, centralPoint.y))
        let leftDNP = horizontalMillimeters(between: normalizedLeft.pupil.x,
                                            and: centralPoint.x,
                                            at: midpoint(normalizedLeft.pupil.y, centralPoint.y))

        let rightAltura = verticalMillimeters(between: normalizedRight.inferiorBarY,
                                              and: normalizedRight.pupil.y,
                                              at: normalizedRight.pupil.x)
        let leftAltura = verticalMillimeters(between: normalizedLeft.inferiorBarY,
                                             and: normalizedLeft.pupil.y,
                                             at: normalizedLeft.pupil.x)

        let ponte = horizontalMillimeters(between: normalizedLeft.nasalBarX,
                                          and: normalizedRight.nasalBarX,
                                          at: centralPoint.y)

        let rightSummary = EyeMeasurementSummary(horizontalMaior: rightHorizontal,
                                                 verticalMaior: rightVertical,
                                                 dnp: rightDNP,
                                                 alturaPupilar: rightAltura)
        let leftSummary = EyeMeasurementSummary(horizontalMaior: leftHorizontal,
                                                verticalMaior: leftVertical,
                                                dnp: leftDNP,
                                                alturaPupilar: leftAltura)
        let farDNP = PostCaptureFarDNPResolver.resolve(rightPupilNear: normalizedRight.pupil,
                                                       leftPupilNear: normalizedLeft.pupil,
                                                       centralPoint: centralPoint,
                                                       scale: scale,
                                                       eyeGeometry: eyeGeometrySnapshot)

        let metrics = PostCaptureMetrics(rightEye: rightSummary,
                                         leftEye: leftSummary,
                                         ponte: ponte,
                                         rightDNPFar: farDNP.rightDNPFar,
                                         leftDNPFar: farDNP.leftDNPFar,
                                         farDNPConfidence: farDNP.confidence,
                                         farDNPConfidenceReason: farDNP.confidenceReason)
        try validatePlausibility(of: metrics)
        return metrics
    }

    // MARK: - Conversões Auxiliares
    /// Converte um deslocamento horizontal normalizado em milímetros considerando a calibração válida.
    private func horizontalMillimeters(between first: CGFloat,
                                       and second: CGFloat,
                                       at y: CGFloat) -> Double {
        sanitizedMillimeters(from: scale.horizontalMillimeters(between: first,
                                                               and: second,
                                                               at: y))
    }

    /// Converte um deslocamento vertical normalizado em milímetros considerando a calibração válida.
    private func verticalMillimeters(between first: CGFloat,
                                     and second: CGFloat,
                                     at x: CGFloat) -> Double {
        sanitizedMillimeters(from: scale.verticalMillimeters(between: first,
                                                             and: second,
                                                             at: x))
    }

    /// Garante que valores inválidos não contaminem o resumo final respeitando precisão de 0,01 mm.
    private func sanitizedMillimeters(from value: Double) -> Double {
        guard value.isFinite, value >= 0 else { return 0 }
        let precision = 0.01
        return (value / precision).rounded(.toNearestOrAwayFromZero) * precision
    }

    /// Bloqueia medidas fora de domínio para evitar resumos absurdos.
    private func validatePlausibility(of metrics: PostCaptureMetrics) throws {
        try validate(metric: metrics.rightEye.horizontalMaior,
                     within: 20...90,
                     message: "A largura do olho direito ficou fora da faixa plausível.")
        try validate(metric: metrics.leftEye.horizontalMaior,
                     within: 20...90,
                     message: "A largura do olho esquerdo ficou fora da faixa plausível.")
        try validate(metric: metrics.rightEye.verticalMaior,
                     within: 10...80,
                     message: "A altura do olho direito ficou fora da faixa plausível.")
        try validate(metric: metrics.leftEye.verticalMaior,
                     within: 10...80,
                     message: "A altura do olho esquerdo ficou fora da faixa plausível.")
        try validate(metric: metrics.rightEye.dnp,
                     within: 10...45,
                     message: "A DNP do olho direito ficou fora da faixa plausível.")
        try validate(metric: metrics.leftEye.dnp,
                     within: 10...45,
                     message: "A DNP do olho esquerdo ficou fora da faixa plausível.")
        try validate(metric: metrics.rightDNPFar,
                     within: 10...45,
                     message: "A DNP de longe do olho direito ficou fora da faixa plausível.")
        try validate(metric: metrics.leftDNPFar,
                     within: 10...45,
                     message: "A DNP de longe do olho esquerdo ficou fora da faixa plausível.")
        try validate(metric: metrics.rightEye.alturaPupilar,
                     within: 5...40,
                     message: "A altura pupilar do olho direito ficou fora da faixa plausível.")
        try validate(metric: metrics.leftEye.alturaPupilar,
                     within: 5...40,
                     message: "A altura pupilar do olho esquerdo ficou fora da faixa plausível.")
        try validate(metric: metrics.ponte,
                     within: 5...35,
                     message: "A ponte ficou fora da faixa plausível.")
    }

    private func validate(metric value: Double,
                          within range: ClosedRange<Double>,
                          message: String) throws {
        guard value.isFinite, range.contains(value) else {
            throw PostCaptureMeasurementError.implausibleMeasurement(message)
        }
    }

    private func midpoint(_ first: CGFloat,
                          _ second: CGFloat) -> CGFloat {
        (first + second) * 0.5
    }
}
