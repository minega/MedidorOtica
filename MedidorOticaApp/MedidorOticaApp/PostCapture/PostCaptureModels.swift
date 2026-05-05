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
struct NormalizedPoint: Codable, Equatable, Sendable {
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

    /// Normaliza os valores mantendo a barra nasal sempre próxima ao ponto central informado.
    /// - Parameter centralX: Coordenada X do ponto central utilizado como referência para o lado nasal.
    func normalized(centralX: CGFloat) -> EyeMeasurementData {
        let minimumHorizontalGap: CGFloat = 0.002
        let reference = min(max(centralX, 0), 1)
        let pupilValue = pupil.clamped()
        let nasalClamped = min(max(nasalBarX, 0), 1)
        let temporalClamped = min(max(temporalBarX, 0), 1)
        let inferiorClamped = min(max(inferiorBarY, 0), 1)
        let superiorClamped = min(max(superiorBarY, 0), 1)

        let sortedDistances = [abs(nasalClamped - reference), abs(temporalClamped - reference)].sorted()
        let nearestDistance = sortedDistances.first ?? 0
        let farthestDistance = max(sortedDistances.last ?? nearestDistance,
                                   nearestDistance + minimumHorizontalGap)
        let eyeOnRightSide = pupilValue.x >= reference
        let sideSign: CGFloat = eyeOnRightSide ? 1 : -1
        let nasalValue = min(max(reference + (nearestDistance * sideSign), 0), 1)
        let temporalValue = min(max(reference + (farthestDistance * sideSign), 0), 1)

        let inferiorValue = max(inferiorClamped, superiorClamped)
        let superiorValue = min(inferiorClamped, superiorClamped)

        return EyeMeasurementData(
            pupil: pupilValue,
            nasalBarX: nasalValue,
            temporalBarX: temporalValue,
            inferiorBarY: inferiorValue,
            superiorBarY: superiorValue
        )
    }
}

// MARK: - Configuração completa
/// Representa uma área normalizada dentro da imagem original.
struct NormalizedRect: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    /// Inicializa com valores padrão cobrindo a imagem inteira.
    init(x: CGFloat = 0,
         y: CGFloat = 0,
         width: CGFloat = 1,
         height: CGFloat = 1) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

extension NormalizedRect {
    /// Retorna uma versão limitada ao intervalo 0...1.
    func clamped() -> NormalizedRect {
        let clampedX = min(max(x, 0), 1)
        let clampedY = min(max(y, 0), 1)
        let maxWidth = 1 - clampedX
        let maxHeight = 1 - clampedY
        let clampedWidth = min(max(width, 0), maxWidth)
        let clampedHeight = min(max(height, 0), maxHeight)
        return NormalizedRect(x: clampedX,
                              y: clampedY,
                              width: clampedWidth,
                              height: clampedHeight)
    }

    /// Expande ou contrai as bordas respeitando os limites válidos.
    func insetBy(dx: CGFloat, dy: CGFloat) -> NormalizedRect {
        let newX = x + dx
        let newY = y + dy
        let newWidth = width - (2 * dx)
        let newHeight = height - (2 * dy)
        return NormalizedRect(x: newX,
                              y: newY,
                              width: newWidth,
                              height: newHeight).clamped()
    }

    /// Converte para coordenadas absolutas utilizando o tamanho informado.
    func absolute(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width,
               y: y * size.height,
               width: width * size.width,
               height: height * size.height)
    }
}

/// Conjunto de dados pós-captura utilizados para reconstruir a edição.
struct PostCaptureConfiguration: Codable, Equatable {
    var centralPoint: NormalizedPoint
    var rightEye: EyeMeasurementData
    var leftEye: EyeMeasurementData
    var faceBounds: NormalizedRect

