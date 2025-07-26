//
//  MeasurementTable.swift
//  MedidorOticaApp
//
//  Tabela com as medidas detectadas automaticamente.
//

import SwiftUI

struct MeasurementTable: View {
    let landmarks: FrameLandmarks
    let imageSize: CGSize
    private let mmPerPixel: Double = 0.2

    // MARK: - View
    var body: some View {
        VStack(alignment: .leading) {
            Text("Medições")
                .font(.headline)

            TableRow(title: "DNP", value: formatted(distanceBetween(landmarks.leftPupil, landmarks.rightPupil)))
            TableRow(title: "Altura Pupilar", value: formatted(verticalDistance(from: CGPoint(x: 0, y: landmarks.topLineY), to: landmarks.leftPupil)))
            TableRow(title: "Largura da Armação", value: formatted(horizontalLength()))
            TableRow(title: "Altura da Armação", value: formatted(verticalLength()))
            TableRow(title: "Diagonal", value: formatted(diagonal()))
        }
    }

    /// Distância em pixels entre dois pontos
    private func pixelDistance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double((b.x - a.x) * imageSize.width)
        let dy = Double((b.y - a.y) * imageSize.height)
        return sqrt(dx * dx + dy * dy)
    }

    /// Distância em milímetros entre dois pontos
    private func distanceBetween(_ a: CGPoint, _ b: CGPoint) -> Double {
        pixelDistance(a, b) * mmPerPixel
    }

    /// Distância vertical em milímetros entre dois pontos
    private func verticalDistance(from a: CGPoint, to b: CGPoint) -> Double {
        let dy = Double((b.y - a.y) * imageSize.height)
        return abs(dy) * mmPerPixel
    }

    /// Calcula a diagonal da armação
    private func diagonal() -> Double {
        let width = horizontalLength()
        let height = verticalLength()
        return sqrt(width * width + height * height)
    }

    /// Largura da armação em milímetros
    private func horizontalLength() -> Double {
        let pixels = Double((landmarks.rightLineX - landmarks.leftLineX) * imageSize.width)
        return abs(pixels) * mmPerPixel
    }

    /// Altura da armação em milímetros
    private func verticalLength() -> Double {
        let pixels = Double((landmarks.bottomLineY - landmarks.topLineY) * imageSize.height)
        return abs(pixels) * mmPerPixel
    }

    /// Formata um valor para exibição em milímetros
    private func formatted(_ value: Double) -> String {
        String(format: "%.1f mm", value)
    }
}

/// Linha simples da tabela de medidas
private struct TableRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }
}

// MARK: - Preview
struct MeasurementTable_Previews: PreviewProvider {
    static var previews: some View {
        MeasurementTable(landmarks: FrameLandmarks(leftLineX: 0.1,
                                                   rightLineX: 0.9,
                                                   topLineY: 0.2,
                                                   bottomLineY: 0.8,
                                                   leftPupil: CGPoint(x: 0.3, y: 0.3),
                                                   rightPupil: CGPoint(x: 0.7, y: 0.3)),
                          imageSize: CGSize(width: 1000, height: 1000))
    }
}
