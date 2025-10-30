//
//  PostCaptureViewModel.swift
//  MedidorOticaApp
//
//  Controla o estado das etapas pós-captura permitindo edição e cálculo das medidas finais.
//

import Foundation
import SwiftUI

// MARK: - Enumerações de Etapas
enum PostCaptureEye: String {
    case right = "Direito"
    case left = "Esquerdo"
}

enum PostCaptureStage: Int, CaseIterable {
    case confirmation
    case pupil
    case horizontal
    case vertical
    case summary

    /// Retorna a descrição textual da etapa atual.
    var description: String {
        switch self {
        case .confirmation: return "Confirmar enquadramento"
        case .pupil: return "Localize a pupila"
        case .horizontal: return "Ajuste a largura da lente"
        case .vertical: return "Ajuste a altura da lente"
        case .summary: return "Resumo das medidas"
        }
    }
}

// MARK: - ViewModel
@MainActor
final class PostCaptureViewModel: ObservableObject {
    // MARK: - Propriedades Públicas
    @Published var configuration: PostCaptureConfiguration
    @Published var metrics: PostCaptureMetrics?
    @Published var currentEye: PostCaptureEye = .right
    @Published var currentStage: PostCaptureStage = .confirmation
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var facePreview: UIImage?
    /// Define o recorte original do rosto identificado na foto completa.
    @Published var faceBounds: NormalizedRect = NormalizedRect()
    /// Representa o recorte efetivamente exibido nas etapas interativas após aplicar margens extras.
    @Published var previewBounds: NormalizedRect = NormalizedRect()

    let capturedImage: UIImage
    private let baseMeasurement: Measurement?

    // MARK: - Estados Internos
    private var didMirrorLeftEye = false

    // MARK: - Inicialização
    init(image: UIImage, existingMeasurement: Measurement? = nil) {
        self.capturedImage = image
        self.baseMeasurement = existingMeasurement
        self.configuration = PostCaptureConfiguration()
        self.metrics = existingMeasurement?.postCaptureMetrics
        self.isProcessing = true

        Task { await runAnalysis() }
    }

    // MARK: - Acesso a Dados
    var currentEyeData: EyeMeasurementData {
        switch currentEye {
        case .right: return configuration.rightEye
        case .left: return configuration.leftEye
        }
    }

    /// Retorna os dados do olho atual convertidos para o espaço exibido.
    var currentDisplayEyeData: EyeMeasurementData {
        displayEyeData(for: currentEye)
    }

    /// Imagem exibida em todas as etapas, já considerando o recorte facial.
    var displayImage: UIImage {
        facePreview ?? capturedImage
    }

    /// Ponto central utilizado nas divisões, ajustado para o recorte exibido.
    var displayCentralPoint: NormalizedPoint {
        convertToDisplay(configuration.centralPoint)
    }

    var stageInstructions: String {
        switch currentStage {
        case .confirmation:
            return "🙂🆗 Garanta que o PC divida o rosto antes de iniciar."
        case .pupil:
            return "🙂🎯 Arraste o ponto azul para o centro da pupila."
        case .horizontal:
            return "🙂↔️ Posicione as barras verticais nos limites da lente."
        case .vertical:
            return "🙂↕️ Ajuste as barras horizontais na lente."
        case .summary:
            return "Revise os valores antes de salvar no histórico."
        }
    }

    var showEyeLabel: Bool {
        currentStage != .summary && currentStage != .confirmation
    }

    var canGoBack: Bool {
        switch currentStage {
        case .confirmation:
            return false
        case .pupil:
            return currentEye == .left
        case .horizontal, .vertical, .summary:
            return true
        }
    }

    var isOnSummary: Bool {
        currentStage == .summary
    }

    // MARK: - Processamento Inicial
    private func runAnalysis() async {
        do {
            let result = try await PostCaptureProcessor.shared.analyze(image: capturedImage)
            await MainActor.run {
                self.configuration = result.configuration
                self.faceBounds = result.configuration.faceBounds
                let preview = generateFacePreview(from: result.configuration.faceBounds)
                self.facePreview = preview.image
                self.previewBounds = preview.bounds
                self.isProcessing = false
            }
        } catch {
            await MainActor.run {
                self.isProcessing = false
                self.errorMessage = error.localizedDescription
                self.configuration = PostCaptureConfiguration()
                self.previewBounds = NormalizedRect()
            }
        }
    }

    // MARK: - Navegação
    func advanceStage() {
        guard !isProcessing else { return }

        switch currentStage {
        case .confirmation:
            currentStage = .pupil
            currentEye = .right
        case .pupil:
            currentStage = .horizontal
        case .horizontal:
            currentStage = .vertical
        case .vertical:
            if currentEye == .right {
                mirrorLeftEyeIfNeeded()
                currentEye = .left
                currentStage = .pupil
            } else {
                finalizeMetrics()
                currentStage = .summary
            }
        case .summary:
            break
        }
    }

