//
//  FrameLandmarks.swift
//  MedidorOticaApp
//
//  Estrutura simples que armazena pontos detectados na arma\u00e7\u00e3o e nas pupilas.
//

import CoreGraphics

struct FrameLandmarks {
    let leftPoint: CGPoint
    let rightPoint: CGPoint
    let topPoint: CGPoint
    let bottomPoint: CGPoint
    let leftPupil: CGPoint
    let rightPupil: CGPoint
}
