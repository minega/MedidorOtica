//
//  ManualAdjustmentView.swift
//  MedidorOticaApp
//
//  Permite arrastar os marcadores detectados para ajuste fino.
//

import SwiftUI

struct ManualAdjustmentView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var landmarks: FrameLandmarks
    let image: UIImage

    // MARK: - View
    var body: some View {
        VStack {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)

                GeometryReader { geo in
                    DraggableVerticalLine(value: $landmarks.leftLineX, geoSize: geo.size)
                    DraggableVerticalLine(value: $landmarks.rightLineX, geoSize: geo.size)
                    DraggableHorizontalLine(value: $landmarks.topLineY, geoSize: geo.size)
                    DraggableHorizontalLine(value: $landmarks.bottomLineY, geoSize: geo.size)
                    DraggablePoint(position: $landmarks.leftPupil, geoSize: geo.size)
                    DraggablePoint(position: $landmarks.rightPupil, geoSize: geo.size)
                }
            }
            .padding()

            Button("Concluir") { dismiss() }
                .padding()
        }
    }
}

// MARK: - Ponto Arrastável
private struct DraggablePoint: View {
    @Binding var position: CGPoint
    let geoSize: CGSize

    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 12, height: 12)
            .position(x: position.x * geoSize.width, y: position.y * geoSize.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newX = min(max(0, value.location.x / geoSize.width), 1)
                        let newY = min(max(0, value.location.y / geoSize.height), 1)
                        position = CGPoint(x: newX, y: newY)
                    }
            )
    }
}

// MARK: - Linha Vertical Arrastável
private struct DraggableVerticalLine: View {
    @Binding var value: CGFloat
    let geoSize: CGSize

    var body: some View {
        Rectangle()
            .fill(Color.green)
            .frame(width: 2, height: geoSize.height)
            .position(x: value * geoSize.width, y: geoSize.height / 2)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        let newX = min(max(0, gesture.location.x / geoSize.width), 1)
                        value = newX
                    }
            )
    }
}

// MARK: - Linha Horizontal Arrastável
private struct DraggableHorizontalLine: View {
    @Binding var value: CGFloat
    let geoSize: CGSize

    var body: some View {
        Rectangle()
            .fill(Color.green)
            .frame(width: geoSize.width, height: 2)
            .position(x: geoSize.width / 2, y: value * geoSize.height)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        let newY = min(max(0, gesture.location.y / geoSize.height), 1)
                        value = newY
                    }
            )
    }
}

// MARK: - Preview
struct ManualAdjustmentView_Previews: PreviewProvider {
    @State static var landmarks = FrameLandmarks(leftLineX: 0.2,
                                                 rightLineX: 0.8,
                                                 topLineY: 0.3,
                                                 bottomLineY: 0.7,
                                                 leftPupil: CGPoint(x: 0.4, y: 0.5),
                                                 rightPupil: CGPoint(x: 0.6, y: 0.5))

    static var previews: some View {
        ManualAdjustmentView(landmarks: $landmarks,
                             image: UIImage(systemName: "person.fill")!)
    }
}
