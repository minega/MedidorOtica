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
@MainActor
extension VerificationManager {

    // MARK: - Configuração de Margem de Erro
    /// Ajuste aqui os limites de tolerância para cada sensor
    private enum GazeConfig {
        /// Máximo em radianos para desvio do olhar no TrueDepth
        static let angleLimit: Float = .pi / 12 // ±15 graus
        /// Máximo em pontos normalizados para desvio da pupila no LiDAR
        static let deviationThreshold: CGFloat = 0.08
    }

    // MARK: - Verificação 7: Direção do Olhar
    
    /// Verifica a direção do olhar utilizando o sensor disponível.
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
    /// Calcula e publica a posição das pupilas para depuração visual.
    /// - Parameter frame: Frame atual processado pela sessão AR.
    func updatePupilPoints(using frame: ARFrame) {
        var left: CGPoint?
        var right: CGPoint?

        if hasTrueDepth || hasLiDAR {
            (left, right) = visionPupilPoints(from: frame)
        }

        DispatchQueue.main.async {
            self.leftPupilPoint = left
            self.rightPupilPoint = right
        }
    }
    
    // Implementação para a câmera frontal (TrueDepth)
    private func checkGazeWithTrueDepth(faceAnchor: ARFaceAnchor, frame: ARFrame) -> Bool {
        // Permite piscadas curtas sem invalidar a verificação
        let shapes = faceAnchor.blendShapes
        let blinkOk = (shapes[.eyeBlinkLeft]?.floatValue ?? 0) < 0.3 &&
                      (shapes[.eyeBlinkRight]?.floatValue ?? 0) < 0.3
        guard blinkOk else { return false }

        // Pontos normalizados das pupilas
        let (leftNorm, rightNorm) = visionPupilPoints(from: frame)

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
            let leftDesc = leftNorm.map { "\($0.x),\($0.y)" } ?? "nil"
            let rightDesc = rightNorm.map { "\($0.x),\($0.y)" } ?? "nil"
            print("Pupila esquerda: \(leftDesc), direita: \(rightDesc)")
            print("Verificação de olhar (TrueDepth): \(aligned)")
        }

        return aligned
    }
    
    // Implementação para a câmera traseira (LiDAR)
    private func checkGazeWithLiDAR(frame: ARFrame) -> Bool {
        let request = makeLandmarksRequest()
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

            // Converte para coordenadas absolutas (origem no canto inferior esquerdo)
            let leftAbs = CGPoint(x: bounding.origin.x + leftP.x * bounding.width,
                                  y: bounding.origin.y + leftP.y * bounding.height)
            let rightAbs = CGPoint(x: bounding.origin.x + rightP.x * bounding.width,
                                   y: bounding.origin.y + rightP.y * bounding.height)

            // Ajusta para o sistema de coordenadas da interface (origem no canto superior esquerdo)
            let leftNorm = CGPoint(x: leftAbs.x, y: 1.0 - leftAbs.y)
            let rightNorm = CGPoint(x: rightAbs.x, y: 1.0 - rightAbs.y)

            DispatchQueue.main.async {
                self.leftPupilPoint = leftNorm
                self.rightPupilPoint = rightNorm
                self.gazeData = ["aligned": aligned ? 1.0 : 0.0]
                let leftDesc = "\(leftNorm.x),\(leftNorm.y)"
                let rightDesc = "\(rightNorm.x),\(rightNorm.y)"
                print("Pupila esquerda: \(leftDesc), direita: \(rightDesc)")
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

    /// Limita um valor dentro de um intervalo fechado
    private func clamp(_ value: Float, min: Float, max: Float) -> Float {
        if value < min { return min }
        if value > max { return max }
        return value
    }

    // MARK: - Cálculo dos Pontos das Pupilas
    /// Extrai as pupilas do frame usando Vision e retorna pontos normalizados.
    /// - Parameter frame: `ARFrame` capturado no momento.
    /// - Returns: Tupla com os pontos das pupilas esquerda e direita.
    private func visionPupilPoints(from frame: ARFrame) -> (CGPoint?, CGPoint?) {
        let request = makeLandmarksRequest()
        let orientation = currentCGOrientation()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage,
                                            orientation: orientation,
                                            options: [:])
        do {
            try handler.perform([request])
            guard let face = request.results?.first as? VNFaceObservation,
                  let left = face.landmarks?.leftPupil,
                  let right = face.landmarks?.rightPupil else {
                return (nil, nil)
            }

            let width = CGFloat(CVPixelBufferGetWidth(frame.capturedImage))
            let height = CGFloat(CVPixelBufferGetHeight(frame.capturedImage))

            let leftP = averagePoint(from: left.normalizedPoints)
            let rightP = averagePoint(from: right.normalizedPoints)

            // `VNImagePointForNormalizedPoint` espera coordenadas normalizadas
            // e retorna pontos em pixels considerando largura e altura da imagem
            let leftPixel = VNImagePointForNormalizedPoint(leftP, Int(width), Int(height))
            let rightPixel = VNImagePointForNormalizedPoint(rightP, Int(width), Int(height))

            var leftNorm = CGPoint(x: leftPixel.x / width, y: 1.0 - (leftPixel.y / height))
            var rightNorm = CGPoint(x: rightPixel.x / width, y: 1.0 - (rightPixel.y / height))

            if CameraManager.shared.cameraPosition == .front {
                leftNorm.x = 1.0 - leftNorm.x
                rightNorm.x = 1.0 - rightNorm.x
            }

            return (leftNorm, rightNorm)
        } catch {
            print("ERRO ao extrair pupilas: \(error)")
            return (nil, nil)
        }
    }

}
