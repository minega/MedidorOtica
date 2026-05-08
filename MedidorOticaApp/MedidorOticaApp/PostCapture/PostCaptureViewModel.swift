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
    @Published var dnpCandidates: [PostCaptureDNPCandidate] = []
    @Published var bridgeReferenceText = ""
    @Published var bridgeReferenceError: String?

    let capturedImage: UIImage
    private let baseMeasurement: Measurement?
    private let existingConfiguration: PostCaptureConfiguration?
    /// Calibração aplicada à imagem atual.
    let calibration: PostCaptureCalibration
    /// Mapa local da face usado para reduzir erro de perspectiva.
    let localCalibration: LocalFaceScaleCalibration
    /// Aviso opcional gerado no momento da captura para orientar a revisão manual.
    let captureWarning: String?
    let captureCentralPoint: NormalizedPoint?
    let eyeGeometrySnapshot: CaptureEyeGeometrySnapshot?
    /// Conversor de escalas utilizado em todos os cálculos normalizados.
    let scale: PostCaptureScale

    // MARK: - Estados Internos
    private var didMirrorLeftEye = false
    private var detectedPupils = PostCaptureAnalysisResult.DetectedPupils(right: false, left: false)
    private var centralCandidates: PostCaptureAnalysisResult.CentralPointCandidates?

    // MARK: - Inicialização
    init(photo: CapturedPhoto, existingMeasurement: Measurement? = nil) {
        self.capturedImage = photo.image
        self.baseMeasurement = existingMeasurement
        self.existingConfiguration = existingMeasurement?.postCaptureConfiguration
        self.calibration = existingMeasurement?.postCaptureCalibration ?? photo.calibration
        self.localCalibration = existingMeasurement?.postCaptureLocalCalibration ?? photo.localCalibration
        self.captureWarning = photo.captureWarning
        self.captureCentralPoint = existingMeasurement?.postCaptureCaptureCentralPoint ?? photo.captureCentralPoint
        self.eyeGeometrySnapshot = existingMeasurement?.postCaptureEyeGeometrySnapshot ?? photo.eyeGeometrySnapshot
        self.scale = PostCaptureScale(calibration: self.calibration,
                                      localCalibration: self.localCalibration)
        self.configuration = existingMeasurement?.postCaptureConfiguration ?? PostCaptureConfiguration()
        self.metrics = existingMeasurement?.postCaptureMetrics
        if let bridgeReference = existingMeasurement?.postCaptureMetrics?.bridgeReferenceComparison?.requestedBridgeMM {
            self.bridgeReferenceText = Self.formattedBridgeReference(bridgeReference)
        }
        self.isProcessing = true

        Task { await prepareInitialState() }
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
    private func prepareInitialState() async {
        if let existingConfiguration {
            await restoreExistingConfiguration(existingConfiguration)
            return
        }

        await runAnalysis()
    }

    private func runAnalysis() async {
        do {
            let result = try await PostCaptureProcessor.shared.analyze(image: capturedImage,
                                                                       scale: scale,
                                                                       preferredCentralPoint: captureCentralPoint,
                                                                       usesRearCameraDepthCapture: usesRearCameraDepthCapture)
            await MainActor.run {
                self.configuration = result.configuration
                self.detectedPupils = result.detectedPupils
                self.centralCandidates = result.centralCandidates
                self.normalizeEyeOrdering()
                self.faceBounds = result.configuration.faceBounds
                let preview = generateFacePreview(from: result.configuration.faceBounds)
                self.facePreview = preview.image
                self.previewBounds = preview.bounds
                self.dnpCandidates = self.makeDNPCandidates()
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

    private func restoreExistingConfiguration(_ storedConfiguration: PostCaptureConfiguration) async {
        let preview = generateFacePreview(from: storedConfiguration.faceBounds)
        await MainActor.run {
            self.configuration = storedConfiguration
            self.detectedPupils = PostCaptureAnalysisResult.DetectedPupils(right: true, left: true)
            self.centralCandidates = self.makeFallbackCentralCandidates(from: storedConfiguration)
            self.normalizeEyeOrdering()
            self.faceBounds = storedConfiguration.faceBounds
            self.facePreview = preview.image
            self.previewBounds = preview.bounds
            if let storedMetrics = self.baseMeasurement?.postCaptureMetrics {
                self.dnpCandidates = self.makeDNPCandidates(noseReference: storedMetrics.noseDNP,
                                                            bridgeReference: storedMetrics.bridgeDNP,
                                                            farConfidence: storedMetrics.farDNPConfidence,
                                                            farConfidenceReason: storedMetrics.farDNPConfidenceReason)
            } else {
                self.dnpCandidates = self.makeDNPCandidates()
            }
            self.isProcessing = false
            self.errorMessage = nil
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
                do {
                    try finalizeMetrics()
                    currentStage = .summary
                    errorMessage = nil
                } catch {
                    metrics = nil
                    errorMessage = error.localizedDescription
                }
            }
        case .summary:
            break
        }
    }

    /// Reinicia o fluxo pós-captura retornando para a etapa de confirmação.
    func restartFlowFromBeginning() {
        currentStage = .confirmation
        currentEye = .right
    }

    private func normalizeEyeOrdering() {
        let rightEye = configuration.rightEye
        let leftEye = configuration.leftEye
        let centralX = configuration.centralPoint.x

        let rightPupilX = rightEye.pupil.x
        let leftPupilX = leftEye.pupil.x

        let shouldSwap = rightPupilX > leftPupilX || (rightPupilX >= centralX && leftPupilX >= centralX)

        guard shouldSwap else { return }

        configuration = PostCaptureConfiguration(centralPoint: configuration.centralPoint,
                                                 rightEye: leftEye,
                                                 leftEye: rightEye,
                                                 faceBounds: configuration.faceBounds)

        detectedPupils = PostCaptureAnalysisResult.DetectedPupils(right: detectedPupils.left,
                                                                  left: detectedPupils.right)
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
        guard !detectedPupils.left else { return }
        let mirrored = configuration.rightEye.mirrored(around: configuration.centralPoint.x)
        configuration.leftEye = mirrored.normalized(centralX: configuration.centralPoint.x)
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
        let normalized = updatedEye.normalized(centralX: configuration.centralPoint.x)
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
    func finalizeMetrics() throws {
        if !scale.isReliable,
           let baseMeasurement,
           let baseMetrics = baseMeasurement.postCaptureMetrics,
            baseMeasurement.postCaptureConfiguration == configuration {
            metrics = try metricsApplyingBridgeReferenceIfNeeded(to: baseMetrics)
            dnpCandidates = makeDNPCandidates(noseReference: baseMetrics.noseDNP,
                                              bridgeReference: baseMetrics.bridgeDNP,
                                              farConfidence: baseMetrics.farDNPConfidence,
                                              farConfidenceReason: baseMetrics.farDNPConfidenceReason)
            return
        }

        let candidates = centralCandidates ?? makeFallbackCentralCandidates(from: configuration)
        let nosePoint = candidates.faceMidline.clamped()
        let bridgePoint = candidates.bridge.clamped()

        let noseMetrics = try makeMetrics(for: nosePoint)
        let bridgeMetrics = try makeMetrics(for: bridgePoint)
        let convergence = evaluateDNPConvergence(nose: noseMetrics.validatedDNP,
                                                 bridge: bridgeMetrics.validatedDNP)
        let validatedPoint = makeValidatedCentralPoint(nosePoint: nosePoint,
                                                       bridgePoint: bridgePoint,
                                                       converged: convergence.isConverged)
        let validatedMetrics = try makeMetrics(for: validatedPoint)
        let validatedReference = convergence.isConverged ?
            averagedReference(nose: noseMetrics.validatedDNP,
                              bridge: bridgeMetrics.validatedDNP) :
            noseMetrics.validatedDNP
        let validatedSummary = makeValidatedSummary(from: validatedMetrics,
                                                    validatedReference: validatedReference,
                                                    noseReference: noseMetrics.validatedDNP,
                                                    bridgeReference: bridgeMetrics.validatedDNP,
                                                    convergence: convergence)

        configuration = configurationForCentralPoint(validatedPoint)
        metrics = try metricsApplyingBridgeReferenceIfNeeded(to: validatedSummary)
        dnpCandidates = makeDNPCandidates(noseReference: noseMetrics.validatedDNP,
                                          bridgeReference: bridgeMetrics.validatedDNP,
                                          farConfidence: validatedSummary.farDNPConfidence,
                                          farConfidenceReason: validatedSummary.farDNPConfidenceReason)
    }

    // MARK: - Construção de Measurement
    /// Aplica a ponte real digitada e recalcula a comparacao proporcional.
    func applyBridgeReferenceFromInput() throws {
        if metrics == nil {
            try finalizeMetrics()
            return
        }

        guard let currentMetrics = metrics else { return }
        metrics = try metricsApplyingBridgeReferenceIfNeeded(to: currentMetrics.removingBridgeReferenceComparison())
    }

    /// Remove a comparacao por ponte real do resumo atual.
    func clearBridgeReferenceComparison() {
        bridgeReferenceText = ""
        bridgeReferenceError = nil
        metrics = metrics?.removingBridgeReferenceComparison()
    }

    func buildMeasurement(clientName: String, orderNumber: String) -> Measurement? {
        guard let metrics else { return nil }
        let trimmed = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrder = orderNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmedOrder.isEmpty else { return nil }

        let identifier = baseMeasurement?.id ?? UUID()
        let date = baseMeasurement?.date ?? Date()

        return Measurement(clientName: trimmed,
                           orderNumber: trimmedOrder,
                           capturedImage: capturedImage,
                           postCaptureConfiguration: configuration,
                           postCaptureMetrics: metrics,
                           postCaptureCalibration: calibration,
                           postCaptureLocalCalibration: localCalibration,
                           postCaptureCaptureCentralPoint: captureCentralPoint,
                           postCaptureEyeGeometrySnapshot: eyeGeometrySnapshot,
                           id: identifier,
                           date: date)
    }

    // MARK: - Pré-visualização
    /// Indica se a captura veio de um fluxo traseiro com escala de profundidade.
    private var usesRearCameraDepthCapture: Bool {
        if captureWarning?.localizedCaseInsensitiveContains("LiDAR traseiro") == true {
            return true
        }

        if captureWarning?.localizedCaseInsensitiveContains("Depth traseiro") == true {
            return true
        }

        if eyeGeometrySnapshot?.fixationConfidenceReason?
            .localizedCaseInsensitiveContains("Depth traseiro") == true {
            return true
        }

        return eyeGeometrySnapshot?.fixationConfidenceReason?
            .localizedCaseInsensitiveContains("LiDAR traseiro") == true
    }

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
        return data.normalized(centralX: displayCentralPoint.x)
    }

    /// Converte um ponto para o espaço recortado mostrado na tela.
    private func convertToDisplay(_ point: NormalizedPoint) -> NormalizedPoint {
        let bounds = activeBounds()
        guard bounds.width > 0, bounds.height > 0 else { return point.clamped() }
        let convertedX = convertToDisplayX(point.x)
        let convertedY = convertToDisplayY(point.y)
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

    private func makeFallbackCentralCandidates(from configuration: PostCaptureConfiguration) -> PostCaptureAnalysisResult.CentralPointCandidates {
        let pupilMidX = (configuration.rightEye.pupil.x + configuration.leftEye.pupil.x) / 2
        let faceMidX = configuration.faceBounds.x + (configuration.faceBounds.width / 2)
        let y = configuration.centralPoint.y

        return PostCaptureAnalysisResult.CentralPointCandidates(
            bridge: configuration.centralPoint,
            faceMidline: NormalizedPoint(x: faceMidX, y: y).clamped(),
            pupilMidline: NormalizedPoint(x: pupilMidX, y: y).clamped()
        )
    }

    private func makeDNPCandidates(noseReference: PostCaptureDNPReference? = nil,
                                   bridgeReference: PostCaptureDNPReference? = nil,
                                   farConfidence: Double? = nil,
                                   farConfidenceReason: String? = nil) -> [PostCaptureDNPCandidate] {
        let candidates = centralCandidates ?? makeFallbackCentralCandidates(from: configuration)
        return [
            makeDNPCandidate(id: "nose",
                             title: "DNP nariz",
                             point: candidates.faceMidline,
                             reference: noseReference,
                             farConfidence: farConfidence,
                             farConfidenceReason: farConfidenceReason),
            makeDNPCandidate(id: "bridge",
                             title: "DNP ponte",
                             point: candidates.bridge,
                             reference: bridgeReference,
                             farConfidence: farConfidence,
                             farConfidenceReason: farConfidenceReason)
        ]
    }

    private func makeDNPCandidate(id: String,
                                  title: String,
                                  point: NormalizedPoint,
                                  reference: PostCaptureDNPReference?,
                                  farConfidence: Double?,
                                  farConfidenceReason: String?) -> PostCaptureDNPCandidate {
        let resolvedFarDNP = PostCaptureFarDNPResolver.resolve(rightPupilNear: configuration.rightEye.pupil,
                                                               leftPupilNear: configuration.leftEye.pupil,
                                                               centralPoint: point,
                                                               scale: scale,
                                                               eyeGeometry: eyeGeometrySnapshot)
        let resolvedReference = reference ?? PostCaptureDNPReference(
            rightNear: sanitizedMillimeters(scale.horizontalMillimeters(between: configuration.rightEye.pupil.x,
                                                                        and: point.x,
                                                                        at: midpoint(configuration.rightEye.pupil.y, point.y))),
            leftNear: sanitizedMillimeters(scale.horizontalMillimeters(between: configuration.leftEye.pupil.x,
                                                                       and: point.x,
                                                                       at: midpoint(configuration.leftEye.pupil.y, point.y))),
            rightFar: resolvedFarDNP.rightDNPFar,
            leftFar: resolvedFarDNP.leftDNPFar
        )
        return PostCaptureDNPCandidate(id: id,
                                       title: title,
                                       point: point,
                                       rightDNPNear: resolvedReference.rightNear,
                                       leftDNPNear: resolvedReference.leftNear,
                                       rightDNPFar: resolvedReference.rightFar,
                                       leftDNPFar: resolvedReference.leftFar,
                                       farConfidence: farConfidence ?? resolvedFarDNP.confidence,
                                       farConfidenceReason: farConfidenceReason ?? resolvedFarDNP.confidenceReason)
    }

    private func sanitizedMillimeters(_ value: Double) -> Double {
        guard value.isFinite, value >= 0 else { return 0 }
        let precision = 0.01
        return (value / precision).rounded(.toNearestOrAwayFromZero) * precision
    }

    private func metricsApplyingBridgeReferenceIfNeeded(to summary: PostCaptureMetrics) throws -> PostCaptureMetrics {
        do {
            guard let bridgeReference = try parsedBridgeReferenceInput() else {
                bridgeReferenceError = nil
                return summary.removingBridgeReferenceComparison()
            }

            let adjusted = try summary.applyingBridgeReference(requestedBridgeMM: bridgeReference)
            bridgeReferenceError = nil
            return adjusted
        } catch {
            bridgeReferenceError = error.localizedDescription
            throw error
        }
    }

    private func parsedBridgeReferenceInput() throws -> Double? {
        let trimmed = bridgeReferenceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else {
            throw PostCaptureMeasurementError.implausibleMeasurement("Informe a ponte real em mm.")
        }

        guard PostCaptureBridgeReferenceLimits.plausibleBridgeMM.contains(value) else {
            throw PostCaptureMeasurementError.implausibleMeasurement("Informe uma ponte real entre 5 e 35 mm.")
        }

        return value
    }

    private static func formattedBridgeReference(_ value: Double) -> String {
        PostCaptureMetrics.summaryNumberFormatter.string(from: NSNumber(value: value))
        ?? String(format: "%.1f", value)
    }

    private func makeMetrics(for centralPoint: NormalizedPoint) throws -> PostCaptureMetrics {
        let resolvedConfiguration = configurationForCentralPoint(centralPoint)
        let calculator = PostCaptureMeasurementCalculator(configuration: resolvedConfiguration,
                                                         centralPoint: resolvedConfiguration.centralPoint,
                                                         scale: scale,
                                                         eyeGeometrySnapshot: eyeGeometrySnapshot)
        return try calculator.makeMetrics()
    }

    private func configurationForCentralPoint(_ centralPoint: NormalizedPoint) -> PostCaptureConfiguration {
        let clampedPoint = centralPoint.clamped()
        return PostCaptureConfiguration(centralPoint: clampedPoint,
                                        rightEye: configuration.rightEye.normalized(centralX: clampedPoint.x),
                                        leftEye: configuration.leftEye.normalized(centralX: clampedPoint.x),
                                        faceBounds: configuration.faceBounds)
    }

    private func makeValidatedCentralPoint(nosePoint: NormalizedPoint,
                                           bridgePoint: NormalizedPoint,
                                           converged: Bool) -> NormalizedPoint {
        guard converged else { return nosePoint.clamped() }
        return NormalizedPoint(x: midpoint(nosePoint.x, bridgePoint.x),
                               y: midpoint(nosePoint.y, bridgePoint.y)).clamped()
    }

    private func averagedReference(nose: PostCaptureDNPReference,
                                   bridge: PostCaptureDNPReference) -> PostCaptureDNPReference {
        PostCaptureDNPReference(rightNear: sanitizedMillimeters((nose.rightNear + bridge.rightNear) * 0.5),
                                leftNear: sanitizedMillimeters((nose.leftNear + bridge.leftNear) * 0.5),
                                rightFar: sanitizedMillimeters((nose.rightFar + bridge.rightFar) * 0.5),
                                leftFar: sanitizedMillimeters((nose.leftFar + bridge.leftFar) * 0.5))
    }

    private func makeValidatedSummary(from metrics: PostCaptureMetrics,
                                      validatedReference: PostCaptureDNPReference,
                                      noseReference: PostCaptureDNPReference,
                                      bridgeReference: PostCaptureDNPReference,
                                      convergence: (isConverged: Bool, tolerance: Double, reason: String?)) -> PostCaptureMetrics {
        let rightEye = EyeMeasurementSummary(horizontalMaior: metrics.rightEye.horizontalMaior,
                                             verticalMaior: metrics.rightEye.verticalMaior,
                                             dnp: validatedReference.rightNear,
                                             alturaPupilar: metrics.rightEye.alturaPupilar)
        let leftEye = EyeMeasurementSummary(horizontalMaior: metrics.leftEye.horizontalMaior,
                                            verticalMaior: metrics.leftEye.verticalMaior,
                                            dnp: validatedReference.leftNear,
                                            alturaPupilar: metrics.leftEye.alturaPupilar)

        return PostCaptureMetrics(rightEye: rightEye,
                                  leftEye: leftEye,
                                  ponte: metrics.ponte,
                                  validatedDNP: validatedReference,
                                  noseDNP: noseReference,
                                  bridgeDNP: bridgeReference,
                                  dnpConverged: convergence.isConverged,
                                  dnpConvergenceToleranceMM: convergence.tolerance,
                                  dnpConvergenceReason: convergence.reason,
                                  farDNPConfidence: metrics.farDNPConfidence,
                                  farDNPConfidenceReason: metrics.farDNPConfidenceReason)
    }

    private func evaluateDNPConvergence(nose: PostCaptureDNPReference,
                                        bridge: PostCaptureDNPReference) -> (isConverged: Bool, tolerance: Double, reason: String?) {
        let tolerance = 0.5
        let differences = [
            abs(nose.rightNear - bridge.rightNear),
            abs(nose.leftNear - bridge.leftNear),
            abs(nose.rightFar - bridge.rightFar),
            abs(nose.leftFar - bridge.leftFar)
        ]
        let maximumDifference = differences.max() ?? 0
        guard maximumDifference > tolerance else {
            return (true, tolerance, nil)
        }

        let formattedDifference = PostCaptureMetrics.summaryNumberFormatter
            .string(from: NSNumber(value: maximumDifference))
            ?? String(format: "%.1f", maximumDifference)
        return (false,
                tolerance,
                "Nariz e ponte divergiram \(formattedDifference) mm. Refaça a captura para validar a DNP.")
    }

    private func midpoint(_ first: CGFloat,
                          _ second: CGFloat) -> CGFloat {
        (first + second) * 0.5
    }
}
