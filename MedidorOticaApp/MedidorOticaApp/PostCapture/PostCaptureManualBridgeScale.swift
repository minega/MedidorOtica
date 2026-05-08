//
//  PostCaptureManualBridgeScale.swift
//  MedidorOticaApp
//
//  Calcula a escala do modo Mono usando a ponte real e as barras nasais ajustadas.
//

import CoreGraphics
import Foundation

// MARK: - Escala manual por ponte
/// Resolve uma calibracao plana quando nao existe sensor de profundidade traseiro.
struct PostCaptureManualBridgeScale {
    private enum Constants {
        static let minimumBridgeNormalizedWidth: CGFloat = 0.006
    }

    /// Cria uma escala usando a distancia entre as barras nasais como referencia real.
    static func makeScale(configuration: PostCaptureConfiguration,
                          centralPoint: NormalizedPoint,
                          imageSize: CGSize,
                          requestedBridgeMM: Double) throws -> PostCaptureScale {
        guard requestedBridgeMM.isFinite,
              PostCaptureBridgeReferenceLimits.plausibleBridgeMM.contains(requestedBridgeMM) else {
            throw PostCaptureMeasurementError.implausibleMeasurement("Informe uma ponte real entre 5 e 35 mm.")
        }

        guard imageSize.width > 0, imageSize.height > 0 else {
            throw PostCaptureMeasurementError.implausibleMeasurement("Imagem invalida para calcular a escala pela ponte.")
        }

        let resolved = configurationForCentralPoint(centralPoint,
                                                    configuration: configuration)
        let bridgeWidth = abs(resolved.leftEye.nasalBarX - resolved.rightEye.nasalBarX)
        guard bridgeWidth.isFinite,
              bridgeWidth >= Constants.minimumBridgeNormalizedWidth else {
            throw PostCaptureMeasurementError.implausibleMeasurement("Ajuste as barras nasais antes de informar a ponte.")
        }

        let horizontalReference = requestedBridgeMM / Double(bridgeWidth)
        let verticalReference = horizontalReference * Double(imageSize.height / imageSize.width)
        let calibration = PostCaptureCalibration(horizontalReferenceMM: horizontalReference,
                                                verticalReferenceMM: verticalReference)
        guard calibration.isPlausibleMeasurementScale else {
            throw PostCaptureMeasurementError.implausibleMeasurement("A ponte informada gerou uma escala fora da faixa plausivel.")
        }

        return PostCaptureScale(calibration: calibration,
                                localCalibration: .empty,
                                acceptsManualBridgeCalibration: true)
    }

    private static func configurationForCentralPoint(_ centralPoint: NormalizedPoint,
                                                     configuration: PostCaptureConfiguration) -> PostCaptureConfiguration {
        let clampedPoint = centralPoint.clamped()
        return PostCaptureConfiguration(centralPoint: clampedPoint,
                                        rightEye: configuration.rightEye.normalized(centralX: clampedPoint.x),
                                        leftEye: configuration.leftEye.normalized(centralX: clampedPoint.x),
                                        faceBounds: configuration.faceBounds)
    }
}
