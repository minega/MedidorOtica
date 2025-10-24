//
//  PostCaptureModels.swift
//  MedidorOticaApp
//
//  Modelos que armazenam os dados normalizados do fluxo pós-captura.
//

import Foundation
import CoreGraphics

// MARK: - Pontos Normalizados
/// Representa um ponto no espaço da imagem utilizando coordenadas normalizadas (0...1).
struct NormalizedPoint: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat

    /// Construtor com valores padrão centralizados.
    init(x: CGFloat = 0.5, y: CGFloat = 0.5) {
        self.x = x
        self.y = y
    }
}

extension NormalizedPoint {
    /// Converte um `CGPoint` absoluto para `NormalizedPoint` considerando dimensões fornecidas.
    /// - Parameters:
    ///   - point: Ponto em coordenadas absolutas.
    ///   - size: Dimensões totais utilizadas como referência.
    /// - Returns: Ponto normalizado clamped entre 0 e 1.
    static func fromAbsolute(_ point: CGPoint, size: CGSize) -> NormalizedPoint {
        guard size.width > 0, size.height > 0 else { return NormalizedPoint() }
        let normalizedX = min(max(point.x / size.width, 0), 1)
        let normalizedY = min(max(point.y / size.height, 0), 1)
        return NormalizedPoint(x: normalizedX, y: normalizedY)
    }

    /// Converte o ponto normalizado em coordenadas absolutas.
    /// - Parameter size: Dimensões de referência.
    /// - Returns: `CGPoint` na escala indicada.
    func absolute(in size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }

    /// Retorna uma versão espelhada horizontalmente considerando o ponto central informado.
    /// - Parameter centerX: Coordenada X do ponto central utilizado como espelho.
    func mirrored(around centerX: CGFloat) -> NormalizedPoint {
        let mirroredX = (2 * centerX) - x
        return NormalizedPoint(x: mirroredX, y: y)
    }

    /// Limita os valores para o intervalo 0...1.
    func clamped() -> NormalizedPoint {
        NormalizedPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}

// MARK: - Dados por olho
/// Armazena os pontos manipuláveis de um olho no fluxo pós-captura.
struct EyeMeasurementData: Codable, Equatable {
    var pupil: NormalizedPoint
    var nasalBarX: CGFloat
    var temporalBarX: CGFloat
    var inferiorBarY: CGFloat
    var superiorBarY: CGFloat

    /// Inicializa com valores padrão centralizados.
    init(pupil: NormalizedPoint = NormalizedPoint(),
         nasalBarX: CGFloat = 0.45,
         temporalBarX: CGFloat = 0.55,
         inferiorBarY: CGFloat = 0.6,
         superiorBarY: CGFloat = 0.4) {
        self.pupil = pupil
        self.nasalBarX = nasalBarX
        self.temporalBarX = temporalBarX
        self.inferiorBarY = inferiorBarY
        self.superiorBarY = superiorBarY
    }
}

extension EyeMeasurementData {
    /// Retorna uma versão espelhada usando o ponto central informado.
    /// - Parameter centerX: Coordenada X do ponto central.
    func mirrored(around centerX: CGFloat) -> EyeMeasurementData {
        let mirroredPupil = pupil.mirrored(around: centerX).clamped()
        let mirroredNasal = (2 * centerX) - nasalBarX
        let mirroredTemporal = (2 * centerX) - temporalBarX
        return EyeMeasurementData(
            pupil: mirroredPupil,
            nasalBarX: mirroredTemporal,
            temporalBarX: mirroredNasal,
            inferiorBarY: inferiorBarY,
            superiorBarY: superiorBarY
        )
    }

    /// Atualiza garantindo que as barras fiquem ordenadas e dentro do intervalo válido.
    func normalizedOrder() -> EyeMeasurementData {
        let nasal = min(max(nasalBarX, 0), 1)
        let temporal = min(max(temporalBarX, 0), 1)
        let inferior = min(max(inferiorBarY, 0), 1)
        let superior = min(max(superiorBarY, 0), 1)

        return EyeMeasurementData(
            pupil: pupil.clamped(),
            nasalBarX: min(nasal, temporal),
            temporalBarX: max(nasal, temporal),
            inferiorBarY: max(inferior, superior),
            superiorBarY: min(inferior, superior)
        )
    }
}

// MARK: - Configuração completa
/// Conjunto de dados pós-captura utilizados para reconstruir a edição.
struct PostCaptureConfiguration: Codable, Equatable {
    var centralPoint: NormalizedPoint
    var rightEye: EyeMeasurementData
    var leftEye: EyeMeasurementData

    /// Construtor padrão com olhos centralizados.
    init(centralPoint: NormalizedPoint = NormalizedPoint(),
         rightEye: EyeMeasurementData = EyeMeasurementData(),
         leftEye: EyeMeasurementData = EyeMeasurementData()) {
        self.centralPoint = centralPoint
        self.rightEye = rightEye
        self.leftEye = leftEye
    }
}

// MARK: - Métricas finais
/// Resultado consolidado com as medidas calculadas em milímetros.
struct EyeMeasurementSummary: Codable, Equatable {
    var horizontalMaior: Double
    var verticalMaior: Double
    var dnp: Double
    var alturaPupilar: Double
}

/// Informações finais derivadas do fluxo pós-captura.
struct PostCaptureMetrics: Codable, Equatable {
    var rightEye: EyeMeasurementSummary
    var leftEye: EyeMeasurementSummary
    var ponte: Double

    /// Retorna a distância pupilar total somando OD e OE.
    var distanciaPupilarTotal: Double {
        rightEye.dnp + leftEye.dnp
    }
}
