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
import UIKit
import AVFoundation

// Extensão para verificação de direção do olhar
extension VerificationManager {
    
    // MARK: - Verificação 7: Direção do Olhar
    
    // Função principal para verificar o olhar com ARKit
    func checkGaze(using frame: ARFrame) -> Bool {
        // Verifica se há um rosto no frame atual
        if let faceAnchor = frame.anchors.first(where: { $0 is ARFaceAnchor }) as? ARFaceAnchor {
            // Câmera frontal com TrueDepth
            return checkGazeWithTrueDepth(faceAnchor: faceAnchor)
        } else if #available(iOS 13.4, *), ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            // Câmera traseira com LiDAR
            return checkGazeWithLiDAR(frame: frame)
        } else {
            print("ERRO: Nenhum sensor de profundidade disponível para verificação do olhar")
            return false
        }
    }
    
    // Implementação para a câmera frontal (TrueDepth)
    private func checkGazeWithTrueDepth(faceAnchor: ARFaceAnchor) -> Bool {
        // A verificação de olhar deve ser absolutamente precisa (sem margem de erro)
        // conforme solicitado pelo usuário
        
        // Verifica se o ARKit suporta tracking de olhos
        guard #available(iOS 12.0, *) else {
            print("ERRO: Tracking de olhos requer iOS 12.0 ou superior")
            return false
        }
        
        // Acessa os BlendShapes para análise do olhar
        let blendShapes = faceAnchor.blendShapes
        
        // Obtém os valores de BlendShape relacionados ao olhar
        // Valores importantes:
        // - eyeBlinkLeft/Right: 0 = olho aberto, 1 = olho fechado
        // - eyeLookInLeft/Right: Pupila olhando para dentro (nariz)
        // - eyeLookOutLeft/Right: Pupila olhando para fora
        // - eyeLookUpLeft/Right: Pupila olhando para cima
        // - eyeLookDownLeft/Right: Pupila olhando para baixo
        
        // Certifica-se de que os olhos estão abertos
        let leftEyeBlink = blendShapes[.eyeBlinkLeft]?.floatValue ?? 0.0
        let rightEyeBlink = blendShapes[.eyeBlinkRight]?.floatValue ?? 0.0
        
        if leftEyeBlink > 0.2 || rightEyeBlink > 0.2 {
            print("Olhos fechados ou piscando: L=\(leftEyeBlink), R=\(rightEyeBlink)")
            return false
        }
        
        // Verifica desvio horizontal do olhar
        let leftEyeLookIn = blendShapes[.eyeLookInLeft]?.floatValue ?? 0.0
        let rightEyeLookIn = blendShapes[.eyeLookInRight]?.floatValue ?? 0.0
        let leftEyeLookOut = blendShapes[.eyeLookOutLeft]?.floatValue ?? 0.0
        let rightEyeLookOut = blendShapes[.eyeLookOutRight]?.floatValue ?? 0.0
        
        // Verifica desvio vertical do olhar
        let leftEyeLookUp = blendShapes[.eyeLookUpLeft]?.floatValue ?? 0.0
        let rightEyeLookUp = blendShapes[.eyeLookUpRight]?.floatValue ?? 0.0
        let leftEyeLookDown = blendShapes[.eyeLookDownLeft]?.floatValue ?? 0.0
        let rightEyeLookDown = blendShapes[.eyeLookDownRight]?.floatValue ?? 0.0
        
        // Cálculo do alinhamento absoluto do olhar
        // Para um olhar perfeitamente alinhado com a câmera:
        // - Todos os valores devem ser muito baixos (próximos a zero)
        
        // Sem margem de erro - absolutamente preciso
        // Pequena tolerância apenas para ruído do sensor (menor possível)
        let strictThreshold: Float = 0.001 // Quase sem margem
        
        // Verifica todas as direções do olhar
        let isHorizontalAligned = leftEyeLookIn < strictThreshold && rightEyeLookIn < strictThreshold &&
                                 leftEyeLookOut < strictThreshold && rightEyeLookOut < strictThreshold
        
        let isVerticalAligned = leftEyeLookUp < strictThreshold && rightEyeLookUp < strictThreshold &&
                               leftEyeLookDown < strictThreshold && rightEyeLookDown < strictThreshold
        
        let isLookingAtCamera = isHorizontalAligned && isVerticalAligned
        
        // Armazena os dados do olhar para feedback
        DispatchQueue.main.async {
            self.gazeCorrect = isLookingAtCamera
            
            // Dados detalhados sobre o olhar para feedback preciso
            self.gazeData = [
                "leftIn": leftEyeLookIn,
                "rightIn": rightEyeLookIn,
                "leftOut": leftEyeLookOut,
                "rightOut": rightEyeLookOut,
                "leftUp": leftEyeLookUp,
                "rightUp": rightEyeLookUp,
                "leftDown": leftEyeLookDown,
                "rightDown": rightEyeLookDown
            ]
            
            self.updateAllVerifications()
            
            print("Verificação de olhar (ARKit): H=\(isHorizontalAligned), V=\(isVerticalAligned), Total=\(isLookingAtCamera)")
        }
        
        return isLookingAtCamera
    }
    
    // Implementação para a câmera traseira (LiDAR)
    @available(iOS 13.4, *)
    private func checkGazeWithLiDAR(frame: ARFrame) -> Bool {
        // Verificação do olhar usando dados da câmera traseira e LiDAR
        // Como não há rastreamento facial direto na câmera traseira,
        // usamos Vision para detectar o rosto e estimar a direção do olhar
        
        // Obtém a imagem da câmera
        let pixelBuffer = frame.capturedImage
        
        // Configura a detecção facial com Vision
        let faceDetectionRequest = VNDetectFaceLandmarksRequest()
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        
        var isLookingAtCamera = false
        
        do {
            // Executa a solicitação de detecção facial
            try requestHandler.perform([faceDetectionRequest])
            
            // Verifica se detectou um rosto com landmarks
            if let results = faceDetectionRequest.results, !results.isEmpty,
               let observation = results.first,
               let faceObservation = observation as? VNFaceObservation,
               let landmarks = faceObservation.landmarks {
                
                // Verifica os olhos
                if let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye,
                   let leftPupil = landmarks.leftPupil, let rightPupil = landmarks.rightPupil {
                    
                    // Verifica o alinhamento das pupilas com os centros dos olhos
                    let eyeAlignment = checkEyeAlignment(leftEye: leftEye, rightEye: rightEye,
                                                       leftPupil: leftPupil, rightPupil: rightPupil)
                    
                    // Verifica a rotação da cabeça
                    let headAlignment = checkHeadRotation(faceObservation: faceObservation)
                    
                    // Combina as verificações - olhar precisa estar totalmente alinhado
                    isLookingAtCamera = eyeAlignment && headAlignment
                    
                    // Registra o resultado no manager
                    DispatchQueue.main.async {
                        self.gazeCorrect = isLookingAtCamera
                        
                        // Dados simplificados para feedback
                        // Uma vez que não temos BlendShapes na câmera traseira
                        self.gazeData = [
                            "aligned": isLookingAtCamera ? 1.0 : 0.0
                        ]
                        
                        self.updateAllVerifications()
                        print("Verificação de olhar (LiDAR): \(isLookingAtCamera)")
                    }
                }
            }
        } catch {
            print("ERRO na verificação de olhar com LiDAR: \(error)")
        }
        
        return isLookingAtCamera
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
    
    // Função auxiliar para calcular o ponto médio
    private func averagePoint(from points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        
        return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
    }
    
    // Mantém a função original para compatibilidade com código existente
    func checkGaze(using faceAnchor: ARFaceAnchor) -> Bool {
        return checkGazeWithTrueDepth(faceAnchor: faceAnchor)
    }
}
