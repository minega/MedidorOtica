//
//  PostCaptureOverlayView.swift
//  MedidorOticaApp
//
//  Exibe a imagem capturada com os elementos interativos de medição pós-captura.
//

import SwiftUI

// MARK: - Sobreposição Interativa
struct PostCaptureOverlayView: View {
    @ObservedObject var viewModel: PostCaptureViewModel
    @State private var displayZoom: CGFloat = 1.0
    /// Valor mínimo permitido de zoom para a etapa atual.
    @State private var stageMinZoom: CGFloat = 1.0
    @State private var lastMagnification: CGFloat = 1.0
    /// Ponto utilizado como âncora ao centralizar o olho ativo.
    @State private var anchorReference: NormalizedPoint = NormalizedPoint()
    /// Deslocamento calculado automaticamente para posicionar o olho ativo.
    @State private var autoOffset: CGSize = .zero
    /// Deslocamento adicional aplicado pelo usuário ao arrastar a foto.
    @State private var manualOffset: CGSize = .zero
    /// Valor inicial do deslocamento manual ao começar um arraste.
    @State private var panStartOffset: CGSize = .zero
    /// Define quando o deslocamento manual deve ser reiniciado ao trocar de etapa ou olho.
    @State private var shouldResetManualOffset = true
    /// Indica que precisamos aplicar uma nova âncora na próxima renderização.
    @State private var pendingAnchor: NormalizedPoint?
    /// Controle interno para saber se estamos arrastando a imagem.
    @State private var isPanningImage = false
    /// Guarda o ponto inicial do arraste da pupila para aplicar deslocamentos precisos.
    @State private var pupilDragStart: NormalizedPoint?

    private let maxZoom: CGFloat = 3.0

    var body: some View {
        GeometryReader { geometry in
            if viewModel.currentStage == .confirmation {
                confirmationView(in: geometry.size)
            } else {
                interactiveView(in: geometry)
                    .onAppear {
                        configureStage(for: viewModel.currentStage)
                        pendingAnchor = viewModel.displayEyeData(for: viewModel.currentEye).pupil
                    }
                    .onChange(of: viewModel.currentStage) { stage in
                        configureStage(for: stage)
                        pendingAnchor = viewModel.displayEyeData(for: viewModel.currentEye).pupil
                        pupilDragStart = nil
                    }
                    .onChange(of: viewModel.currentEye) { _ in
                        pendingAnchor = viewModel.displayEyeData(for: viewModel.currentEye).pupil
                        shouldResetManualOffset = true
                        pupilDragStart = nil
                    }
            }
        }
    }

    // MARK: - Etapa de Confirmação
    /// Seleciona o layout adequado para a etapa de confirmação, priorizando o recorte real quando disponível.
    @ViewBuilder
    private func confirmationView(in size: CGSize) -> some View {
        if viewModel.facePreview != nil {
            croppedConfirmationView(in: size)
        } else {
            legacyConfirmationView(in: size)
        }
    }