    func goBack() {
        guard !isProcessing else { return }

        switch currentStage {
        case .confirmation:
            break
        case .pupil:
            if currentEye == .left {
                currentEye = .right
                currentStage = .vertical
            } else {
                currentStage = .confirmation
            }
        case .horizontal:
            currentStage = .pupil
        case .vertical:
            currentStage = .horizontal
        case .summary:
            currentStage = .vertical
            currentEye = .left
        }
    }

    private func mirrorLeftEyeIfNeeded() {
        guard !didMirrorLeftEye else { return }
        let mirrored = configuration.rightEye.mirrored(around: configuration.centralPoint.x)
        configuration.leftEye = mirrored.normalizedOrder()
        didMirrorLeftEye = true
    }

    /// Retorna o nível de progresso desbloqueado para o olho informado.
    func progressLevel(for eye: PostCaptureEye) -> Int {
        switch eye {
        case .right:
            switch currentStage {
            case .confirmation:
                return 0
            case .pupil:
                return currentEye == .right ? 1 : 3
            case .horizontal:
                return currentEye == .right ? 2 : 3
            case .vertical, .summary:
                return 3
            }
        case .left:
            switch currentStage {
            case .confirmation:
                return 0
            case .pupil:
                return currentEye == .left ? 1 : 0
            case .horizontal:
                return currentEye == .left ? 2 : 0
            case .vertical:
                return currentEye == .left ? 3 : 0
            case .summary:
                return 3
            }
        }
    }

    // MARK: - Atualizações de Pontos
    func updatePupil(to point: NormalizedPoint) {
        var updated = currentEyeData
        let globalPoint = convertFromDisplay(point)
        updated.pupil = globalPoint.clamped()
        apply(updatedEye: updated)
    }

    func updateVerticalBar(isNasal: Bool, value: CGFloat) {
        var updated = currentEyeData
        let globalValue = convertFromDisplayX(value)
        if isNasal {
            updated.nasalBarX = globalValue
        } else {
            updated.temporalBarX = globalValue
        }
        apply(updatedEye: updated)
    }

    func updateHorizontalBar(isInferior: Bool, value: CGFloat) {
        var updated = currentEyeData
        let globalValue = convertFromDisplayY(value)
        if isInferior {
            updated.inferiorBarY = globalValue
        } else {
            updated.superiorBarY = globalValue
        }
        apply(updatedEye: updated)
    }

    private func apply(updatedEye: EyeMeasurementData) {
        let normalized = updatedEye.normalizedOrder()
        switch currentEye {
        case .right:
            configuration = PostCaptureConfiguration(centralPoint: configuration.centralPoint,
                                                     rightEye: normalized,
                                                     leftEye: configuration.leftEye,
                                                     faceBounds: configuration.faceBounds)
        case .left:
            configuration = PostCaptureConfiguration(centralPoint: configuration.centralPoint,
                                                     rightEye: configuration.rightEye,
                                                     leftEye: normalized,
                                                     faceBounds: configuration.faceBounds)
            didMirrorLeftEye = true
        }
    }

    // MARK: - Cálculo de Métricas
    func finalizeMetrics() {
        let orderedRight = configuration.rightEye.normalizedOrder()
        let orderedLeft = configuration.leftEye.normalizedOrder()
        let center = configuration.centralPoint.clamped()

        let rightHorizontal = abs(orderedRight.temporalBarX - orderedRight.nasalBarX) * PostCaptureScale.horizontalReferenceMM
        let leftHorizontal = abs(orderedLeft.temporalBarX - orderedLeft.nasalBarX) * PostCaptureScale.horizontalReferenceMM

        let rightVertical = abs(orderedRight.inferiorBarY - orderedRight.superiorBarY) * PostCaptureScale.verticalReferenceMM
        let leftVertical = abs(orderedLeft.inferiorBarY - orderedLeft.superiorBarY) * PostCaptureScale.verticalReferenceMM

        let rightDNP = abs(orderedRight.pupil.x - center.x) * PostCaptureScale.horizontalReferenceMM
        let leftDNP = abs(orderedLeft.pupil.x - center.x) * PostCaptureScale.horizontalReferenceMM

        let rightAltura = abs(orderedRight.inferiorBarY - orderedRight.pupil.y) * PostCaptureScale.verticalReferenceMM
        let leftAltura = abs(orderedLeft.inferiorBarY - orderedLeft.pupil.y) * PostCaptureScale.verticalReferenceMM

        let ponte = abs(orderedLeft.nasalBarX - orderedRight.nasalBarX) * PostCaptureScale.horizontalReferenceMM

        let rightSummary = EyeMeasurementSummary(horizontalMaior: Double(rightHorizontal),
                                                 verticalMaior: Double(rightVertical),
                                                 dnp: Double(rightDNP),
                                                 alturaPupilar: Double(rightAltura))
        let leftSummary = EyeMeasurementSummary(horizontalMaior: Double(leftHorizontal),
                                                verticalMaior: Double(leftVertical),
                                                dnp: Double(leftDNP),
                                                alturaPupilar: Double(leftAltura))

        metrics = PostCaptureMetrics(rightEye: rightSummary,
                                     leftEye: leftSummary,
                                     ponte: Double(ponte))
    }

