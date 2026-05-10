# Pipeline camera traseira Mono

Este documento descreve o fluxo separado para iPhones sem LiDAR e sem profundidade traseira por camera dupla. Ele nao substitui os caminhos TrueDepth frontal, LiDAR traseiro ou Depth traseiro.

## Objetivo

- Usar sempre a camera traseira principal (`builtInWideAngleCamera`).
- Manter a experiencia de foto unica, com as mesmas verificacoes de rosto, enquadramento, centralizacao e alinhamento.
- Calcular a escala final somente depois que o usuario informar a ponte real na pos-captura.
- Usar as barras nasais ja ajustadas no fluxo normal para medir a ponte, sem criar marcadores extras.

## Regras

- O modo fica em `RearDepthMode.monoBridge` e aparece no botao superior junto com `LiDAR` e `Depth`.
- A captura usa `RearMonoBridgeMeasurementEngine` e `RearMonoBridgeCaptureCoordinator`.
- O botao superior alterna `LiDAR -> Depth -> Mono`, pulando modos indisponiveis.
- A tela exibe distancia em cm como nos modos `LiDAR` e `Depth`, mas no Mono esse valor e estimado por tamanho facial calibrado, distancia entre olhos e intrinsics quando disponiveis; ele nao e profundidade real.
- A faixa pratica do Mono e `22-38 cm`, porque a camera principal em foto unica precisa do rosto maior no quadro e a escala final vem da ponte real.
- A centralizacao do Mono continua bloqueando por tolerancia normalizada do PC, mas a orientacao exibida ao usuario converte esse erro para centimetros estimados usando distancia, tamanho da imagem e intrinsics/focal de fallback.
- O alinhamento `roll/yaw/pitch` nao usa fallback zerado: cada eixo precisa ter geometria facial confiavel e, quando o Vision tambem mede o eixo, a leitura mais conservadora impede liberar a captura por erro otimista.
- A tolerancia de pose do Mono e mais rigida que a versao inicial: `roll +/-2,2°`, `yaw +/-2,4°` e `pitch +/-2,5°`.
- O `pitch` Mono nao deve travar por vies pequeno do retangulo facial; quando nariz/queixo estao proporcionais ou o Vision indica eixo alinhado, esse vies 2D e tratado como neutro.
- A foto salva `scaleSource = .manualBridge`, obrigando a ponte real antes do resumo final.
- A escala plana nasce de `ponte real / distancia normalizada entre as barras nasais`.
- A referencia vertical e derivada da horizontal pela proporcao real da imagem para reduzir erro de distorcao lateral.

## Limitacoes

- Sem LiDAR, Depth ou TrueDepth nao existe escala absoluta no frame da camera.
- A ponte real informada pelo usuario e a unica ancora absoluta do modo Mono.
- Sem profundidade real, `yaw` e `pitch` sao validacoes geometricas 2D; pequenas assimetrias naturais entram em zona neutra para evitar instrucao impossivel.
- A precisao depende de captura centralizada, pose alinhada, distancia estimada dentro de `22-38 cm`, camera principal e barras nasais bem posicionadas.

## Arquivos principais

- `MedidorOticaApp/MedidorOticaApp/Managers/RearMonoBridgeMeasurementEngine.swift`
  Detecta rosto, PC visual, enquadramento e pose usando Vision.
- `MedidorOticaApp/MedidorOticaApp/Managers/RearMonoBridgeDistanceEstimator.swift`
  Corrige a distancia estimada do Mono por proporcao facial, olhos e intrinsics da camera.
- `MedidorOticaApp/MedidorOticaApp/Managers/RearMonoBridgePoseEstimator.swift`
  Valida `roll`, `yaw` e `pitch` do modo Mono com landmarks faciais e bloqueio conservador.
- `MedidorOticaApp/MedidorOticaApp/Managers/RearMonoBridgeCaptureCoordinator.swift`
  Entrega frames da camera principal traseira sem ativar LiDAR ou depth.
- `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureManualBridgeScale.swift`
  Converte a ponte real e as barras nasais em escala de medicao.
- `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureViewModel.swift`
  Exige a ponte real antes de gerar metricas no modo Mono.