    /// Exibe a imagem já recortada destacando o alinhamento do ponto central.
    private func croppedConfirmationView(in size: CGSize) -> some View {
        let image = viewModel.displayImage
        let rect = aspectFitRect(imageSize: image.size,
                                  containerSize: size)
        let cornerRadius = min(rect.size.width, rect.size.height) * 0.12
        let centerX = viewModel.displayCentralPoint.x * rect.size.width

        return ZStack {
            Color.black

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: rect.size.width, height: rect.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    )

                Rectangle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 2, height: rect.size.height)
                    .position(x: centerX, y: rect.size.height / 2)
            }
            .frame(width: rect.size.width, height: rect.size.height)
            .shadow(color: Color.black.opacity(0.45), radius: 16, x: 0, y: 8)
        }
        .frame(width: size.width, height: size.height)
    }

    /// Fallback que mantém o comportamento anterior caso o recorte falhe.
    private func legacyConfirmationView(in size: CGSize) -> some View {
        let rect = aspectFitRect(imageSize: viewModel.capturedImage.size,
                                  containerSize: size)
        let faceRect = viewModel.faceBounds.clamped().absolute(in: rect.size)
        let cornerRadius = min(faceRect.width, faceRect.height) * 0.12
        let centerX = viewModel.configuration.centralPoint.x * rect.size.width
        let dividerHeight = max(faceRect.height * 1.1, rect.size.height * 0.65)

        return ZStack {
            Color.black

            ZStack(alignment: .topLeading) {
                Image(uiImage: viewModel.capturedImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: rect.size.width, height: rect.size.height)

                legacyConfirmationMask(faceRect: faceRect,
                                       canvasSize: rect.size,
                                       cornerRadius: cornerRadius)

                Rectangle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 2, height: dividerHeight)
                    .position(x: centerX, y: rect.size.height / 2)
            }
            .frame(width: rect.size.width, height: rect.size.height)
        }
        .frame(width: size.width, height: size.height)
    }

    /// Cria a máscara do modo legado destacando apenas a área estimada quando o recorte não está disponível.
    private func legacyConfirmationMask(faceRect: CGRect,
                                        canvasSize: CGSize,
                                        cornerRadius: CGFloat) -> some View {
        ZStack {
            Path { path in
                let fullRect = CGRect(origin: .zero, size: canvasSize)
                path.addRect(fullRect)
                path.addRoundedRect(in: faceRect,
                                     cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 2)
                .frame(width: faceRect.width, height: faceRect.height)
                .position(x: faceRect.midX, y: faceRect.midY)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.blue.opacity(0.35), lineWidth: 6)
                .frame(width: faceRect.width * 1.04, height: faceRect.height * 1.04)
                .position(x: faceRect.midX, y: faceRect.midY)
        }
    }

    // MARK: - Etapas Interativas
    private func interactiveView(in geometry: GeometryProxy) -> some View {
        let rect = aspectFitRect(imageSize: viewModel.displayImage.size,
                                  containerSize: geometry.size)
        let imageSize = viewModel.displayImage.size
        let aspectRatio = imageSize.height == 0 ? 1 : imageSize.width / imageSize.height
        let translation = totalTranslation()

        // Sobrepõe a foto recortada permitindo zoom e deslocamento controlados.
        return ZStack {
            Color.black.opacity(0.9)
            ZStack(alignment: .topLeading) {
                Image(uiImage: viewModel.displayImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(width: rect.size.width, height: rect.size.height)
                overlayContent(size: rect.size, zoom: displayZoom)
                    .frame(width: rect.size.width, height: rect.size.height)
            }
            .frame(width: rect.size.width, height: rect.size.height)
            .scaleEffect(displayZoom)
            .offset(translation)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(panGesture(for: rect.size))
        .simultaneousGesture(magnificationGesture(for: rect.size))
        .onAppear {
            if pendingAnchor == nil {
                pendingAnchor = viewModel.displayEyeData(for: viewModel.currentEye).pupil
            }
            applyPendingAnchorIfNeeded(size: rect.size)
        }
        .onChange(of: rect.size) { newSize in
            pendingAnchor = pendingAnchor ?? anchorReference
            applyPendingAnchorIfNeeded(size: newSize)
        }
        .onChange(of: pendingAnchor) { _ in
            applyPendingAnchorIfNeeded(size: rect.size)
        }
        .onChange(of: displayZoom) { _ in
            pendingAnchor = pendingAnchor ?? anchorReference
            applyPendingAnchorIfNeeded(size: rect.size)
        }
        .animation(.easeInOut(duration: 0.25), value: displayZoom)
    }

    // MARK: - Conteúdo da Sobreposição
    private func overlayContent(size: CGSize, zoom: CGFloat) -> some View {
        ZStack {
            centralDivider(size: size)
            eyeOverlay(for: .right, size: size, zoom: zoom)
            eyeOverlay(for: .left, size: size, zoom: zoom)
        }
    }

    private func centralDivider(size: CGSize) -> some View {
        let centerX = viewModel.displayCentralPoint.x * size.width
        return Rectangle()
            .fill(Color.white.opacity(0.4))
            .frame(width: 2)
            .position(x: centerX, y: size.height / 2)
    }

    private func eyeOverlay(for eye: PostCaptureEye, size: CGSize, zoom: CGFloat) -> some View {
        let data = viewModel.displayEyeData(for: eye)
        let isActiveEye = eye == viewModel.currentEye
        let progress = viewModel.progressLevel(for: eye)

        return ZStack {
            if progress >= 2 {
                verticalBars(for: eye, data: data, size: size, isActiveEye: isActiveEye)
            }
            if progress >= 3 {
                horizontalBars(for: eye, data: data, size: size, isActiveEye: isActiveEye)
            }
            if progress >= 1 {
                pupilMarker(for: eye,
                             data: data,
                             size: size,
                             zoom: zoom,
                             isActiveEye: isActiveEye)
            }
        }
        .opacity(progress == 0 ? 0 : (isActiveEye ? 1 : 0.45))
    }

    private func pupilMarker(for eye: PostCaptureEye,
                              data: EyeMeasurementData,
                              size: CGSize,
                              zoom: CGFloat,
                              isActiveEye: Bool) -> some View {
        let center = CGPoint(x: data.pupil.x * size.width,
                             y: data.pupil.y * size.height)
        let baseDiameter = PostCaptureScale.normalizedHorizontal(PostCaptureScale.pupilDiameterMM) * size.width
        let diameter = max(baseDiameter / 5, 8)
        let interactionSize = max(diameter * 3.1, 88)
        let crossLength = max(diameter * 1.6, 34)
        let crossWidth = max(diameter * 0.14, 2.4)
        let innerDot = max(diameter * 0.22, 4)
        let isActive = isActiveEye && viewModel.currentStage == .pupil
        let ringColor = isActive ? Color.blue : Color.white.opacity(0.85)
        let fillColor = isActive ? Color.blue.opacity(0.28) : Color.white.opacity(0.18)

        // Cria um marcador em formato de mira para deixar claro qual é o ponto correto.
        return ZStack {
            Circle()
                .strokeBorder(ringColor, lineWidth: max(2, diameter * 0.12))
                .background(Circle().fill(fillColor))
                .frame(width: diameter, height: diameter)

            Capsule(style: .circular)
                .fill(ringColor)
                .frame(width: crossLength, height: crossWidth)

            Capsule(style: .circular)
                .fill(ringColor)
                .frame(width: crossWidth, height: crossLength)

            Circle()
                .fill(Color.white)
                .frame(width: innerDot, height: innerDot)
        }
        .frame(width: interactionSize, height: interactionSize)
        .position(center)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { value in
                guard isActive, size.width > 0, size.height > 0 else { return }
                if pupilDragStart == nil {
                    pupilDragStart = data.pupil
                }
                let start = pupilDragStart ?? data.pupil
                let deltaX = (value.translation.width / max(zoom, 0.0001)) / size.width
                let deltaY = (value.translation.height / max(zoom, 0.0001)) / size.height
                let proposed = NormalizedPoint(x: start.x + deltaX,
                                               y: start.y + deltaY).clamped()
                viewModel.updatePupil(to: proposed)
            }
            .onEnded { _ in
                guard isActive else { return }
                pupilDragStart = nil
                pendingAnchor = pendingAnchor ?? anchorReference
            }
        )
        .allowsHitTesting(isActive)
        .animation(.easeInOut(duration: 0.2), value: viewModel.currentStage)
    }

    private func verticalBars(for eye: PostCaptureEye,
                               data: EyeMeasurementData,
                               size: CGSize,
                               isActiveEye: Bool) -> some View {
        let barHeight = min(PostCaptureScale.normalizedVertical(PostCaptureScale.verticalBarHeightMM) * size.height,
                            size.height)
        let centerY = data.pupil.y * size.height
        let isActive = isActiveEye && viewModel.currentStage == .horizontal
        let nasalX = data.nasalBarX * size.width
        let temporalX = data.temporalBarX * size.width

        return ZStack {
            draggableVerticalBar(positionX: nasalX,
                                  centerY: centerY,
                                  height: barHeight,
                                  color: .yellow,
                                  isActive: isActive,
                                  size: size,
                                  update: { value in
                                      viewModel.updateVerticalBar(isNasal: true, value: value / size.width)
                                  })
            draggableVerticalBar(positionX: temporalX,
                                  centerY: centerY,
                                  height: barHeight,
                                  color: .orange,
                                  isActive: isActive,
                                  size: size,
                                  update: { value in
                                      viewModel.updateVerticalBar(isNasal: false, value: value / size.width)
                                  })
        }
    }

    private func draggableVerticalBar(positionX: CGFloat,
                                       centerY: CGFloat,
                                       height: CGFloat,
                                       color: Color,
                                       isActive: Bool,
                                       size: CGSize,
                                       update: @escaping (CGFloat) -> Void) -> some View {
        let lineWidth: CGFloat = isActive ? 2.2 : 1.4
        let handleSize: CGFloat = isActive ? 14 : 10

        return Capsule()
            .fill(color.opacity(isActive ? 0.9 : 0.45))
            .frame(width: lineWidth, height: height)
            .position(x: positionX, y: centerY)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(isActive ? 0.85 : 0.55))
                    .frame(width: handleSize, height: handleSize)
                    .position(x: positionX, y: centerY)
            )
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard isActive else { return }
                let clampedX = min(max(value.location.x, 0), size.width)
                update(clampedX)
            })
            .allowsHitTesting(isActive)
    }

    private func horizontalBars(for eye: PostCaptureEye,
                                 data: EyeMeasurementData,
                                 size: CGSize,
                                 isActiveEye: Bool) -> some View {
        let barWidth = min(PostCaptureScale.normalizedHorizontal(PostCaptureScale.horizontalBarLengthMM) * size.width,
                           size.width)
        let centerX = data.pupil.x * size.width
        let inferiorY = data.inferiorBarY * size.height
        let superiorY = data.superiorBarY * size.height
        let isActive = isActiveEye && viewModel.currentStage == .vertical

        return ZStack {
            draggableHorizontalBar(positionY: inferiorY,
                                    centerX: centerX,
                                    width: barWidth,
                                    color: .green,
                                    isActive: isActive,
                                    size: size,
                                    update: { value in
                                        viewModel.updateHorizontalBar(isInferior: true, value: value / size.height)
                                    })
            draggableHorizontalBar(positionY: superiorY,
                                    centerX: centerX,
                                    width: barWidth,
                                    color: .mint,
                                    isActive: isActive,
                                    size: size,
                                    update: { value in
                                        viewModel.updateHorizontalBar(isInferior: false, value: value / size.height)
                                    })
        }
    }

    private func draggableHorizontalBar(positionY: CGFloat,
                                         centerX: CGFloat,
                                         width: CGFloat,
                                         color: Color,
                                         isActive: Bool,
                                         size: CGSize,
                                         update: @escaping (CGFloat) -> Void) -> some View {
        let lineHeight: CGFloat = isActive ? 2.2 : 1.4
        let handleSize: CGFloat = isActive ? 14 : 10

        return Capsule()
            .fill(color.opacity(isActive ? 0.9 : 0.45))
            .frame(width: width, height: lineHeight)
            .position(x: centerX, y: positionY)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(isActive ? 0.85 : 0.55))
                    .frame(width: handleSize, height: handleSize)
                    .position(x: centerX, y: positionY)
            )
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard isActive else { return }
                let clampedY = min(max(value.location.y, 0), size.height)
                update(clampedY)
            })
            .allowsHitTesting(isActive)
    }

    /// Permite arrastar a imagem mantendo o deslocamento dentro da área segura.
    private func panGesture(for size: CGSize) -> some Gesture {
        return DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard viewModel.currentStage != .summary else { return }
                if !isPanningImage {
                    panStartOffset = manualOffset
                    isPanningImage = true
                }
                let translation = value.translation
                let proposed = CGSize(width: panStartOffset.width + translation.width,
                                      height: panStartOffset.height + translation.height)
                manualOffset = clampManualOffset(proposed, size: size, auto: autoOffset)
            }
            .onEnded { _ in
                panStartOffset = manualOffset
                isPanningImage = false
            }
    }

    /// Controla o gesto de pinça atualizando o zoom e recalculando os limites.
    private func magnificationGesture(for size: CGSize) -> some Gesture {
        return MagnificationGesture()
            .onChanged { value in
                guard viewModel.currentStage != .summary else { return }
                let delta = value / lastMagnification
                let proposed = displayZoom * delta
                let clamped = min(max(proposed, stageMinZoom), maxZoom)
                displayZoom = clamped
                lastMagnification = value
                pendingAnchor = anchorReference
            }
            .onEnded { _ in
                lastMagnification = 1.0
                pendingAnchor = anchorReference
                manualOffset = clampManualOffset(manualOffset, size: size, auto: autoOffset)
                panStartOffset = manualOffset
            }
    }

    /// Calcula o deslocamento total aplicando a centralização automática e o ajuste manual.
    private func totalTranslation() -> CGSize {
        CGSize(width: autoOffset.width + manualOffset.width,
               height: autoOffset.height + manualOffset.height)
    }

    /// Ajusta zoom e âncoras ao entrar em uma nova etapa interativa.
    private func configureStage(for stage: PostCaptureStage) {
        let preferred: CGFloat
        let minZoom: CGFloat
        switch stage {
        case .pupil, .horizontal, .vertical:
            preferred = 2.6
            minZoom = 1.15
        case .summary, .confirmation:
            preferred = 1.0
            minZoom = 1.0
        }
        stageMinZoom = minZoom
        displayZoom = preferred
        lastMagnification = 1.0
        if stage == .pupil || stage == .horizontal || stage == .vertical {
            shouldResetManualOffset = true
            pendingAnchor = viewModel.displayEyeData(for: viewModel.currentEye).pupil
        } else {
            shouldResetManualOffset = true
            manualOffset = .zero
            autoOffset = .zero
            anchorReference = viewModel.displayEyeData(for: viewModel.currentEye).pupil
        }
    }

    /// Atualiza deslocamentos quando um novo âncora for definido ou o layout mudar.
    private func applyPendingAnchorIfNeeded(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        DispatchQueue.main.async {
            let anchor = pendingAnchor ?? anchorReference
            let centeredOffset = centeringOffset(for: anchor, size: size, zoom: displayZoom)
            autoOffset = centeredOffset
            anchorReference = anchor

            if shouldResetManualOffset {
                manualOffset = .zero
                panStartOffset = .zero
                shouldResetManualOffset = false
            } else {
                manualOffset = clampManualOffset(manualOffset, size: size, auto: centeredOffset)
                panStartOffset = manualOffset
            }

            pendingAnchor = nil
        }
    }

    /// Centraliza o olho ativo respeitando os limites visíveis após aplicar zoom.
    private func centeringOffset(for anchor: NormalizedPoint,
                                 size: CGSize,
                                 zoom: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let target = CGPoint(x: anchor.x * size.width, y: anchor.y * size.height)
        let desiredX = -(target.x - center.x) * zoom
        let desiredY = -(target.y - center.y) * zoom
        let limitX = (size.width * (zoom - 1)) / 2
        let limitY = (size.height * (zoom - 1)) / 2
        let clampedX = min(max(desiredX, -limitX), limitX)
        let clampedY = min(max(desiredY, -limitY), limitY)
        return CGSize(width: clampedX, height: clampedY)
    }

    /// Limita o deslocamento manual mantendo a imagem sempre cobrindo todo o quadro.
    private func clampManualOffset(_ offset: CGSize,
                                   size: CGSize,
                                   auto: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let limitX = (size.width * (displayZoom - 1)) / 2
        let limitY = (size.height * (displayZoom - 1)) / 2
        if limitX <= 0 && limitY <= 0 {
            return .zero
        }

        let minX = -limitX - auto.width
        let maxX = limitX - auto.width
        let minY = -limitY - auto.height
        let maxY = limitY - auto.height

        let clampedWidth = min(max(offset.width, minX), maxX)
        let clampedHeight = min(max(offset.height, minY), maxY)
        return CGSize(width: clampedWidth.isFinite ? clampedWidth : 0,
                      height: clampedHeight.isFinite ? clampedHeight : 0)
    }

    // MARK: - Helpers
    private func aspectFitRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let scale = min(containerSize.width / imageSize.width,
                        containerSize.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let originX = (containerSize.width - width) / 2
        let originY = (containerSize.height - height) / 2
        return CGRect(x: originX, y: originY, width: width, height: height)
    }
}