    /// Construtor padrão com olhos centralizados.
    init(centralPoint: NormalizedPoint = NormalizedPoint(),
         rightEye: EyeMeasurementData = EyeMeasurementData(),
         leftEye: EyeMeasurementData = EyeMeasurementData(),
         faceBounds: NormalizedRect = NormalizedRect()) {
        self.centralPoint = centralPoint
        self.rightEye = rightEye
        self.leftEye = leftEye
        self.faceBounds = faceBounds
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

/// Referencia monocular completa de DNP perto/longe.
struct PostCaptureDNPReference: Codable, Equatable {
    var rightNear: Double
    var leftNear: Double
    var rightFar: Double
    var leftFar: Double

    var totalNear: Double {
        rightNear + leftNear
    }

    var totalFar: Double {
        rightFar + leftFar
    }
}

// MARK: - Comparacao por ponte real
/// Limites usados quando o usuario informa a ponte real da armacao no resumo.
struct PostCaptureBridgeReferenceLimits {
    static let plausibleBridgeMM: ClosedRange<Double> = 5...35
    static let maximumScaleRatio: ClosedRange<Double> = 0.45...2.25
}

/// Resultado recalculado quando a ponte real e usada como referencia proporcional.
struct PostCaptureBridgeReferenceComparison: Codable, Equatable {
    var measuredBridgeMM: Double
    var requestedBridgeMM: Double
    var scaleRatio: Double
    var adjustedRightEye: EyeMeasurementSummary
    var adjustedLeftEye: EyeMeasurementSummary
    var adjustedValidatedDNP: PostCaptureDNPReference
    var adjustedNoseDNP: PostCaptureDNPReference
    var adjustedBridgeDNP: PostCaptureDNPReference
    var farDNPConfidence: Double
    var farDNPConfidenceReason: String?

    /// Diferenca percentual entre a escala dos sensores e a escala derivada da ponte real.
    var scaleDeltaPercent: Double {
        (scaleRatio - 1) * 100
    }

    /// Ponte final forcada pela referencia real informada.
    var adjustedBridgeMM: Double {
        requestedBridgeMM
    }

    /// DNP total perto depois do ajuste proporcional.
    var adjustedNearTotal: Double {
        adjustedValidatedDNP.totalNear
    }

    /// DNP total longe depois do ajuste proporcional.
    var adjustedFarTotal: Double {
        adjustedValidatedDNP.totalFar
    }
}

/// Informacoes finais derivadas do fluxo pos-captura.
struct PostCaptureMetrics: Codable, Equatable {
    var rightEye: EyeMeasurementSummary
    var leftEye: EyeMeasurementSummary
    var ponte: Double
    var validatedDNP: PostCaptureDNPReference
    var noseDNP: PostCaptureDNPReference
    var bridgeDNP: PostCaptureDNPReference
    var dnpConverged: Bool
    var dnpConvergenceToleranceMM: Double
    var dnpConvergenceReason: String?
    var farDNPConfidence: Double
    var farDNPConfidenceReason: String?
    var bridgeReferenceComparison: PostCaptureBridgeReferenceComparison?

    /// Mantem compatibilidade com a UI que ainda le a DNP longe principal por olho.
    var rightDNPFar: Double { validatedDNP.rightFar }
    /// Mantem compatibilidade com a UI que ainda le a DNP longe principal por olho.
    var leftDNPFar: Double { validatedDNP.leftFar }

    /// Inicializa o resumo final preservando compatibilidade com históricos antigos.
    init(rightEye: EyeMeasurementSummary,
         leftEye: EyeMeasurementSummary,
         ponte: Double,
         validatedDNP: PostCaptureDNPReference? = nil,
         noseDNP: PostCaptureDNPReference? = nil,
         bridgeDNP: PostCaptureDNPReference? = nil,
         dnpConverged: Bool = true,
         dnpConvergenceToleranceMM: Double = 0.5,
         dnpConvergenceReason: String? = nil,
         farDNPConfidence: Double = 0,
         farDNPConfidenceReason: String? = nil,
         bridgeReferenceComparison: PostCaptureBridgeReferenceComparison? = nil) {
        self.rightEye = rightEye
        self.leftEye = leftEye
        self.ponte = ponte
        let defaultReference = PostCaptureDNPReference(rightNear: rightEye.dnp,
                                                       leftNear: leftEye.dnp,
                                                       rightFar: rightEye.dnp,
                                                       leftFar: leftEye.dnp)
        self.validatedDNP = validatedDNP ?? defaultReference
        self.noseDNP = noseDNP ?? self.validatedDNP
        self.bridgeDNP = bridgeDNP ?? self.validatedDNP
        self.dnpConverged = dnpConverged
        self.dnpConvergenceToleranceMM = dnpConvergenceToleranceMM
        self.dnpConvergenceReason = dnpConvergenceReason
        self.farDNPConfidence = farDNPConfidence
        self.farDNPConfidenceReason = farDNPConfidenceReason
        self.bridgeReferenceComparison = bridgeReferenceComparison
    }

    /// Retorna a DNP total de perto somando OD e OE.
    var distanciaPupilarTotal: Double {
        validatedDNP.totalNear
    }

    /// Retorna a DNP total equivalente para longe.
    var distanciaPupilarTotalFar: Double {
        validatedDNP.totalFar
    }

    private enum CodingKeys: String, CodingKey {
        case rightEye
        case leftEye
        case ponte
        case validatedDNP
        case noseDNP
        case bridgeDNP
        case dnpConverged
        case dnpConvergenceToleranceMM
        case dnpConvergenceReason
        case rightDNPFar
        case leftDNPFar
        case farDNPConfidence
        case farDNPConfidenceReason
        case bridgeReferenceComparison
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rightEye = try container.decode(EyeMeasurementSummary.self, forKey: .rightEye)
        let leftEye = try container.decode(EyeMeasurementSummary.self, forKey: .leftEye)
        let ponte = try container.decode(Double.self, forKey: .ponte)
        let validatedDNP = try container.decodeIfPresent(PostCaptureDNPReference.self, forKey: .validatedDNP)
        let noseDNP = try container.decodeIfPresent(PostCaptureDNPReference.self, forKey: .noseDNP)
        let bridgeDNP = try container.decodeIfPresent(PostCaptureDNPReference.self, forKey: .bridgeDNP)
        let dnpConverged = try container.decodeIfPresent(Bool.self, forKey: .dnpConverged) ?? true
        let dnpConvergenceToleranceMM = try container.decodeIfPresent(Double.self, forKey: .dnpConvergenceToleranceMM) ?? 0.5
        let dnpConvergenceReason = try container.decodeIfPresent(String.self, forKey: .dnpConvergenceReason)
        let rightDNPFar = try container.decodeIfPresent(Double.self, forKey: .rightDNPFar)
        let leftDNPFar = try container.decodeIfPresent(Double.self, forKey: .leftDNPFar)
        let farDNPConfidence = try container.decodeIfPresent(Double.self, forKey: .farDNPConfidence) ?? 0
        let farDNPConfidenceReason = try container.decodeIfPresent(String.self, forKey: .farDNPConfidenceReason)
        let bridgeReferenceComparison = try container.decodeIfPresent(PostCaptureBridgeReferenceComparison.self,
                                                                      forKey: .bridgeReferenceComparison)

        let fallbackReference = PostCaptureDNPReference(rightNear: rightEye.dnp,
                                                        leftNear: leftEye.dnp,
                                                        rightFar: rightDNPFar ?? rightEye.dnp,
                                                        leftFar: leftDNPFar ?? leftEye.dnp)

        self.init(rightEye: rightEye,
                  leftEye: leftEye,
                  ponte: ponte,
                  validatedDNP: validatedDNP ?? fallbackReference,
                  noseDNP: noseDNP,
                  bridgeDNP: bridgeDNP,
                  dnpConverged: dnpConverged,
                  dnpConvergenceToleranceMM: dnpConvergenceToleranceMM,
                  dnpConvergenceReason: dnpConvergenceReason,
                  farDNPConfidence: farDNPConfidence,
                  farDNPConfidenceReason: farDNPConfidenceReason,
                  bridgeReferenceComparison: bridgeReferenceComparison)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rightEye, forKey: .rightEye)
        try container.encode(leftEye, forKey: .leftEye)
        try container.encode(ponte, forKey: .ponte)
        try container.encode(validatedDNP, forKey: .validatedDNP)
        try container.encode(noseDNP, forKey: .noseDNP)
        try container.encode(bridgeDNP, forKey: .bridgeDNP)
        try container.encode(dnpConverged, forKey: .dnpConverged)
        try container.encode(dnpConvergenceToleranceMM, forKey: .dnpConvergenceToleranceMM)
        try container.encodeIfPresent(dnpConvergenceReason, forKey: .dnpConvergenceReason)
        try container.encode(validatedDNP.rightFar, forKey: .rightDNPFar)
        try container.encode(validatedDNP.leftFar, forKey: .leftDNPFar)
        try container.encode(farDNPConfidence, forKey: .farDNPConfidence)
        try container.encodeIfPresent(farDNPConfidenceReason, forKey: .farDNPConfidenceReason)
        try container.encodeIfPresent(bridgeReferenceComparison, forKey: .bridgeReferenceComparison)
    }
}

/// Compara variantes do eixo X do PC apenas para a DNP final.
struct PostCaptureDNPCandidate: Equatable, Identifiable {
    let id: String
    let title: String
    let point: NormalizedPoint
    let rightDNPNear: Double
    let leftDNPNear: Double
    let rightDNPFar: Double
    let leftDNPFar: Double
    let farConfidence: Double
    let farConfidenceReason: String?

