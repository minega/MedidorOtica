//
//  CenteringVerification.swift
//  MedidorOticaApp
//
//  Verificação de Centralização do Rosto
//
//  Objetivo:
//  - Garantir que o rosto esteja perfeitamente centralizado na câmera
//  - Posicionar o dispositivo no meio do nariz, na altura das pupilas
//  - Fornecer feedback visual sobre o posicionamento
//
//  Critérios de Aceitação:
//  1. Centralização horizontal (eixo X) com margem de ±0,5cm
//  2. Centralização vertical (eixo Y) com margem de ±0,5cm
//  3. Alinhamento do nariz com o centro da câmera
//
//  Técnicas Utilizadas:
//  - ARKit Face Tracking para detecção precisa de pontos faciais
//  - Cálculos 3D para determinar o posicionamento relativo
//  - Tolerância ajustável para diferentes cenários de uso
//
//  Notas de Desempenho:
//  - Processamento otimizado para execução em tempo real
//  - Uso eficiente de memória com reutilização de estruturas
//  - Cálculos otimizados para evitar sobrecarga na CPU/GPU

import ARKit
import Vision
import simd

// MARK: - Extensões

extension Notification.Name {
    /// Notificação enviada quando o status de centralização do rosto é atualizado
    static let faceCenteringUpdated = Notification.Name("faceCenteringUpdated")
}

// MARK: - Extensão para verificação de centralização
extension VerificationManager {
    
    // MARK: - Constantes
    
    private enum CenteringConstants {
        // Tolerância de 0,5 cm convertida para metros
        static let tolerance: Float = 0.005

        // Índice do vértice correspondente à ponta do nariz
        struct FaceIndices {
            static let noseTip = 9
        }
    }

    /// Medidas calculadas para orientar o ajuste da câmera em relação ao PC
    private struct FaceCenteringMetrics {
        let horizontal: Float
        let vertical: Float
        let noseAlignment: Float
    }
    
    // MARK: - Verificação de Centralização
    
    /// Verifica se o rosto está corretamente centralizado na câmera
    /// - Parameters:
    ///   - frame: O frame AR atual (não utilizado, mantido para compatibilidade)
    ///   - faceAnchor: O anchor do rosto detectado pelo ARKit
    /// - Returns: Booleano indicando se o rosto está perfeitamente centralizado
    /// Confere se o rosto está centralizado
    func checkFaceCentering(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> Bool {
        let sensors = preferredSensors(requireFaceAnchor: true, faceAnchorAvailable: faceAnchor != nil)

        guard !sensors.isEmpty else { return false }

        for sensor in sensors {
            switch sensor {
            case .trueDepth:
                guard let anchor = faceAnchor else { continue }
                return checkCenteringWithTrueDepth(faceAnchor: anchor, frame: frame)
            case .liDAR:
                return checkCenteringWithLiDAR(frame: frame)
            case .none:
                continue
            }
        }

        return false
    }

    private func checkCenteringWithTrueDepth(faceAnchor: ARFaceAnchor, frame: ARFrame) -> Bool {
        // Obtém a geometria 3D do rosto
        let vertices = faceAnchor.geometry.vertices

        // Valida se temos vértices suficientes para análise
        guard vertices.count > CenteringConstants.FaceIndices.noseTip else {
            print("❌ Geometria facial incompleta para análise de centralização")
            return false
        }

        // Converte pontos faciais para o sistema de coordenadas da câmera
        let worldToCamera = simd_inverse(frame.camera.transform)
        let leftEyeWorld = simd_mul(faceAnchor.transform, faceAnchor.leftEyeTransform)
        let rightEyeWorld = simd_mul(faceAnchor.transform, faceAnchor.rightEyeTransform)
        let noseWorld = simd_mul(faceAnchor.transform,
                                 simd_float4(vertices[CenteringConstants.FaceIndices.noseTip], 1))
        let leftEyeCam = simd_mul(worldToCamera, leftEyeWorld)
        let rightEyeCam = simd_mul(worldToCamera, rightEyeWorld)
        let noseCam = simd_mul(worldToCamera, noseWorld)

        // Calcula o ponto central (PC) usando a altura média das pupilas e o eixo X do nariz
        let averageEyeHeight = (leftEyeCam.columns.3.y + rightEyeCam.columns.3.y) / 2
        let horizontalOffset = noseCam.x
        let verticalOffset = averageEyeHeight

        // Consolida todas as medidas para avaliar e exibir na interface
        let metrics = FaceCenteringMetrics(
            horizontal: horizontalOffset,
            vertical: verticalOffset,
            noseAlignment: noseCam.x
        )

        return evaluateCentering(using: metrics)
    }

    private func checkCenteringWithLiDAR(frame: ARFrame) -> Bool {
        guard let depthMap = frame.sceneDepth?.depthMap ?? frame.smoothedSceneDepth?.depthMap else {
            print("❌ Dados de profundidade LiDAR não disponíveis")
            return false
        }

        let request = makeLandmarksRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: frame.capturedImage,
            orientation: currentCGOrientation(),
            options: [:]
        )
        do {
            try handler.perform([request])
            guard let face = request.results?.first as? VNFaceObservation,
                  let landmarks = face.landmarks else { return false }

            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            let nosePointNorm = landmarks.nose?.normalizedPoints.first ?? CGPoint(x: face.boundingBox.midX, y: face.boundingBox.midY)
            let leftEyeCenter = averagePoint(from: landmarks.leftEye?.normalizedPoints ?? [])
            let rightEyeCenter = averagePoint(from: landmarks.rightEye?.normalizedPoints ?? [])
            let eyeCenterY = (leftEyeCenter.y + rightEyeCenter.y) / 2

            let px = nosePointNorm.x * CGFloat(width)
            let py = (1 - nosePointNorm.y) * CGFloat(height)
            guard let depth = depthValue(from: depthMap, at: CGPoint(x: px, y: py)) else { return false }

            let leftEyeDepthPoint = CGPoint(x: (leftEyeCenter.x) * CGFloat(width),
                                            y: (1 - leftEyeCenter.y) * CGFloat(height))
            let rightEyeDepthPoint = CGPoint(x: (rightEyeCenter.x) * CGFloat(width),
                                             y: (1 - rightEyeCenter.y) * CGFloat(height))
            guard let leftEyeDepth = depthValue(from: depthMap, at: leftEyeDepthPoint),
                  let rightEyeDepth = depthValue(from: depthMap, at: rightEyeDepthPoint) else {
                return false
            }

            // Profundidade média dos olhos para estimar a altura do PC em metros
            let averageEyeDepth = (leftEyeDepth + rightEyeDepth) / 2
            let horizontalOffset = Float(nosePointNorm.x - 0.5) * depth
            let verticalOffset = Float(0.5 - eyeCenterY) * averageEyeDepth

            let metrics = FaceCenteringMetrics(
                horizontal: horizontalOffset,
                vertical: verticalOffset,
                noseAlignment: horizontalOffset
            )

            return evaluateCentering(using: metrics)
        } catch {
            print("Erro ao verificar centralização com Vision: \(error)")
            return false
        }
    }

