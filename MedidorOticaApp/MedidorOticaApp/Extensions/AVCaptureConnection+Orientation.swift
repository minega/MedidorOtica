//
//  AVCaptureConnection+Orientation.swift
//  MedidorOticaApp
//
//  Extensão utilitária para configurar a orientação das conexões de vídeo
//  de forma compatível com diferentes versões do iOS.
//

import AVFoundation

extension AVCaptureConnection {
    /// Define a orientação para portrait considerando versões diferentes do iOS.
    func setPortraitOrientation() {
        let angle: CGFloat = 90 // Equivalente à orientação .portrait
        if #available(iOS 17, *) {
            if isVideoRotationAngleSupported(angle) {
                videoRotationAngle = angle
            }
        } else {
            if isVideoOrientationSupported {
                videoOrientation = .portrait
            }
        }
    }
}
