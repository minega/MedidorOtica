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

/// Informações finais derivadas do fluxo pós-captura.
struct PostCaptureMetrics: Codable, Equatable {
    var rightEye: EyeMeasurementSummary
    var leftEye: EyeMeasurementSummary
    var ponte: Double
    var rightDNPFar: Double
    var leftDNPFar: Double
    var farDNPConfidence: Double
    var farDNPConfidenceReason: String?

    /// Inicializa o resumo final preservando compatibilidade com históricos antigos.
    init(rightEye: EyeMeasurementSummary,
         leftEye: EyeMeasurementSummary,
         ponte: Double,
         rightDNPFar: Double? = nil,
         leftDNPFar: Double? = nil,
         farDNPConfidence: Double = 0,
         farDNPConfidenceReason: String? = nil) {
        self.rightEye = rightEye
        self.leftEye = leftEye
        self.ponte = ponte
        self.rightDNPFar = rightDNPFar ?? rightEye.dnp
        self.leftDNPFar = leftDNPFar ?? leftEye.dnp
        self.farDNPConfidence = farDNPConfidence
        self.farDNPConfidenceReason = farDNPConfidenceReason
    }

    /// Retorna a DNP total de perto somando OD e OE.
    var distanciaPupilarTotal: Double {
        rightEye.dnp + leftEye.dnp
    }

    /// Retorna a DNP total equivalente para longe.
    var distanciaPupilarTotalFar: Double {
        rightDNPFar + leftDNPFar
    }

    private enum CodingKeys: String, CodingKey {
        case rightEye
        case leftEye
        case ponte
        case rightDNPFar
        case leftDNPFar
        case farDNPConfidence
        case farDNPConfidenceReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rightEye = try container.decode(EyeMeasurementSummary.self, forKey: .rightEye)
        let leftEye = try container.decode(EyeMeasurementSummary.self, forKey: .leftEye)
        let ponte = try container.decode(Double.self, forKey: .ponte)
        let rightDNPFar = try container.decodeIfPresent(Double.self, forKey: .rightDNPFar)
        let leftDNPFar = try container.decodeIfPresent(Double.self, forKey: .leftDNPFar)
        let farDNPConfidence = try container.decodeIfPresent(Double.self, forKey: .farDNPConfidence) ?? 0
        let farDNPConfidenceReason = try container.decodeIfPresent(String.self, forKey: .farDNPConfidenceReason)

        self.init(rightEye: rightEye,
                  leftEye: leftEye,
                  ponte: ponte,
                  rightDNPFar: rightDNPFar,
                  leftDNPFar: leftDNPFar,
                  farDNPConfidence: farDNPConfidence,
                  farDNPConfidenceReason: farDNPConfidenceReason)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rightEye, forKey: .rightEye)
        try container.encode(leftEye, forKey: .leftEye)
        try container.encode(ponte, forKey: .ponte)
        try container.encode(rightDNPFar, forKey: .rightDNPFar)
        try container.encode(leftDNPFar, forKey: .leftDNPFar)
        try container.encode(farDNPConfidence, forKey: .farDNPConfidence)
        try container.encodeIfPresent(farDNPConfidenceReason, forKey: .farDNPConfidenceReason)
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
                               title: "DNP perto",
                               rightValue: rightEye.dnp,
                               leftValue: leftEye.dnp,
                               singleValue: nil,
                               totalValue: distanciaPupilarTotal),
            SummaryMetricEntry(id: "dnpLonge",
                               title: farDNPConfidence < 0.65 ? "DNP longe (conf. baixa)" : "DNP longe",
                               rightValue: rightDNPFar,
                               leftValue: leftDNPFar,
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
        if let farDNPConfidenceReason, farDNPConfidence < 0.65 {
            lines.append("Obs.: \(farDNPConfidenceReason)")
        }

        return lines.joined(separator: "\n")
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
