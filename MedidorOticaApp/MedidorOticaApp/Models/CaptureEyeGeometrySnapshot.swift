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
    /// Geometria de um olho individual no referencial da camera.
    struct EyeSnapshot: Codable, Equatable {
        var centerCamera: CodableVector3
        var gazeCamera: CodableVector3
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