    var totalDNPNear: Double {
        rightDNPNear + leftDNPNear
    }

    var totalDNPFar: Double {
        rightDNPFar + leftDNPFar
    }
}

// MARK: - Resumo formatado das métricas
extension PostCaptureMetrics {
    /// Entrada utilizada para exibir ou compartilhar uma linha do resumo final.
    struct SummaryMetricEntry: Identifiable, Hashable {
        let id: String
        let title: String
        let rightValue: Double?
        let leftValue: Double?
        let singleValue: Double?
        let totalValue: Double?

        /// Indica quando o item possui valores para ambos os olhos.
        var hasPair: Bool {
            rightValue != nil && leftValue != nil
        }
    }

    /// Formata um valor numérico com uma casa decimal respeitando a localidade brasileira.
    /// Usado para manter o padrão em todo o fluxo pós-captura.
    static let summaryNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    /// Retorna os itens padronizados que compõem o resumo visual e textual.
    func summaryEntries() -> [SummaryMetricEntry] {
        [
            SummaryMetricEntry(id: "horizontalMaior",
                               title: "Horizontal maior",
                               rightValue: rightEye.horizontalMaior,
                               leftValue: leftEye.horizontalMaior,
                               singleValue: nil,
                               totalValue: nil),
            SummaryMetricEntry(id: "verticalMaior",
                               title: "Vertical maior",
                               rightValue: rightEye.verticalMaior,
                               leftValue: leftEye.verticalMaior,
                               singleValue: nil,
                               totalValue: nil),
            SummaryMetricEntry(id: "dnpPerto",
                               title: dnpConverged ? "DNP validada perto" : "DNP validada perto (revise)",
                               rightValue: validatedDNP.rightNear,
                               leftValue: validatedDNP.leftNear,
                               singleValue: nil,
                               totalValue: distanciaPupilarTotal),
            SummaryMetricEntry(id: "dnpLonge",
                               title: farDNPConfidence < 0.65 ? "DNP validada longe (conf. baixa)" : "DNP validada longe",
                               rightValue: validatedDNP.rightFar,
                               leftValue: validatedDNP.leftFar,
                               singleValue: nil,
                               totalValue: distanciaPupilarTotalFar),
            SummaryMetricEntry(id: "alturaPupilar",
                               title: "Altura pupilar",
                               rightValue: rightEye.alturaPupilar,
                               leftValue: leftEye.alturaPupilar,
                               singleValue: nil,
                               totalValue: nil),
            SummaryMetricEntry(id: "ponte",
                               title: "Ponte",
                               rightValue: nil,
                               leftValue: nil,
                               singleValue: ponte,
                               totalValue: nil)
        ]
    }

