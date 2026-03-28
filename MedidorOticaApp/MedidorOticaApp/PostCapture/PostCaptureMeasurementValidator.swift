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

/// Diagnostico resumido da geometria antes do calculo final.
struct PostCaptureGeometryDiagnostic {
    let calibrationReliable: Bool
    let centralPointMessage: String
    let rightEyeMessage: String
    let leftEyeMessage: String
    let summaryMessage: String

    /// Indica se toda a geometria atual ja parece coerente.
    var isValid: Bool {
        summaryMessage == "Geometria coerente."
    }
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

    /// Retorna um diagnostico amigavel para a UI de depuracao das etapas manuais.
    func diagnostic(calibrationReliable: Bool) -> PostCaptureGeometryDiagnostic {
        let centralMessage = centralPointIssue() ?? "PC coerente."
        let rightMessage = eyeIssue(configuration.rightEye.normalized(centralX: centralPoint.x),
                                    label: "direito") ?? "Olho direito coerente."
        let leftMessage = eyeIssue(configuration.leftEye.normalized(centralX: centralPoint.x),
                                   label: "esquerdo") ?? "Olho esquerdo coerente."
        let summary = [centralPointIssue(),
                       eyeIssue(configuration.rightEye.normalized(centralX: centralPoint.x),
                                label: "direito"),
                       eyeIssue(configuration.leftEye.normalized(centralX: centralPoint.x),
                                label: "esquerdo"),
                       calibrationReliable ? nil : "Calibracao invalida para medir."]
            .compactMap { $0 }
            .first ?? "Geometria coerente."

        return PostCaptureGeometryDiagnostic(calibrationReliable: calibrationReliable,
                                             centralPointMessage: centralMessage,
                                             rightEyeMessage: rightMessage,
                                             leftEyeMessage: leftMessage,
                                             summaryMessage: summary)
    }

    private func validateCentralPoint() throws {
        if let issue = centralPointIssue() {
            throw PostCaptureMeasurementError.invalidGeometry(issue)
        }
    }

    private func validateEye(_ eye: EyeMeasurementData, label: String) throws {
        if let issue = eyeIssue(eye, label: label) {
            throw PostCaptureMeasurementError.invalidGeometry(issue)
        }
    }

    private func centralPointIssue() -> String? {
        guard centralPoint.x.isFinite, centralPoint.y.isFinite else {
            return "O ponto central ficou invalido. Reposicione os marcadores."
        }

        guard (0...1).contains(centralPoint.x), (0...1).contains(centralPoint.y) else {
            return "O ponto central saiu da area util da imagem."
        }

        return nil
    }

    private func eyeIssue(_ eye: EyeMeasurementData,
                          label: String) -> String? {
        let values = [eye.pupil.x, eye.pupil.y, eye.nasalBarX, eye.temporalBarX, eye.inferiorBarY, eye.superiorBarY]
        guard values.allSatisfy(\.isFinite) else {
            return "Os marcadores do olho \(label) estao invalidos."
        }

        guard values.allSatisfy({ (0...1).contains($0) }) else {
            return "Os marcadores do olho \(label) sairam da imagem."
        }

        let horizontalWidth = abs(eye.temporalBarX - eye.nasalBarX)
        let verticalHeight = abs(eye.inferiorBarY - eye.superiorBarY)

        guard horizontalWidth >= 0.01 else {
            return "A largura do olho \(label) ficou insuficiente."
        }

        guard verticalHeight >= 0.01 else {
            return "A altura do olho \(label) ficou insuficiente."
        }

        let minHorizontal = min(eye.nasalBarX, eye.temporalBarX)
        let maxHorizontal = max(eye.nasalBarX, eye.temporalBarX)
        guard eye.pupil.x >= minHorizontal, eye.pupil.x <= maxHorizontal else {
            return "A pupila do olho \(label) precisa ficar entre as barras verticais."
        }

        if let sideIssue = eyeSideIssue(eye, label: label) {
            return sideIssue
        }

        guard eye.pupil.y >= eye.superiorBarY, eye.pupil.y <= eye.inferiorBarY else {
            return "A pupila do olho \(label) precisa ficar entre as barras horizontais."
        }

        return nil
    }

    private func eyeSideIssue(_ eye: EyeMeasurementData,
                              label: String) -> String? {
        let eyeOnRightSide = eye.pupil.x >= centralPoint.x

        if eyeOnRightSide {
            guard eye.nasalBarX >= centralPoint.x,
                  eye.temporalBarX >= eye.nasalBarX else {
                return "As barras do olho \(label) ficaram invertidas em relacao ao PC."
            }
            return nil
        }

        guard eye.nasalBarX <= centralPoint.x,
              eye.temporalBarX <= eye.nasalBarX else {
            return "As barras do olho \(label) ficaram invertidas em relacao ao PC."
        }

        return nil
    }
}
