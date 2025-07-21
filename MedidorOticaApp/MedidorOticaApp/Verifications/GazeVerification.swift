//
//  GazeVerification.swift
//  MedidorOticaApp
//
//  Verificação 7: Direção do olhar
//  Utiliza ARKit/Vision para confirmar se o olhar converge para a lente
//  Calcula o ângulo entre o vetor dos olhos e a posição da câmera
//  Suporta câmera frontal (TrueDepth) e traseira (LiDAR)
//

import ARKit
import Vision
import simd
import UIKit

// Extensão para verificação de direção do olhar
extension VerificationManager {

    // MARK: - Configuração de Margem de Erro
    /// Ajuste aqui os limites de tolerância para cada sensor
    private enum GazeConfig {
        /// Máximo em radianos para desvio do olhar no TrueDepth
        static var angleLimit: Float = .pi / 12 // ±15 graus
        /// Máximo em pontos normalizados para desvio da pupila no LiDAR
        static var deviationThreshold: CGFloat = 0.08
    }

    // MARK: - Verificação 7: Direção do Olhar
    
    /// Verifica a direção do olhar utilizando o sensor disponível
    func checkGaze(using frame: ARFrame) -> Bool {
        if hasTrueDepth,
           let anchor = frame.anchors.first(where: { $0 is ARFaceAnchor }) as? ARFaceAnchor {
            return checkGazeWithTrueDepth(faceAnchor: anchor, frame: frame)
        }
        if hasLiDAR { return checkGazeWithLiDAR(frame: frame) }

        print("ERRO: Nenhum sensor de profundidade disponível para verificação do olhar")
        return false
    }

    // MARK: - Atualização das Pupilas
    /// Calcula e publica a posição das pupilas para depuração
    func updatePupilPoints(using frame: ARFrame, faceAnchor: ARFaceAnchor? = nil) {
        var left: CGPoint?
        var right: CGPoint?

        if hasTrueDepth, let anchor = faceAnchor {
            (left, right) = pupilPointsTrueDepth(anchor: anchor, frame: frame)
        } else if hasLiDAR {
            (left, right) = pupilPointsLiDAR(frame: frame)
        }

        DispatchQueue.main.async {
            self.leftPupilPoint = left
            self.rightPupilPoint = right
        }
    }
    
    // Implementação para a câmera frontal (TrueDepth)
    private func checkGazeWithTrueDepth(faceAnchor: ARFaceAnchor, frame: ARFrame) -> Bool {
        guard #available(iOS 12.0, *) else { return false }

        // Permite piscadas curtas sem invalidar a verificação
        let shapes = faceAnchor.blendShapes
        let blinkOk = (shapes[.eyeBlinkLeft]?.floatValue ?? 0) < 0.3 &&
                      (shapes[.eyeBlinkRight]?.floatValue ?? 0) < 0.3
        guard blinkOk else { return false }

        // Pontos normalizados das pupilas
        let (leftNorm, rightNorm) = pupilPointsTrueDepth(anchor: faceAnchor, frame: frame)

        // Converte o ponto observado para o sistema da câmera
        let worldToCamera = simd_inverse(frame.camera.transform)
        let lookPointWorld = simd_make_float4(faceAnchor.lookAtPoint, 1)
        let lookPointCamera = simd_mul(worldToCamera, lookPointWorld)

        // Vetor de observação normalizado
        let lookVector = simd_normalize(simd_make_float3(lookPointCamera))
        let cameraForward = simd_float3(0, 0, -1)

        let angle = acos(clamp(simd_dot(lookVector, cameraForward), min: -1, max: 1))
        let aligned = angle < GazeConfig.angleLimit

        DispatchQueue.main.async {
            self.leftPupilPoint = leftNorm
            self.rightPupilPoint = rightNorm
            self.gazeData = ["angle": angle]
            print("Pupila esquerda: \(leftNorm), direita: \(rightNorm)")
            print("Verificação de olhar (TrueDepth): \(aligned)")
        }

        return aligned
    }
    