    /// Gera uma string compacta no padrão "Nome - valor OD/valor OE" sem repetir unidades.
    /// - Parameter item: Item do resumo que terá os valores convertidos para texto.
    /// - Returns: Linha formatada pronta para compartilhar ou exibir.
    func compactLine(for item: SummaryMetricEntry) -> String {
        "\(item.title) - \(item.compactDisplay(using: Self.summaryNumberFormatter))"
    }

    /// Lista todas as linhas compactas respeitando o padrão definido.
    func compactSummaryLines() -> [String] {
        summaryEntries().map { compactLine(for: $0) }
    }

    /// Monta o texto utilizado ao compartilhar o resumo das medidas.
    /// - Parameters:
    ///   - clientName: Nome bruto informado pelo usuário.
    ///   - orderNumber: Número da OS informado no formulário.
    /// - Returns: Texto formatado com identificação e métricas compactas.
    func shareDescription(clientName: String, orderNumber: String) -> String {
        var lines: [String] = []

        let trimmedName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrder = orderNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedName.isEmpty {
            lines.append("Cliente: \(trimmedName)")
        }

        if !trimmedOrder.isEmpty {
            lines.append("OS: \(trimmedOrder)")
        }

        lines.append("Valores em mm — OD / OE / total")
        lines.append(contentsOf: compactSummaryLines())
        if let dnpConvergenceReason, !dnpConverged {
            lines.append("Obs. PC: \(dnpConvergenceReason)")
        }
        if let farDNPConfidenceReason, farDNPConfidence < 0.65 {
            lines.append("Obs.: \(farDNPConfidenceReason)")
        }
        if let bridgeReferenceComparison {
            lines.append("")
            lines.append(contentsOf: bridgeReferenceComparison.compactSummaryLines(baseMetrics: self))
        }

        return lines.joined(separator: "\n")
    }
}

extension PostCaptureMetrics {
    /// Recalcula todas as medidas por proporcao quando a ponte real da armacao e informada.
    func applyingBridgeReference(requestedBridgeMM: Double) throws -> PostCaptureMetrics {
        guard requestedBridgeMM.isFinite,
              PostCaptureBridgeReferenceLimits.plausibleBridgeMM.contains(requestedBridgeMM) else {
            throw PostCaptureMeasurementError.implausibleMeasurement("Informe uma ponte real entre 5 e 35 mm.")
        }

        guard ponte.isFinite, ponte > 0 else {
            throw PostCaptureMeasurementError.implausibleMeasurement("A ponte medida nao permite recalculo proporcional.")
        }

        let scaleRatio = requestedBridgeMM / ponte
        guard scaleRatio.isFinite,
              PostCaptureBridgeReferenceLimits.maximumScaleRatio.contains(scaleRatio) else {
            throw PostCaptureMeasurementError.implausibleMeasurement("A ponte real diverge demais da captura. Revise as barras.")
        }

        var adjusted = self
        adjusted.bridgeReferenceComparison = PostCaptureBridgeReferenceComparison(
            measuredBridgeMM: roundedMillimeters(ponte),
            requestedBridgeMM: roundedMillimeters(requestedBridgeMM),
            scaleRatio: scaleRatio,
            adjustedRightEye: scaled(rightEye, by: scaleRatio),
            adjustedLeftEye: scaled(leftEye, by: scaleRatio),
            adjustedValidatedDNP: scaled(validatedDNP, by: scaleRatio),
            adjustedNoseDNP: scaled(noseDNP, by: scaleRatio),
            adjustedBridgeDNP: scaled(bridgeDNP, by: scaleRatio),
            farDNPConfidence: farDNPConfidence,
            farDNPConfidenceReason: farDNPConfidenceReason
        )
        return adjusted
    }

