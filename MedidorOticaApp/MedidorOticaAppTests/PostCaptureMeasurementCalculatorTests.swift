//
//  PostCaptureMeasurementCalculatorTests.swift
//  MedidorOticaAppTests
//
//  Verifica se a calculadora de métricas converte valores normalizados em milímetros corretamente.
//

import Testing
@testable import MedidorOticaApp

struct PostCaptureMeasurementCalculatorTests {
    // MARK: - Cenário padrão com calibração conhecida
    @Test func convertsNormalizedDistancesUsingCalibration() async throws {
        let calibration = PostCaptureCalibration(horizontalReferenceMM: 120, verticalReferenceMM: 80)
        let scale = PostCaptureScale(calibration: calibration)

        // Posição do ponto central no meio da imagem.
        let center = NormalizedPoint(x: 0.5, y: 0.5)

        // Configuração com barras já ordenadas em ambos os eixos.
        let rightEye = EyeMeasurementData(pupil: NormalizedPoint(x: 0.4, y: 0.55),
                                          nasalBarX: 0.46,
                                          temporalBarX: 0.22,
                                          inferiorBarY: 0.72,
                                          superiorBarY: 0.32)

        let leftEye = EyeMeasurementData(pupil: NormalizedPoint(x: 0.62, y: 0.53),
                                         nasalBarX: 0.54,
                                         temporalBarX: 0.86,
                                         inferiorBarY: 0.74,
                                         superiorBarY: 0.34)

        let configuration = PostCaptureConfiguration(centralPoint: center,
                                                     rightEye: rightEye,
                                                     leftEye: leftEye,
                                                     faceBounds: NormalizedRect())

        let calculator = PostCaptureMeasurementCalculator(configuration: configuration,
                                                          centralPoint: center,
                                                          scale: scale)

        let metrics = try calculator.makeMetrics()

        // Cada valor esperado resulta de distance * referência mm (120 ou 80).
        #expect(metrics.rightEye.horizontalMaior.rounded() == 29)
        #expect(metrics.leftEye.horizontalMaior.rounded() == 38)
        #expect(metrics.rightEye.verticalMaior.rounded() == 32)
        #expect(metrics.leftEye.verticalMaior.rounded() == 32)
        #expect(metrics.rightEye.dnp.rounded() == 12)
        #expect(metrics.leftEye.dnp.rounded() == 14)
        #expect(metrics.rightEye.alturaPupilar.rounded() == 14)
        #expect(metrics.leftEye.alturaPupilar.rounded() == 17)
        #expect(metrics.ponte.rounded() == 10)
    }

    // MARK: - Fallback para calibração padrão
    @Test func fallsBackToDefaultCalibrationWhenValuesAreInvalid() async throws {
        let invalidCalibration = PostCaptureCalibration(horizontalReferenceMM: 0,
                                                         verticalReferenceMM: .infinity)
        let scale = PostCaptureScale(calibration: invalidCalibration)
        let center = NormalizedPoint(x: 0.5, y: 0.5)
        let eye = EyeMeasurementData(pupil: NormalizedPoint(x: 0.55, y: 0.5),
                                     nasalBarX: 0.5,
                                     temporalBarX: 0.7,
                                     inferiorBarY: 0.6,
                                     superiorBarY: 0.4)
        let configuration = PostCaptureConfiguration(centralPoint: center,
                                                     rightEye: eye,
                                                     leftEye: eye,
                                                     faceBounds: NormalizedRect())
        let calculator = PostCaptureMeasurementCalculator(configuration: configuration,
                                                          centralPoint: center,
                                                          scale: scale)
        do {
            _ = try calculator.makeMetrics()
            #expect(false)
        } catch let error as PostCaptureMeasurementError {
            #expect(error == .unreliableCalibration)
        } catch {
            #expect(false)
        }
    }
}
