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
}

extension PostCaptureMeasurementError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreliableCalibration:
            return "Calibração inválida. Refaça a captura garantindo o uso dos sensores de profundidade."
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

    // MARK: - Inicialização
    init(configuration: PostCaptureConfiguration,
         centralPoint: NormalizedPoint,
         scale: PostCaptureScale) {
        self.configuration = configuration
        self.centralPoint = centralPoint.clamped()
        self.scale = scale
    }

    // MARK: - Interface Pública
    /// Retorna `PostCaptureMetrics` calculado a partir da configuração atual, lançando erro quando a calibração não é confiável.
    func makeMetrics() throws -> PostCaptureMetrics {
        guard scale.isReliable else { throw PostCaptureMeasurementError.unreliableCalibration }

        let horizontalReference = Double(scale.horizontalReferenceMM)
        let verticalReference = Double(scale.verticalReferenceMM)

        // Normaliza os olhos para garantir que as barras estejam ordenadas corretamente.
        let normalizedRight = configuration.rightEye.normalized(centralX: centralPoint.x)
        let normalizedLeft = configuration.leftEye.normalized(centralX: centralPoint.x)

        let rightHorizontal = horizontalMillimeters(between: normalizedRight.temporalBarX,
                                                    and: normalizedRight.nasalBarX,
                                                    reference: horizontalReference)
        let leftHorizontal = horizontalMillimeters(between: normalizedLeft.temporalBarX,
                                                   and: normalizedLeft.nasalBarX,
                                                   reference: horizontalReference)

        let rightVertical = verticalMillimeters(between: normalizedRight.inferiorBarY,
                                                and: normalizedRight.superiorBarY,
                                                reference: verticalReference)
        let leftVertical = verticalMillimeters(between: normalizedLeft.inferiorBarY,
                                               and: normalizedLeft.superiorBarY,
                                               reference: verticalReference)

        let rightDNP = horizontalMillimeters(between: normalizedRight.pupil.x,
                                             and: centralPoint.x,
                                             reference: horizontalReference)
        let leftDNP = horizontalMillimeters(between: normalizedLeft.pupil.x,
                                            and: centralPoint.x,
                                            reference: horizontalReference)

        let rightAltura = verticalMillimeters(between: normalizedRight.inferiorBarY,
                                              and: normalizedRight.pupil.y,
                                              reference: verticalReference)
        let leftAltura = verticalMillimeters(between: normalizedLeft.inferiorBarY,
                                             and: normalizedLeft.pupil.y,
                                             reference: verticalReference)

        let ponte = horizontalMillimeters(between: normalizedLeft.nasalBarX,
                                          and: normalizedRight.nasalBarX,
                                          reference: horizontalReference)

        let rightSummary = EyeMeasurementSummary(horizontalMaior: rightHorizontal,
                                                 verticalMaior: rightVertical,
                                                 dnp: rightDNP,
                                                 alturaPupilar: rightAltura)
        let leftSummary = EyeMeasurementSummary(horizontalMaior: leftHorizontal,
                                                verticalMaior: leftVertical,
                                                dnp: leftDNP,
                                                alturaPupilar: leftAltura)

        return PostCaptureMetrics(rightEye: rightSummary,
                                  leftEye: leftSummary,
                                  ponte: ponte)
    }

    // MARK: - Conversões Auxiliares
    /// Converte um deslocamento horizontal normalizado em milímetros considerando a calibração válida.
    private func horizontalMillimeters(between first: CGFloat,
                                       and second: CGFloat,
                                       reference: Double) -> Double {
        sanitizedMillimeters(from: Double(abs(first - second)) * reference)
    }

    /// Converte um deslocamento vertical normalizado em milímetros considerando a calibração válida.
    private func verticalMillimeters(between first: CGFloat,
                                     and second: CGFloat,
                                     reference: Double) -> Double {
        sanitizedMillimeters(from: Double(abs(first - second)) * reference)
    }

    /// Garante que valores inválidos não contaminem o resumo final.
    private func sanitizedMillimeters(from value: Double) -> Double {
        guard value.isFinite, value >= 0 else { return 0 }
        let precision = 0.1
        return (value / precision).rounded(.toNearestOrAwayFromZero) * precision
    }
}
