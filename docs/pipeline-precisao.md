# Pipeline de Precisão do Medidor Ótica

Este documento descreve o estado atual do pipeline de captura e pós-captura. Ele existe para que uma conversa nova consiga se orientar rápido sem depender do histórico do chat.

## Objetivo

O app mede armações com prioridade total em precisão. O fluxo correto é:

1. detectar rosto;
2. validar distância real do plano do `PC` ao sensor;
3. centralizar a câmera com o `PC`;
4. alinhar a cabeça nos 3 eixos;
5. capturar a foto;
6. recalcular o `PC` e as medidas no pós-captura com apoio do `TrueDepth`.

## Invariantes que não podem regredir

- A câmera frontal só pode medir com `TrueDepth` ativo.
- A captura frontal deve continuar válida entre `30 cm` e `40 cm`.
- O tamanho do rosto no oval é apenas guia visual; não pode bloquear a captura.
- A captura automática precisa ser instantânea no primeiro bloco curto de frames perfeitos; não pode haver countdown.
- A malha útil do `TrueDepth` deve ser usada inteira, sem downsampling agressivo no cálculo final.
- O `PC.y` deve ficar sempre na média da altura das pupilas; na captura ao vivo, usar landmarks de pupila do `Vision` quando disponíveis e `ARFaceAnchor.leftEyeTransform/rightEyeTransform` apenas como fallback.
- O `PC.x` não pode ser dominado pela ponta do nariz.
- A pós-captura não pode cair para uma escala global simplificada em `mm/pixel`.
- A `DNP longe` não pode usar tabela fixa.
- O frame final da foto não pode reutilizar verificação, calibração ou fallback de outro frame.
- A `DNP validada` precisa convergir entre `DNP nariz` e `DNP ponte`.

## Arquivos críticos

### Captura

- `MedidorOticaApp/MedidorOticaApp/Managers/CameraManager.swift`
  Controla o estado geral da sessão e o gate de captura.
- `MedidorOticaApp/MedidorOticaApp/Managers/CameraManager+CapturaFoto.swift`
  Monta a foto final, salva a calibração final, persiste o `PC` da captura e o snapshot ocular 3D.
- `MedidorOticaApp/MedidorOticaApp/Managers/CaptureReadinessEngine.swift`
  Decide se a captura está pronta no frame atual usando `4` frames válidos, gap máximo `0,16 s` e frame final fresco em `0,12 s`.
- `MedidorOticaApp/MedidorOticaApp/Managers/VerificationManager.swift`
  Coordena rosto, distância, centralização e alinhamento.

### Verificações

- `MedidorOticaApp/MedidorOticaApp/Verifications/DistanceVerification.swift`
  Usa a profundidade real do plano do `PC` para liberar a faixa de `30–40 cm`.
- `MedidorOticaApp/MedidorOticaApp/Verifications/CenteringVerification.swift`
  Garante que a câmera fique alinhada com o `PC`.
- `MedidorOticaApp/MedidorOticaApp/Verifications/HeadAlignmentVerification.swift`
  Valida `pitch`, `yaw` e `roll`.
- `MedidorOticaApp/MedidorOticaApp/Verifications/DepthUtils.swift`
  Concentra helpers geométricos e referências do `PC` na captura.

### Pós-captura

- `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureProcessor.swift`
  Orquestra a análise inicial da foto e monta os candidatos do `PC`.
- `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureCentralPointResolver.swift`
  Resolve o `PC.x` final a partir da linha média facial, pupilas e ponte nasal.
- `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureScale.swift`
  Faz a escala local ponto a ponto usando a malha do `TrueDepth`.
- `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureMeasurementCalculator.swift`
  Calcula as medidas finais de perto no plano do `PC`.
- `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureFarDNPResolver.swift`
  Converte `DNP perto` em `DNP longe` usando geometria ocular real da mesma captura.
- `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureViewModel.swift`
  Monta o resumo apresentado na tela final.

### Modelos

- `MedidorOticaApp/MedidorOticaApp/Models/CaptureEyeGeometrySnapshot.swift`
  Persiste a geometria 3D dos olhos no frame final.
- `MedidorOticaApp/MedidorOticaApp/Models/CapturedPhoto.swift`
  Guarda a foto já com calibração e metadados da captura.
- `MedidorOticaApp/MedidorOticaApp/Models/Measurement.swift`
  Persiste o resultado salvo no histórico.

## Como o `PC` deve ser resolvido

### Eixo Y

- Sempre usar a média da altura das pupilas detectadas na foto pós-captura.
- Não usar nariz ou face bounds para definir `PC.y`.
- Na captura ao vivo, a altura do `PC` deve preferir `rightPupil/leftPupil` do `Vision`; o centro ocular do ARKit pode aparecer abaixo da pupila visível e não deve ser a primeira referência quando o Vision localizar as pupilas.

### Eixo X

- Base principal: linha média facial útil na banda óptica das pupilas.
- Segundo sinal: simetria pupilar da própria foto.
- Terceiro sinal: dorso/ponte do nariz, apenas como refinamento fraco.
- A ponta do nariz não pode ser a referência dominante.
- `DNP nariz` e `DNP ponte` precisam convergir; quando divergirem acima da tolerância, a captura deve ser tratada como inconsistente.

