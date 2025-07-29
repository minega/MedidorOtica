//
//  FrameLandmarks.swift
//  MedidorOticaApp
//
//  Estrutura simples que armazena linhas detectadas na armação e as pupilas.
//

import CoreGraphics

/// Representa linhas verticais e horizontais que delimitam a armação.
struct FrameLandmarks {
    // MARK: - Propriedades
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

    /// Largura normalizada da armação
    var width: CGFloat { rightLineX - leftLineX }

    /// Altura normalizada da armação
    var height: CGFloat { bottomLineY - topLineY }

    /// Inicializador que recebe valores normalizados das linhas e pupilas.
    init(leftLineX: CGFloat, rightLineX: CGFloat, topLineY: CGFloat, bottomLineY: CGFloat, leftPupil: CGPoint, rightPupil: CGPoint) {
        self.leftLineX = leftLineX
        self.rightLineX = rightLineX
        self.topLineY = topLineY
        self.bottomLineY = bottomLineY
        self.leftPupil = leftPupil
        self.rightPupil = rightPupil
    }

    /// Inicializador de compatibilidade utilizando pontos absolutos.
    /// - Parameters:
    ///   - leftPoint: Lado esquerdo da armação.
    ///   - rightPoint: Lado direito da armação.
    ///   - topPoint: Linha superior da armação.
    ///   - bottomPoint: Linha inferior da armação.
    ///   - leftPupil: Centro da pupila esquerda.
    ///   - rightPupil: Centro da pupila direita.
    init(leftPoint: CGPoint, rightPoint: CGPoint, topPoint: CGPoint, bottomPoint: CGPoint, leftPupil: CGPoint, rightPupil: CGPoint) {
        self.leftLineX = leftPoint.x
        self.rightLineX = rightPoint.x
        self.topLineY = topPoint.y
        self.bottomLineY = bottomPoint.y
        self.leftPupil = leftPupil
        self.rightPupil = rightPupil
    }
}
