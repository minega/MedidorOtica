//
//  FrameLandmarks.swift
//  MedidorOticaApp
//
//  Estrutura simples que armazena pontos detectados na arma\u00e7\u00e3o e nas pupilas.
//

import CoreGraphics

struct FrameLandmarks {
    /// Ponto na lateral esquerda da armação, normalizado entre 0 e 1
    var leftPoint: CGPoint

    /// Ponto na lateral direita da armação, normalizado entre 0 e 1
    var rightPoint: CGPoint

    /// Ponto superior da armação, normalizado entre 0 e 1
    var topPoint: CGPoint

    /// Ponto inferior da armação, normalizado entre 0 e 1
    var bottomPoint: CGPoint

    /// Centro da pupila esquerda, normalizado entre 0 e 1
    var leftPupil: CGPoint

    /// Centro da pupila direita, normalizado entre 0 e 1
    var rightPupil: CGPoint
}
