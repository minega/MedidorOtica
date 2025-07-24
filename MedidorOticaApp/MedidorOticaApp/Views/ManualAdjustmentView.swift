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
                    DraggablePoint(position: $landmarks.leftPoint, geoSize: geo.size)
                    DraggablePoint(position: $landmarks.rightPoint, geoSize: geo.size)
                    DraggablePoint(position: $landmarks.topPoint, geoSize: geo.size)
                    DraggablePoint(position: $landmarks.bottomPoint, geoSize: geo.size)
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

// MARK: - Preview
struct ManualAdjustmentView_Previews: PreviewProvider {
    @State static var landmarks = FrameLandmarks(leftPoint: CGPoint(x: 0.2, y: 0.5),
                                                 rightPoint: CGPoint(x: 0.8, y: 0.5),
                                                 topPoint: CGPoint(x: 0.5, y: 0.3),
                                                 bottomPoint: CGPoint(x: 0.5, y: 0.7),
                                                 leftPupil: CGPoint(x: 0.4, y: 0.5),
                                                 rightPupil: CGPoint(x: 0.6, y: 0.5))

    static var previews: some View {
        ManualAdjustmentView(landmarks: $landmarks,
                             image: UIImage(systemName: "person.fill")!)
    }
}
