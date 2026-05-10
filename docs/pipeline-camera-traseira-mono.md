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
- A tela do Mono nao exibe distancia em cm: a etapa 2 valida se o rosto esta grande e ainda cabendo no oval.
- O encaixe pratico do Mono exige rosto com altura projetada entre `30%` e `54%` do frame e largura entre `20%` e `50%`.
- A centralizacao do Mono continua bloqueando por tolerancia normalizada do PC, mas a orientacao exibida ao usuario converte esse erro para centimetros estimados apenas como guia de movimento.
- O alinhamento `roll/yaw/pitch` nao usa fallback zerado: cada eixo precisa de Vision ou geometria facial confiavel, e conflitos grandes usam a leitura mais conservadora.
- A tolerancia de pose do Mono e mais rigida que a versao inicial: `roll +/-2,0°`, `yaw +/-2,2°` e `pitch +/-2,3°`.
- O `pitch` Mono nao deve travar por vies pequeno do retangulo facial; somente quando nariz/queixo estao proporcionais esse vies 2D e tratado como neutro.
- Nenhum ajuste pode neutralizar ou pular `roll/yaw/pitch`: se o Vision ou a geometria indicarem erro real, a captura continua bloqueada.
- A foto salva `scaleSource = .manualBridge`, obrigando a ponte real antes do resumo final.
- A escala plana nasce de `ponte real / distancia normalizada entre as barras nasais`.
- A referencia vertical e derivada da horizontal pela proporcao real da imagem para reduzir erro de distorcao lateral.

## Limitacoes

- Sem LiDAR, Depth ou TrueDepth nao existe escala absoluta no frame da camera.
- A ponte real informada pelo usuario e a unica ancora absoluta do modo Mono.
- Sem profundidade real, `yaw` e `pitch` usam Vision como sinal principal e geometria 2D como confirmacao/bloqueio conservador.
- A precisao depende de captura centralizada, pose alinhada, rosto grande no oval, camera principal e barras nasais bem posicionadas.

## Arquivos principais

- `MedidorOticaApp/MedidorOticaApp/Managers/RearMonoBridgeMeasurementEngine.swift`
  Detecta rosto, PC visual, enquadramento e pose usando Vision.
- `MedidorOticaApp/MedidorOticaApp/Managers/RearMonoBridgeDistanceEstimator.swift`
  Mantem a distancia visual apenas para estimar deslocamentos de centralizacao, sem bloquear a etapa 2.
- `MedidorOticaApp/MedidorOticaApp/Managers/RearMonoBridgePoseEstimator.swift`
  Valida `roll`, `yaw` e `pitch` do modo Mono com landmarks faciais e bloqueio conservador.
- `MedidorOticaApp/MedidorOticaApp/Managers/RearMonoBridgeCaptureCoordinator.swift`
  Entrega frames da camera principal traseira sem ativar LiDAR ou depth.
- `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureManualBridgeScale.swift`
  Converte a ponte real e as barras nasais em escala de medicao.
- `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureViewModel.swift`
  Exige a ponte real antes de gerar metricas no modo Mono.
