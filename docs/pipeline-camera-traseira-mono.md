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
- A tela exibe distancia em cm como nos modos `LiDAR` e `Depth`, mas no Mono esse valor e estimado pelo tamanho projetado do rosto; ele nao e profundidade real.
- A foto salva `scaleSource = .manualBridge`, obrigando a ponte real antes do resumo final.
- A escala plana nasce de `ponte real / distancia normalizada entre as barras nasais`.
- A referencia vertical e derivada da horizontal pela proporcao real da imagem para reduzir erro de distorcao lateral.

## Limitacoes

- Sem LiDAR, Depth ou TrueDepth nao existe escala absoluta no frame da camera.
- A ponte real informada pelo usuario e a unica ancora absoluta do modo Mono.
- A precisao depende de captura centralizada, pose alinhada, distancia estimada dentro de `35-55 cm`, camera principal e barras nasais bem posicionadas.

## Arquivos principais

- `MedidorOticaApp/MedidorOticaApp/Managers/RearMonoBridgeMeasurementEngine.swift`
  Detecta rosto, PC visual, enquadramento e pose usando Vision.
- `MedidorOticaApp/MedidorOticaApp/Managers/RearMonoBridgeCaptureCoordinator.swift`
  Entrega frames da camera principal traseira sem ativar LiDAR ou depth.
- `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureManualBridgeScale.swift`
  Converte a ponte real e as barras nasais em escala de medicao.
- `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureViewModel.swift`
  Exige a ponte real antes de gerar metricas no modo Mono.