    // Implementação para a câmera traseira (LiDAR)
    @available(iOS 13.4, *)
    private func checkGazeWithLiDAR(frame: ARFrame) -> Bool {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage,
                                            orientation: currentCGOrientation(),
                                            options: [:])
        do {
            try handler.perform([request])
            guard let face = request.results?.first as? VNFaceObservation,
                  let landmarks = face.landmarks,
                  let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye,
                  let leftPupil = landmarks.leftPupil, let rightPupil = landmarks.rightPupil else {
                return false
            }

            let leftDev = eyeDeviation(eye: leftEye, pupil: leftPupil)
            let rightDev = eyeDeviation(eye: rightEye, pupil: rightPupil)
            let aligned = leftDev < GazeConfig.deviationThreshold &&
                          rightDev < GazeConfig.deviationThreshold

            let leftP = averagePoint(from: leftPupil.normalizedPoints)
            let rightP = averagePoint(from: rightPupil.normalizedPoints)
            let bounding = face.boundingBox
            let leftAbs = CGPoint(x: bounding.origin.x + leftP.x * bounding.width,
                                  y: bounding.origin.y + leftP.y * bounding.height)
            let rightAbs = CGPoint(x: bounding.origin.x + rightP.x * bounding.width,
                                   y: bounding.origin.y + rightP.y * bounding.height)
            // Mantém a origem no canto superior esquerdo do overlay.
            let leftNorm = CGPoint(x: leftAbs.x, y: leftAbs.y)
            let rightNorm = CGPoint(x: rightAbs.x, y: rightAbs.y)

            DispatchQueue.main.async {
                self.leftPupilPoint = leftNorm
                self.rightPupilPoint = rightNorm
                self.gazeData = ["aligned": aligned ? 1.0 : 0.0]
                print("Pupila esquerda: \(leftNorm), direita: \(rightNorm)")
                print("Verificação de olhar (LiDAR): \(aligned)")
            }

            return aligned
        } catch {
            print("ERRO na verificação de olhar com LiDAR: \(error)")
            return false
        }
    }

    /// Distância da pupila até o centro do olho
    private func eyeDeviation(eye: VNFaceLandmarkRegion2D, pupil: VNFaceLandmarkRegion2D) -> CGFloat {
        let eyeCenter = averagePoint(from: eye.normalizedPoints)
        let pupilCenter = averagePoint(from: pupil.normalizedPoints)
        return hypot(pupilCenter.x - eyeCenter.x, pupilCenter.y - eyeCenter.y)
    }

    /// Verifica se a cabeça está centralizada (mínima rotação)
    private func headIsCentered(_ face: VNFaceObservation) -> Bool {
        let roll = face.roll?.doubleValue ?? 0.0
        let yaw = face.yaw?.doubleValue ?? 0.0
        let pitch = face.pitch?.doubleValue ?? 0.0
        let limit = 0.1 // ~6 graus
        return abs(roll) < limit && abs(yaw) < limit && abs(pitch) < limit
    }

    /// Limita um valor dentro de um intervalo fechado
    private func clamp(_ value: Float, min: Float, max: Float) -> Float {
        if value < min { return min }
        if value > max { return max }
        return value
    }

    // MARK: - Cálculo dos Pontos das Pupilas
    private func pupilPointsTrueDepth(anchor: ARFaceAnchor, frame: ARFrame) -> (CGPoint?, CGPoint?) {
        let leftWorld = simd_mul(anchor.transform, anchor.leftEyeTransform)
        let rightWorld = simd_mul(anchor.transform, anchor.rightEyeTransform)
        let left3D = simd_make_float3(leftWorld.columns.3)
        let right3D = simd_make_float3(rightWorld.columns.3)

        let viewport = UIScreen.main.bounds.size
        let orientation = currentUIOrientation()
        let left2D = frame.camera.projectPoint(left3D, orientation: orientation, viewportSize: viewport)
        let right2D = frame.camera.projectPoint(right3D, orientation: orientation, viewportSize: viewport)

        // ARKit já fornece as coordenadas considerando a orientação atual.
        // Normaliza mantendo a origem no canto superior esquerdo para o overlay.
        let leftNorm = CGPoint(x: left2D.x / viewport.width,
                               y: left2D.y / viewport.height)
        let rightNorm = CGPoint(x: right2D.x / viewport.width,
                                y: right2D.y / viewport.height)
        return (leftNorm, rightNorm)
    }

    @available(iOS 13.4, *)
    private func pupilPointsLiDAR(frame: ARFrame) -> (CGPoint?, CGPoint?) {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage,
                                            orientation: currentCGOrientation(),
                                            options: [:])
        do {
            try handler.perform([request])
            guard let face = request.results?.first as? VNFaceObservation,
                  let leftPupil = face.landmarks?.leftPupil,
                  let rightPupil = face.landmarks?.rightPupil else {
                return (nil, nil)
            }

            let left = averagePoint(from: leftPupil.normalizedPoints)
            let right = averagePoint(from: rightPupil.normalizedPoints)
            let bounding = face.boundingBox
            let leftAbs = CGPoint(x: bounding.origin.x + left.x * bounding.width,
                                  y: bounding.origin.y + left.y * bounding.height)
            let rightAbs = CGPoint(x: bounding.origin.x + right.x * bounding.width,
                                   y: bounding.origin.y + right.y * bounding.height)

            // Mantém o sistema de coordenadas com origem no canto superior esquerdo.
            let leftNorm = CGPoint(x: leftAbs.x, y: leftAbs.y)
            let rightNorm = CGPoint(x: rightAbs.x, y: rightAbs.y)
            return (leftNorm, rightNorm)
        } catch {
            print("ERRO ao extrair pupilas: \(error)")
            return (nil, nil)
        }
    }
}