    /// Remove a comparacao por ponte sem alterar as medidas originais dos sensores.
    func removingBridgeReferenceComparison() -> PostCaptureMetrics {
        var updated = self
        updated.bridgeReferenceComparison = nil
        return updated
    }

    private func scaled(_ summary: EyeMeasurementSummary,
                        by ratio: Double) -> EyeMeasurementSummary {
        EyeMeasurementSummary(horizontalMaior: roundedMillimeters(summary.horizontalMaior * ratio),
                              verticalMaior: roundedMillimeters(summary.verticalMaior * ratio),
                              dnp: roundedMillimeters(summary.dnp * ratio),
                              alturaPupilar: roundedMillimeters(summary.alturaPupilar * ratio))
    }

    private func scaled(_ reference: PostCaptureDNPReference,
                        by ratio: Double) -> PostCaptureDNPReference {
        PostCaptureDNPReference(rightNear: roundedMillimeters(reference.rightNear * ratio),
                                leftNear: roundedMillimeters(reference.leftNear * ratio),
                                rightFar: roundedMillimeters(reference.rightFar * ratio),
                                leftFar: roundedMillimeters(reference.leftFar * ratio))
    }

    private func roundedMillimeters(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let precision = 0.01
        return (value / precision).rounded(.toNearestOrAwayFromZero) * precision
    }
}

extension PostCaptureBridgeReferenceComparison {
    /// Retorna os itens ajustados pela ponte real no mesmo formato do resumo principal.
    func summaryEntries(baseMetrics: PostCaptureMetrics) -> [PostCaptureMetrics.SummaryMetricEntry] {
        [
            PostCaptureMetrics.SummaryMetricEntry(id: "horizontalMaior",
                                                  title: "Horizontal maior",
                                                  rightValue: adjustedRightEye.horizontalMaior,
                                                  leftValue: adjustedLeftEye.horizontalMaior,
                                                  singleValue: nil,
                                                  totalValue: nil),
            PostCaptureMetrics.SummaryMetricEntry(id: "verticalMaior",
                                                  title: "Vertical maior",
                                                  rightValue: adjustedRightEye.verticalMaior,
                                                  leftValue: adjustedLeftEye.verticalMaior,
                                                  singleValue: nil,
                                                  totalValue: nil),
            PostCaptureMetrics.SummaryMetricEntry(id: "dnpPerto",
                                                  title: baseMetrics.dnpConverged ? "DNP validada perto" : "DNP validada perto (revise)",
                                                  rightValue: adjustedValidatedDNP.rightNear,
                                                  leftValue: adjustedValidatedDNP.leftNear,
                                                  singleValue: nil,
                                                  totalValue: adjustedNearTotal),
            PostCaptureMetrics.SummaryMetricEntry(id: "dnpLonge",
                                                  title: farDNPConfidence < 0.65 ? "DNP validada longe (conf. baixa)" : "DNP validada longe",
                                                  rightValue: adjustedValidatedDNP.rightFar,
                                                  leftValue: adjustedValidatedDNP.leftFar,
                                                  singleValue: nil,
                                                  totalValue: adjustedFarTotal),
            PostCaptureMetrics.SummaryMetricEntry(id: "alturaPupilar",
                                                  title: "Altura pupilar",
                                                  rightValue: adjustedRightEye.alturaPupilar,
                                                  leftValue: adjustedLeftEye.alturaPupilar,
                                                  singleValue: nil,
                                                  totalValue: nil),
            PostCaptureMetrics.SummaryMetricEntry(id: "ponte",
                                                  title: "Ponte",
                                                  rightValue: nil,
                                                  leftValue: nil,
                                                  singleValue: adjustedBridgeMM,
                                                  totalValue: nil)
        ]
    }

