//
//  PostCaptureMeasurementValidator.swift
//  MedidorOticaApp
//
//  Valida a geometria dos marcadores antes do calculo final.
//

import Foundation
import CoreGraphics

// MARK: - Geometria validada
/// Estrutura auxiliar com os olhos ja normalizados e ordenados.
struct ValidatedMeasurementGeometry {
    let rightEye: EyeMeasurementData
    let leftEye: EyeMeasurementData
}

// MARK: - Validador
/// Garante que os marcadores formem uma geometria mensuravel.
struct PostCaptureMeasurementValidator {
    let configuration: PostCaptureConfiguration
    let centralPoint: NormalizedPoint

    /// Retorna os dados validados e normalizados para o calculo final.
    func validate() throws -> ValidatedMeasurementGeometry {
        try validateCentralPoint()

        var normalizedRight = configuration.rightEye.normalized(centralX: centralPoint.x)
        var normalizedLeft = configuration.leftEye.normalized(centralX: centralPoint.x)

        if normalizedRight.pupil.x > normalizedLeft.pupil.x {
            swap(&normalizedRight, &normalizedLeft)
        }

        try validateEye(normalizedRight, label: "direito")
        try validateEye(normalizedLeft, label: "esquerdo")

        return ValidatedMeasurementGeometry(rightEye: normalizedRight,
                                            leftEye: normalizedLeft)
    }

    private func validateCentralPoint() throws {
        guard centralPoint.x.isFinite, centralPoint.y.isFinite else {
            throw PostCaptureMeasurementError.invalidGeometry("O ponto central ficou invalido. Reposicione os marcadores.")
        }

        guard (0...1).contains(centralPoint.x), (0...1).contains(centralPoint.y) else {
            throw PostCaptureMeasurementError.invalidGeometry("O ponto central saiu da area util da imagem.")
        }
    }

    private func validateEye(_ eye: EyeMeasurementData, label: String) throws {
        let values = [eye.pupil.x, eye.pupil.y, eye.nasalBarX, eye.temporalBarX, eye.inferiorBarY, eye.superiorBarY]
        guard values.allSatisfy(\.isFinite) else {
            throw PostCaptureMeasurementError.invalidGeometry("Os marcadores do olho \(label) estao invalidos.")
        }

        guard values.allSatisfy({ (0...1).contains($0) }) else {
            throw PostCaptureMeasurementError.invalidGeometry("Os marcadores do olho \(label) sairam da imagem.")
        }

        let horizontalWidth = abs(eye.temporalBarX - eye.nasalBarX)
        let verticalHeight = abs(eye.inferiorBarY - eye.superiorBarY)

        guard horizontalWidth >= 0.01 else {
            throw PostCaptureMeasurementError.invalidGeometry("A largura do olho \(label) ficou insuficiente.")
        }

        guard verticalHeight >= 0.01 else {
            throw PostCaptureMeasurementError.invalidGeometry("A altura do olho \(label) ficou insuficiente.")
        }

        let minHorizontal = min(eye.nasalBarX, eye.temporalBarX)
        let maxHorizontal = max(eye.nasalBarX, eye.temporalBarX)
        guard eye.pupil.x >= minHorizontal, eye.pupil.x <= maxHorizontal else {
            throw PostCaptureMeasurementError.invalidGeometry("A pupila do olho \(label) precisa ficar entre as barras verticais.")
        }

        guard eye.pupil.y >= eye.superiorBarY, eye.pupil.y <= eye.inferiorBarY else {
            throw PostCaptureMeasurementError.invalidGeometry("A pupila do olho \(label) precisa ficar entre as barras horizontais.")
        }
    }
}
