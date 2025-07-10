//
//  GazeVerification.swift
//  MedidorOticaApp
//
//  Verificação 7: Direção do olhar
//  Utiliza ARKit para verificar se o olhar está perfeitamente alinhado com a câmera
//  Suporta câmera frontal (TrueDepth) e traseira (LiDAR)
//

import ARKit
import Vision

// Extensão para verificação de direção do olhar
extension VerificationManager {
    
    // MARK: - Verificação 7: Direção do Olhar
    
    /// Verifica a direção do olhar utilizando o sensor disponível
    func checkGaze(using frame: ARFrame) -> Bool {
        if hasTrueDepth,
           let anchor = frame.anchors.first(where: { $0 is ARFaceAnchor }) as? ARFaceAnchor {
            return checkGazeWithTrueDepth(faceAnchor: anchor)
        }
        if hasLiDAR { return checkGazeWithLiDAR(frame: frame) }

        print("ERRO: Nenhum sensor de profundidade disponível para verificação do olhar")
        return false
    }
    
    // Implementação para a câmera frontal (TrueDepth)
    private func checkGazeWithTrueDepth(faceAnchor: ARFaceAnchor) -> Bool {
        guard #available(iOS 12.0, *) else { return false }

        let shapes = faceAnchor.blendShapes
        let blinkOk = (shapes[.eyeBlinkLeft]?.floatValue ?? 0) < 0.2 &&
                      (shapes[.eyeBlinkRight]?.floatValue ?? 0) < 0.2
        guard blinkOk else { return false }

        let limit: Float = 0.0001
        let horizKeys: [ARFaceAnchor.BlendShapeLocation] = [.eyeLookInLeft, .eyeLookInRight, .eyeLookOutLeft, .eyeLookOutRight]
        let vertKeys: [ARFaceAnchor.BlendShapeLocation] = [.eyeLookUpLeft, .eyeLookUpRight, .eyeLookDownLeft, .eyeLookDownRight]

        let horizontal = horizKeys.allSatisfy { (shapes[$0]?.floatValue ?? 0) < limit }
        let vertical = vertKeys.allSatisfy { (shapes[$0]?.floatValue ?? 0) < limit }
        let aligned = horizontal && vertical

        DispatchQueue.main.async {
            self.gazeData = [
                "leftIn": shapes[.eyeLookInLeft]?.floatValue ?? 0,
                "rightIn": shapes[.eyeLookInRight]?.floatValue ?? 0,
                "leftOut": shapes[.eyeLookOutLeft]?.floatValue ?? 0,
                "rightOut": shapes[.eyeLookOutRight]?.floatValue ?? 0,
                "leftUp": shapes[.eyeLookUpLeft]?.floatValue ?? 0,
                "rightUp": shapes[.eyeLookUpRight]?.floatValue ?? 0,
                "leftDown": shapes[.eyeLookDownLeft]?.floatValue ?? 0,
                "rightDown": shapes[.eyeLookDownRight]?.floatValue ?? 0
            ]
            print("Verificação de olhar (ARKit): \(aligned)")
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
        
        // Threshold rigoroso para o olhar
        let deviationThreshold: CGFloat = 0.05
        
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
    func checkGaze(using faceAnchor: ARFaceAnchor) -> Bool {
        return checkGazeWithTrueDepth(faceAnchor: faceAnchor)
    }
}