    // MARK: - Avaliação de métricas

    /// Avalia se o rosto está centralizado com base nas métricas calculadas
    private func evaluateCentering(using metrics: FaceCenteringMetrics) -> Bool {
        // Verifica se os desvios estão dentro da tolerância permitida
        let isHorizontallyAligned = abs(metrics.horizontal) < CenteringConstants.tolerance
        let isVerticallyAligned = abs(metrics.vertical) < CenteringConstants.tolerance
        let isNoseAligned = abs(metrics.noseAlignment) < CenteringConstants.tolerance

        // Resultado global
        let isCentered = isHorizontallyAligned && isVerticallyAligned && isNoseAligned

        // Atualiza a interface com os valores reais, sem compensações fixas
        updateCenteringUI(
            horizontalOffset: metrics.horizontal,
            verticalOffset: metrics.vertical,
            noseOffset: metrics.noseAlignment,
            isCentered: isCentered
        )

        return isCentered
    }
    
    // MARK: - Atualização da Interface
    
    /// Atualiza a interface do usuário com os resultados da verificação de centralização
    private func updateCenteringUI(horizontalOffset: Float, verticalOffset: Float, 
                                 noseOffset: Float, isCentered: Bool) {
        // Converte as medidas para centímetros para exibição
        let horizontalCm = horizontalOffset * 100
        let verticalCm = verticalOffset * 100
        let noseCm = noseOffset * 100
        
        // Log detalhado para debug
        print("""
        📏 Centralização (cm):
           - Horizontal: \(String(format: "%+.2f", horizontalCm)) cm
           - Vertical:   \(String(format: "%+.2f", verticalCm)) cm
           - Nariz:      \(String(format: "%+.2f", noseCm)) cm
           - Alinhado:   \(isCentered ? "✅" : "❌")
        """)
        
        // Atualiza a interface na thread principal
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Armazena os desvios para feedback visual
            self.facePosition = [
                "x": horizontalCm,
                "y": verticalCm,
                "z": noseCm
            ]
            
            // Notifica a interface sobre a atualização
            self.notifyCenteringUpdate()
        }
    }
    
    /// Notifica a interface sobre a atualização do status de centralização
    private func notifyCenteringUpdate() {
        NotificationCenter.default.post(
            name: .faceCenteringUpdated,
            object: nil,
            userInfo: [
                "isCentered": faceAligned,
                "offsets": facePosition,
                "timestamp": Date().timeIntervalSince1970
            ]
        )
    }
}
