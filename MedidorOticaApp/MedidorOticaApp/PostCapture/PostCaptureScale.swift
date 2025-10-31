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
        return !matchesDefault
    }
}

// MARK: - Conversões de Escala
/// Responsável por converter valores milimétricos para o espaço normalizado (0...1).
struct PostCaptureScale {
    /// Calibração de origem utilizada para garantir a conversão precisa.
    let calibration: PostCaptureCalibration
    /// Referência horizontal em milímetros para o intervalo normalizado completo.
    let horizontalReferenceMM: CGFloat
    /// Referência vertical em milímetros para o intervalo normalizado completo.
    let verticalReferenceMM: CGFloat

    /// Diâmetro padrão da pupila utilizado para desenhar o marcador.
    static let pupilDiameterMM: CGFloat = 2
    /// Altura padrão das barras horizontais exibidas durante o ajuste vertical.
    static let verticalBarHeightMM: CGFloat = 50
    /// Comprimento padrão das barras verticais exibidas durante o ajuste horizontal.
    static let horizontalBarLengthMM: CGFloat = 60
    /// Deslocamento nasal inicial solicitado pelo time de ótica.
    static let nasalOffsetMM: CGFloat = 9
    /// Deslocamento temporal inicial solicitado pelo time de ótica.
    static let temporalOffsetMM: CGFloat = 60
    /// Deslocamento inferior inicial para o ajuste das barras horizontais.
    static let inferiorOffsetMM: CGFloat = 25
    /// Deslocamento superior inicial para o ajuste das barras horizontais.
    static let superiorOffsetMM: CGFloat = 15

    /// Inicializa a escala garantindo que os valores sejam positivos.
    init(calibration: PostCaptureCalibration = .default) {
        self.calibration = calibration
        self.horizontalReferenceMM = max(CGFloat(calibration.horizontalReferenceMM), 1)
        self.verticalReferenceMM = max(CGFloat(calibration.verticalReferenceMM), 1)
    }

    /// Informa se a calibração associada atende aos critérios de confiabilidade.
    var isReliable: Bool { calibration.isReliable }

    /// Converte um valor em milímetros para escala horizontal normalizada (0...1).
    func normalizedHorizontal(_ millimeters: CGFloat) -> CGFloat {
        guard horizontalReferenceMM > 0 else { return 0 }
        return millimeters / horizontalReferenceMM
    }

    /// Converte um valor em milímetros para escala vertical normalizada (0...1).
    func normalizedVertical(_ millimeters: CGFloat) -> CGFloat {
        guard verticalReferenceMM > 0 else { return 0 }
        return millimeters / verticalReferenceMM
    }
}