    // MARK: - Construção de Measurement
    func buildMeasurement(clientName: String) -> Measurement? {
        guard let metrics else { return nil }
        let trimmed = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let identifier = baseMeasurement?.id ?? UUID()
        let date = baseMeasurement?.date ?? Date()

        return Measurement(clientName: trimmed,
                           capturedImage: capturedImage,
                           postCaptureConfiguration: configuration,
                           postCaptureMetrics: metrics,
                           id: identifier,
                           date: date)
    }

    // MARK: - Pré-visualização
    private func generateFacePreview(from bounds: NormalizedRect) -> (image: UIImage?, bounds: NormalizedRect) {
        guard bounds.width > 0, bounds.height > 0 else {
            return (nil, bounds.clamped())
        }
        let oriented = capturedImage.normalizedOrientation()
        guard let cgImage = oriented.cgImage else {
            return (nil, bounds.clamped())
        }
        // Ajusta levemente o recorte para evitar cortes por arredondamento mantendo somente a cabeça no quadro.
        let verticalMargin = min(0.04, bounds.height * 0.12)
        let horizontalMargin = min(0.03, bounds.width * 0.1)
        let expandedBounds = bounds.insetBy(dx: -horizontalMargin, dy: -verticalMargin).clamped()
        let cropRect = expandedBounds.absolute(in: oriented.size)
        let scaled = CGRect(x: cropRect.origin.x * oriented.scale,
                            y: cropRect.origin.y * oriented.scale,
                            width: cropRect.size.width * oriented.scale,
                            height: cropRect.size.height * oriented.scale)
        guard let cropped = cgImage.cropping(to: scaled) else {
            return (nil, bounds.clamped())
        }
        let screenScale = max(UIScreen.main.scale, UIScreen.main.nativeScale)
        let outputScale = max(oriented.scale, screenScale)
        return (UIImage(cgImage: cropped, scale: outputScale, orientation: .up), expandedBounds.clamped())
    }

    /// Fornece os dados de um olho convertidos para o espaço de exibição.
    func displayEyeData(for eye: PostCaptureEye) -> EyeMeasurementData {
        var data = eye == .right ? configuration.rightEye : configuration.leftEye
        data.pupil = convertToDisplay(data.pupil)
        data.nasalBarX = convertToDisplayX(data.nasalBarX)
        data.temporalBarX = convertToDisplayX(data.temporalBarX)
        data.inferiorBarY = convertToDisplayY(data.inferiorBarY)
        data.superiorBarY = convertToDisplayY(data.superiorBarY)
        return data.normalizedOrder()
    }

    /// Converte um ponto para o espaço recortado mostrado na tela.
    private func convertToDisplay(_ point: NormalizedPoint) -> NormalizedPoint {
        let bounds = activeBounds()
        guard bounds.width > 0, bounds.height > 0 else { return point.clamped() }
        let convertedX = (point.x - bounds.x) / bounds.width
        let convertedY = (point.y - bounds.y) / bounds.height
        return NormalizedPoint(x: convertedX, y: convertedY).clamped()
    }

    /// Converte o eixo horizontal para o recorte exibido.
    private func convertToDisplayX(_ value: CGFloat) -> CGFloat {
        let bounds = activeBounds()
        guard bounds.width > 0 else { return value }
        return min(max((value - bounds.x) / bounds.width, 0), 1)
    }

    /// Converte o eixo vertical para o recorte exibido.
    private func convertToDisplayY(_ value: CGFloat) -> CGFloat {
        let bounds = activeBounds()
        guard bounds.height > 0 else { return value }
        return min(max((value - bounds.y) / bounds.height, 0), 1)
    }

    /// Converte um ponto do recorte exibido para o espaço original da foto.
    private func convertFromDisplay(_ point: NormalizedPoint) -> NormalizedPoint {
        let bounds = activeBounds()
        guard bounds.width > 0, bounds.height > 0 else { return point.clamped() }
        let convertedX = bounds.x + (point.x * bounds.width)
        let convertedY = bounds.y + (point.y * bounds.height)
        return NormalizedPoint(x: convertedX, y: convertedY).clamped()
    }

    /// Converte a coordenada horizontal do recorte exibido para o espaço original.
    private func convertFromDisplayX(_ value: CGFloat) -> CGFloat {
        let bounds = activeBounds()
        guard bounds.width > 0 else { return value }
        let converted = bounds.x + (value * bounds.width)
        return min(max(converted, 0), 1)
    }

    /// Converte a coordenada vertical do recorte exibido para o espaço original.
    private func convertFromDisplayY(_ value: CGFloat) -> CGFloat {
        let bounds = activeBounds()
        guard bounds.height > 0 else { return value }
        let converted = bounds.y + (value * bounds.height)
        return min(max(converted, 0), 1)
    }

    /// Resolve qual recorte deve ser usado nas conversões considerando a existência da pré-visualização expandida.
    private func activeBounds() -> NormalizedRect {
        let preview = previewBounds.clamped()
        if facePreview != nil, preview.width > 0, preview.height > 0 {
            return preview
        }
        return faceBounds.clamped()
    }
}
