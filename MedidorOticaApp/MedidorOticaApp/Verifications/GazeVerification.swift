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

// Extensão para verificação de direção do olhar
extension VerificationManager {
    
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
    
    // Implementação para a câmera frontal (TrueDepth)
    private func checkGazeWithTrueDepth(faceAnchor: ARFaceAnchor, frame: ARFrame) -> Bool {
        guard #available(iOS 12.0, *) else { return false }

        // Permite pequena margem para piscadas involuntárias
        let shapes = faceAnchor.blendShapes
        let blinkOk = (shapes[.eyeBlinkLeft]?.floatValue ?? 0) < 0.3 &&
                      (shapes[.eyeBlinkRight]?.floatValue ?? 0) < 0.3
        guard blinkOk else { return false }

        // Posição do dispositivo
        let cameraPos = simd_make_float3(frame.camera.transform.columns.3)

        // Matriz dos olhos no sistema do mundo
        let leftEyeMatrix = simd_mul(faceAnchor.transform, faceAnchor.leftEyeTransform)
        let rightEyeMatrix = simd_mul(faceAnchor.transform, faceAnchor.rightEyeTransform)

        // Vetores olhando para frente de cada olho (eixo -Z)
        let leftForward = -simd_make_float3(leftEyeMatrix.columns.2)
        let rightForward = -simd_make_float3(rightEyeMatrix.columns.2)

        // Vetores dos olhos até a câmera
        let leftToCamera = simd_normalize(cameraPos - simd_make_float3(leftEyeMatrix.columns.3))
        let rightToCamera = simd_normalize(cameraPos - simd_make_float3(rightEyeMatrix.columns.3))

        // Ângulo entre o vetor do olho e a câmera
        let leftAngle = acos(clamp(simd_dot(simd_normalize(leftForward), leftToCamera), min: -1, max: 1))
        let rightAngle = acos(clamp(simd_dot(simd_normalize(rightForward), rightToCamera), min: -1, max: 1))

        let angleLimit: Float = .pi / 12 // ±15 graus
        let aligned = leftAngle < angleLimit && rightAngle < angleLimit

        DispatchQueue.main.async {
            self.gazeData = [
                "left": leftAngle,
                "right": rightAngle
            ]
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

            let aligned = checkEyeAlignment(leftEye: leftEye, rightEye: rightEye,
                                            leftPupil: leftPupil, rightPupil: rightPupil) &&
                           checkHeadRotation(faceObservation: face)

            DispatchQueue.main.async {
                self.gazeData = ["aligned": aligned ? 1.0 : 0.0]
                print("Verificação de olhar (LiDAR): \(aligned)")
            }

            return aligned
        } catch {
            print("ERRO na verificação de olhar com LiDAR: \(error)")
            return false
        }
    }
    
    // Função auxiliar para verificar o alinhamento dos olhos
    private func checkEyeAlignment(leftEye: VNFaceLandmarkRegion2D, rightEye: VNFaceLandmarkRegion2D,
                                leftPupil: VNFaceLandmarkRegion2D, rightPupil: VNFaceLandmarkRegion2D) -> Bool {
        
        // Calcula os centros dos olhos
        let leftEyePoints = leftEye.normalizedPoints
        let rightEyePoints = rightEye.normalizedPoints
        let leftPupilPoints = leftPupil.normalizedPoints
        let rightPupilPoints = rightPupil.normalizedPoints
        
        // Calcula os centros médios
        let leftEyeCenter = averagePoint(from: leftEyePoints)
        let rightEyeCenter = averagePoint(from: rightEyePoints)
        let leftPupilCenter = averagePoint(from: leftPupilPoints)
        let rightPupilCenter = averagePoint(from: rightPupilPoints)
        
        // Calcula os desvios
        let leftDeviationX = abs(leftPupilCenter.x - leftEyeCenter.x)
        let rightDeviationX = abs(rightPupilCenter.x - rightEyeCenter.x)
        let leftDeviationY = abs(leftPupilCenter.y - leftEyeCenter.y)
        let rightDeviationY = abs(rightPupilCenter.y - rightEyeCenter.y)
        
        // Threshold mais permissivo para maior confiabilidade
        let deviationThreshold: CGFloat = 0.08
        
        // O olhar está alinhado se as pupilas estiverem centradas
        return leftDeviationX < deviationThreshold && rightDeviationX < deviationThreshold &&
               leftDeviationY < deviationThreshold && rightDeviationY < deviationThreshold
    }
    
    // Função auxiliar para verificar a rotação da cabeça
    private func checkHeadRotation(faceObservation: VNFaceObservation) -> Bool {
        // Obtém os ângulos de rotação se disponíveis
        let roll = faceObservation.roll?.doubleValue ?? 0.0
        let yaw = faceObservation.yaw?.doubleValue ?? 0.0
        let pitch = faceObservation.pitch?.doubleValue ?? 0.0
        
        // Threshold rigoroso para a rotação da cabeça (0.15 radianos ≈ 8.6 graus)
        let rotationThreshold = 0.15
        
        // A cabeça está alinhada se todas as rotações forem mínimas
        return abs(roll) < rotationThreshold && abs(yaw) < rotationThreshold && abs(pitch) < rotationThreshold
    }
    
    // Mantém a função original para compatibilidade com código existente
    func checkGaze(using faceAnchor: ARFaceAnchor, frame: ARFrame) -> Bool {
        return checkGazeWithTrueDepth(faceAnchor: faceAnchor, frame: frame)
    }

    /// Limita um valor dentro de um intervalo fechado
    private func clamp(_ value: Float, min: Float, max: Float) -> Float {
        if value < min { return min }
        if value > max { return max }
        return value
    }
}