## Como a captura ao vivo deve liberar

- A captura frontal usa `X ±0,14 cm` e `Y ±0,20 cm` como tolerância final do `PC`.
- A pose frontal usa `yaw/roll ±1,2°` e `pitch ±1,3°`.
- Durante a etapa de alinhamento da cabeça, existe uma faixa assistida de centralização (`X ±0,30 cm`, `Y ±0,35 cm`) apenas para a UI não alternar entre centralização e eixos a cada microgiro.
- Essa faixa assistida nunca pode liberar captura: quando `pitch`, `yaw` e `roll` ficam corretos, a centralização volta a exigir o limite final antes da foto.
- A captura automática permanece instantânea, sem countdown, no primeiro bloco curto de frames perfeitos.

## Como a escala deve funcionar

- A escala local usa a malha útil inteira do `TrueDepth`.
- Cada medida deve ser integrada localmente, ponto a ponto.
- Evitar qualquer volta para uma única referência global de `mm/pixel`.

## Como a `DNP perto` deve funcionar

- `DNP perto` é sempre medida no plano do `PC`.
- O valor monocular sai da distância horizontal entre o centro da pupila e o `PC`.
- `OD` e `OE` não precisam ser iguais; assimetria pode ser real.
- O valor oficial final deve nascer da convergência entre `DNP nariz` e `DNP ponte`.

## Como a `DNP longe` deve funcionar

- A captura salva a geometria 3D dos olhos no frame final.
- O cálculo usa a distância real do olho até a câmera.
- O cálculo usa a profundidade aparente da pupila naquele frame.
- O cálculo usa também a diferença angular entre o olhar capturado e o eixo frontal da face.
- O valor final de `longe` precisa abrir em relação ao `perto`, mas sem explosão numérica.
- Se a confiança de fixação for baixa, o valor ainda aparece, mas com observação de confiança.

## O que já causou regressão antes

- Usar o tamanho do rosto no oval como gate duro da distância.
- Resumir demais a malha do `TrueDepth`.
- Deixar a ponta do nariz dominar o `PC.x`.
- Herdar o `PC` da captura cegamente no pós-captura.
- Converter `DNP perto -> DNP longe` com reprojeção agressiva demais.
- Converter `DNP perto -> DNP longe` com delta fraco demais, que colapsa para quase o mesmo valor.

## Testes de regressão mais importantes

- `PostCaptureFarDNPResolverTests`
  Protege a abertura da `DNP longe` sem explosão.
- `PostCaptureCentralPointResolverTests`
  Protege o `PC.x` contra nariz torto e referências incoerentes.
- `CaptureReadinessEngineTests`
  Protege a liberação da captura entre `30–40 cm`.

## Regra prática para futuras mudanças

Se uma alteração tocar em `PC`, escala, `DNP perto` ou `DNP longe`, ela precisa atualizar:

- este documento;
- `README.md`;
- `MedidorOticaApp/README.md`;
- pelo menos um teste de regressão do trecho alterado.
## Modo traseiro LiDAR

O app agora possui um segundo fluxo de captura, separado do TrueDepth frontal, para testar medicoes com a camera traseira e LiDAR sem calibracao manual do usuario.

### Regras do fluxo traseiro

- A frontal continua restrita ao `TrueDepth`; nenhuma mudanca neste modo pode liberar captura frontal sem `ARFaceAnchor`.
- A traseira usa `ARWorldTrackingConfiguration` com `sceneDepth` ou `smoothedSceneDepth`.
- A faixa alvo da traseira e `60-100 cm`; a faixa frontal permanece `30-40 cm`.
- O LiDAR fornece escala/profundidade; landmarks do `Vision` fornecem face, olhos, eixo nasal e pose.
- A escala pos-captura da traseira e local: o motor monta amostras dentro do recorte facial e integra ponto a ponto usando `LocalFaceScaleCalibration`.
- A captura traseira nao exige `ARFaceAnchor`, mas exige rosto detectado, distancia valida, PC centralizado, pose alinhada e frame estavel.
- O `DNP longe` da traseira deve ser revisado no pos-captura porque a camera traseira nao fornece geometria ocular equivalente ao `TrueDepth`.

### Arquivos do fluxo traseiro

- `MedidorOticaApp/MedidorOticaApp/Managers/RearLiDARMeasurementEngine.swift`
  Funde landmarks do `Vision`, intrinsics do ARKit e mapa de profundidade LiDAR.
- `MedidorOticaApp/MedidorOticaApp/Managers/CameraManager+ControleSessao.swift`
  Inicia a sessao traseira com `ARWorldTrackingConfiguration`.
- `MedidorOticaApp/MedidorOticaApp/Managers/CameraManager+CapturaFoto.swift`
  Monta a foto final traseira com calibracao local LiDAR.
- `MedidorOticaApp/MedidorOticaApp/Views/CameraView.swift`
  Permite alternar entre `TrueDepth` e `LiDAR`.
