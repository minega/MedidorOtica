//
//  FaceDetectionVerification.swift
//  MedidorOticaApp
//
//  Verifica a presenca do rosto usando TrueDepth frontal ou LiDAR traseiro.
//

import Foundation
import ARKit

// MARK: - Deteccao de rosto
extension VerificationManager {
    /// Verifica a presenca de rosto usando o sensor ativo.
    func checkFaceDetection(using frame: ARFrame) -> Bool {
        let sensors = preferredSensors()
        guard !sensors.isEmpty else {
            print("ERRO: sensores de deteccao de rosto indisponiveis")
            NotificationCenter.default.post(
                name: NSNotification.Name("DeviceNotCompatible"),
                object: nil,
                userInfo: ["reason": "Sensores TrueDepth ou LiDAR nao encontrados"]
            )
            return false
        }

        for sensor in sensors {
            switch sensor {
            case .trueDepth:
                if checkFaceDetectionWithTrueDepth(frame: frame) { return true }
            case .liDAR:
                if checkFaceDetectionWithLiDAR(frame: frame) { return true }
            case .none:
                continue
            }
        }

        return false
    }

    // MARK: - TrueDepth
    private func checkFaceDetectionWithTrueDepth(frame: ARFrame) -> Bool {
        guard let faceAnchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first else {
            print("Nenhum rosto detectado com TrueDepth")
            return false
        }

        let tracked = faceAnchor.isTracked
        print(tracked ? "Rosto detectado usando TrueDepth" : "Rosto nao rastreado com TrueDepth")
        return tracked
    }

    // MARK: - LiDAR
    private func checkFaceDetectionWithLiDAR(frame: ARFrame) -> Bool {
        guard CameraManager.shared.rearLiDARMeasurementEngine
            .detectsFace(frame: frame, cgOrientation: currentCGOrientation()) else {
            print("Nenhum rosto detectado com LiDAR")
            return false
        }

        print("Rosto detectado usando LiDAR")
        return true
    }
}