    /// Monta linhas compactas para compartilhar a comparacao entre sensor e ponte real.
    func compactSummaryLines(baseMetrics: PostCaptureMetrics) -> [String] {
        let formatter = PostCaptureMetrics.summaryNumberFormatter
        let deltaText = formatter.string(from: NSNumber(value: scaleDeltaPercent)) ?? String(format: "%.1f", scaleDeltaPercent)
        let bridgeText = formatter.string(from: NSNumber(value: requestedBridgeMM)) ?? String(format: "%.1f", requestedBridgeMM)
        let baseEntries = baseMetrics.summaryEntries()
        let adjustedEntries = summaryEntries(baseMetrics: baseMetrics)
        var lines = ["Comparacao ponte real \(bridgeText) mm (\(deltaText)%):"]

        for index in baseEntries.indices where adjustedEntries.indices.contains(index) {
            let baseValue = baseEntries[index].compactDisplay(using: formatter)
            let adjustedValue = adjustedEntries[index].compactDisplay(using: formatter)
            lines.append("\(baseEntries[index].title): sensor \(baseValue) / ponte \(adjustedValue)")
        }

        return lines
    }
}

extension PostCaptureMetrics.SummaryMetricEntry {
    /// Converte os valores numéricos para texto usando o formatador fornecido.
    /// - Parameter formatter: `NumberFormatter` configurado com uma casa decimal.
    /// - Returns: Texto já no padrão "valor OD/valor OE" ou apenas um valor.
    func compactDisplay(using formatter: NumberFormatter) -> String {
        let format: (Double) -> String = { value in
            formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
        }

        if let singleValue {
            return format(singleValue)
        }

        let rightText = rightValue.map(format)
        let leftText = leftValue.map(format)
        let totalText = totalValue.map(format)

        switch (rightText, leftText, totalText) {
        case let (right?, left?, total?):
            return "\(right) / \(left) / \(total)"
        case let (right?, left?, nil):
            return "\(right) / \(left)"
        case let (right?, nil, nil):
            return right
        case let (nil, left?, nil):
            return left
        default:
            return "-"
        }
    }
}
