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

    var body: some View {
        GeometryReader { geometry in
            let rect = aspectFitRect(imageSize: viewModel.capturedImage.size,
                                      containerSize: geometry.size)

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.85)

                Image(uiImage: viewModel.capturedImage)
                    .resizable()
                    .aspectRatio(viewModel.capturedImage.size, contentMode: .fit)
                    .frame(width: rect.size.width, height: rect.size.height)
                    .position(x: rect.midX, y: rect.midY)

                overlayContent(size: rect.size)
                    .frame(width: rect.size.width, height: rect.size.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    // MARK: - Conteúdo da Sobreposição
    private func overlayContent(size: CGSize) -> some View {
        ZStack {
            centralDivider(size: size)
            eyeOverlay(for: .right, size: size)
            eyeOverlay(for: .left, size: size)
        }
    }

    private func centralDivider(size: CGSize) -> some View {
        let centerX = viewModel.configuration.centralPoint.x * size.width
        return Rectangle()
            .fill(Color.white.opacity(0.4))
            .frame(width: 2)
            .position(x: centerX, y: size.height / 2)
    }

    private func eyeOverlay(for eye: PostCaptureEye, size: CGSize) -> some View {
        let data = eye == .right ? viewModel.configuration.rightEye : viewModel.configuration.leftEye
        let isActiveEye = eye == viewModel.currentEye

        return ZStack {
            verticalBars(for: eye, data: data, size: size, isActiveEye: isActiveEye)
            horizontalBars(for: eye, data: data, size: size, isActiveEye: isActiveEye)
            pupilMarker(for: eye, data: data, size: size, isActiveEye: isActiveEye)
        }
    }

    private func pupilMarker(for eye: PostCaptureEye,
                              data: EyeMeasurementData,
                              size: CGSize,
                              isActiveEye: Bool) -> some View {
        let center = CGPoint(x: data.pupil.x * size.width,
                             y: data.pupil.y * size.height)
        let diameter = max(PostCaptureScale.normalizedHorizontal(PostCaptureScale.pupilDiameterMM) * size.width, 12)
        let isActive = isActiveEye && viewModel.currentStage == .pupil

        return Circle()
            .fill(isActive ? Color.blue : Color.gray.opacity(0.6))
            .frame(width: diameter, height: diameter)
            .position(center)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isActive ? 0.9 : 0.5), lineWidth: 1)
            )
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard isActive else { return }
                let normalized = NormalizedPoint.fromAbsolute(value.location, size: size)
                viewModel.updatePupil(to: normalized)
            })
            .allowsHitTesting(isActive)
            .opacity(isActiveEye ? 1 : 0.4)
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
        .opacity(isActiveEye ? 1 : 0.4)
    }

    private func draggableVerticalBar(positionX: CGFloat,
                                       centerY: CGFloat,
                                       height: CGFloat,
                                       color: Color,
                                       isActive: Bool,
                                       size: CGSize,
                                       update: @escaping (CGFloat) -> Void) -> some View {
        Capsule()
            .fill(color.opacity(isActive ? 0.9 : 0.4))
            .frame(width: isActive ? 6 : 4, height: height)
            .position(x: positionX, y: centerY)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(isActive ? 0.9 : 0.5))
                    .frame(width: 20, height: 20)
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
        .opacity(isActiveEye ? 1 : 0.4)
    }

    private func draggableHorizontalBar(positionY: CGFloat,
                                         centerX: CGFloat,
                                         width: CGFloat,
                                         color: Color,
                                         isActive: Bool,
                                         size: CGSize,
                                         update: @escaping (CGFloat) -> Void) -> some View {
        Capsule()
            .fill(color.opacity(isActive ? 0.9 : 0.4))
            .frame(width: width, height: isActive ? 6 : 4)
            .position(x: centerX, y: positionY)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(isActive ? 0.9 : 0.5))
                    .frame(width: 20, height: 20)
                    .position(x: centerX, y: positionY)
            )
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard isActive else { return }
                let clampedY = min(max(value.location.y, 0), size.height)
                update(clampedY)
            })
            .allowsHitTesting(isActive)
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
