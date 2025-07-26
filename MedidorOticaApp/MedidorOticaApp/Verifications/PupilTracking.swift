//
//  PupilTracking.swift
//  MedidorOticaApp
//
//  Detecta a posição das pupilas e verifica se o olhar está alinhado.
//

import ARKit
import Vision
import simd
import UIKit

@MainActor
extension VerificationManager {
    // MARK: - Rastreamento das Pupilas
    /// Atualiza `leftPupilPoint` e `rightPupilPoint` com valores normalizados.
    /// - Parameter frame: Frame atual da sessão AR.
    func updatePupilPoints(using frame: ARFrame) {
        let orientation = currentCGOrientation()
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            let (left, right) = self.detectPupils(in: frame, orientation: orientation)
            DispatchQueue.main.async {
                self.leftPupilPoint = left
                self.rightPupilPoint = right
            }
        }
    }

    // MARK: - Verificação do Olhar
    /// Confere se o usuário está olhando para a câmera.
    /// - Parameter frame: Frame com os dados de rosto.
    /// - Returns: `true` se o olhar estiver alinhado.
    func checkGaze(using frame: ARFrame) -> Bool {
        if hasTrueDepth,
           let anchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first {
            return gazeWithTrueDepth(anchor: anchor, frame: frame)
        }
        if hasLiDAR { return gazeWithLiDAR(frame: frame) }
        return false
    }

    // MARK: - Implementação privada
    private func detectPupils(in frame: ARFrame,
                              orientation: CGImagePropertyOrientation) -> (CGPoint?, CGPoint?) {
        let buffer = frame.capturedImage
        let (width, height) = orientedDimensions(for: buffer, orientation: orientation)

        if #available(iOS 17, *),
           let gazeClass = NSClassFromString("VNGazeTrackingRequest") as? VNRequest.Type {
            let request = gazeClass.init()
            (request as NSObject).setValue(1, forKey: "revision")
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer,
                                                orientation: orientation)
            do {
                try handler.perform([request])
                if let results = (request as NSObject).value(forKey: "results") as? [Any],
                   let gaze = results.first as? NSObject,
                   let left = gaze.value(forKey: "leftPupil") as? CGPoint,
                   let right = gaze.value(forKey: "rightPupil") as? CGPoint {
                    let l = normalizedPoint(left, width: width, height: height, orientation: orientation)
                    let r = normalizedPoint(right, width: width, height: height, orientation: orientation)
                    return (l, r)
                }
            } catch {
                print("Falha no VNGazeTrackingRequest: \(error)")
            }
        }

        let request = makeLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer,
                                            orientation: orientation)
        do {
            try handler.perform([request])
            guard let face = request.results?.first as? VNFaceObservation,
                  let left = face.landmarks?.leftPupil?.normalizedPoints.first,
                  let right = face.landmarks?.rightPupil?.normalizedPoints.first else {
                return (nil, nil)
            }
            let leftPixel = VNImagePointForNormalizedPoint(left, width, height)
            let rightPixel = VNImagePointForNormalizedPoint(right, width, height)
            let l = normalizedPoint(leftPixel, width: width, height: height, orientation: orientation)
            let r = normalizedPoint(rightPixel, width: width, height: height, orientation: orientation)
            return (l, r)
        } catch {
            print("Erro ao detectar pupilas: \(error)")
            return (nil, nil)
        }
    }

    private func gazeWithTrueDepth(anchor: ARFaceAnchor, frame: ARFrame) -> Bool {
        let worldToCamera = simd_inverse(frame.camera.transform)
        let lookWorld = simd_make_float4(anchor.lookAtPoint, 1)
        let lookCamera = simd_mul(worldToCamera, lookWorld)
        let vector = simd_normalize(simd_make_float3(lookCamera))
        let angle = acos(max(min(simd_dot(vector, simd_float3(0, 0, -1)), 1), -1))
        return angle < (.pi / 12)
    }

    private func gazeWithLiDAR(frame: ARFrame) -> Bool {
        let orientation = currentCGOrientation()
        let request = makeLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage,
                                            orientation: orientation)
        do {
            try handler.perform([request])
            guard let face = request.results?.first as? VNFaceObservation,
                  let landmarks = face.landmarks,
                  let leftEye = landmarks.leftEye,
                  let rightEye = landmarks.rightEye else {
                return false
            }
            let (left, right) = detectPupils(in: frame, orientation: orientation)
            guard let lp = left, let rp = right else { return false }
            let leftDev = eyeDeviation(eye: leftEye, pupil: lp)
            let rightDev = eyeDeviation(eye: rightEye, pupil: rp)
            return leftDev < 0.08 && rightDev < 0.08
        } catch {
            print("Erro ao verificar olhar: \(error)")
            return false
        }
    }

    private func eyeDeviation(eye: VNFaceLandmarkRegion2D, pupil: CGPoint) -> CGFloat {
        let center = averagePoint(from: eye.normalizedPoints)
        return hypot(pupil.x - center.x, pupil.y - center.y)
    }
}
