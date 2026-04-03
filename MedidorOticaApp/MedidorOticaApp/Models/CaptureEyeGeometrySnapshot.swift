//
//  CaptureEyeGeometrySnapshot.swift
//  MedidorOticaApp
//
//  Persiste a geometria ocular 3D da captura para recalcular DNP perto e longe.
//

import Foundation
import simd

// MARK: - Vetor 3D codificavel
/// Representa um vetor 3D em formato persistivel.
struct CodableVector3: Codable, Equatable {
    var x: Double
    var y: Double
    var z: Double

    /// Inicializa a estrutura a partir de um vetor do `simd`.
    init(_ value: SIMD3<Float>) {
        self.x = Double(value.x)
        self.y = Double(value.y)
        self.z = Double(value.z)
    }

    /// Construtor explicito para restaurar valores persistidos.
    init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// Retorna o vetor no formato nativo do `simd`.
    var simdValue: SIMD3<Float> {
        SIMD3<Float>(Float(x), Float(y), Float(z))
    }
}

// MARK: - Snapshot ocular
/// Geometria ocular do frame final usada para converter DNP perto em DNP longe.
struct CaptureEyeGeometrySnapshot: Codable, Equatable {
    /// Aproximacao linear da projecao 3D -> imagem ao redor do centro do olho.
    struct LinearizedProjection: Codable, Equatable {
        var projectedCenter: NormalizedPoint
        var normalizedXPerMeter: CodableVector3
        var normalizedYPerMeter: CodableVector3

        /// Projeta um deslocamento 3D pequeno no espaco da imagem normalizada.
        func projectedPoint(for delta: SIMD3<Float>) -> NormalizedPoint {
            let xDelta = simd_dot(normalizedXPerMeter.simdValue, delta)
            let yDelta = simd_dot(normalizedYPerMeter.simdValue, delta)
            return NormalizedPoint(x: projectedCenter.x + CGFloat(xDelta),
                                   y: projectedCenter.y + CGFloat(yDelta)).clamped()
        }
    }

    /// Geometria de um olho individual no referencial da camera.
    struct EyeSnapshot: Codable, Equatable {
        var centerCamera: CodableVector3
        var gazeCamera: CodableVector3
        var projection: LinearizedProjection?
    }

    var leftEye: EyeSnapshot
    var rightEye: EyeSnapshot
    var pcCameraPosition: CodableVector3
    var fixationConfidence: Double
    var fixationConfidenceReason: String?
    var strongestGazeDeviation: Double

    /// Indica se a confianca da fixacao e suficiente para considerar a conversao robusta.
    var isFixationReliable: Bool {
        fixationConfidence >= 0.65
    }
}
