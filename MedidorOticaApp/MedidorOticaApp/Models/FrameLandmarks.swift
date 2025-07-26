//
//  FrameLandmarks.swift
//  MedidorOticaApp
//
//  Estrutura simples que armazena linhas detectadas na armação e as pupilas.
//

import CoreGraphics

/// Representa linhas verticais e horizontais que delimitam a armação.
struct FrameLandmarks {
    /// Linha vertical à esquerda (0 a 1) que delimita a lente esquerda
    var leftLineX: CGFloat

    /// Linha vertical à direita (0 a 1) que delimita a lente direita
    var rightLineX: CGFloat

    /// Linha horizontal superior (0 a 1) da armação
    var topLineY: CGFloat

    /// Linha horizontal inferior (0 a 1) da armação
    var bottomLineY: CGFloat

    /// Centro da pupila esquerda, normalizado entre 0 e 1
    var leftPupil: CGPoint

    /// Centro da pupila direita, normalizado entre 0 e 1
    var rightPupil: CGPoint
}
