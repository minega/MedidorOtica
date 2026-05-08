# Pipeline camera traseira Depth

Este documento descreve o fluxo separado para iPhones sem LiDAR. Ele nao substitui nem altera os caminhos existentes de TrueDepth frontal e LiDAR traseiro.

## Objetivo

- Usar a camera traseira com `AVDepthData` sincronizado por `AVCaptureDataOutputSynchronizer`.
- Manter a experiencia pratica de uma foto unica, sem calibracao manual.
- Exigir distancia curta de captura entre 35 cm e 55 cm.
- Bloquear a captura quando rosto, distancia, centralizacao, pose ou frame recente nao estiverem validos.

## Separacao do fluxo

- O motor fica em `RearDepthFallbackMeasurementEngine`.
- A sessao AVFoundation fica em `RearDepthCaptureCoordinator`.
- A camera frontal continua exigindo TrueDepth.
- O modo LiDAR traseiro continua usando ARKit e `RearLiDARMeasurementEngine`.
- A troca LiDAR/Depth e feita pelo botao do sensor no topo da camera traseira.

## Medicao

- O PC e resolvido pela linha mediana facial na altura media das pupilas.
- A profundidade central vem do depth map estimado pela camera dupla.
- A escala local e calculada por uma grade de pontos dentro do rosto, filtrando outliers de escala e profundidade.
- O pos-captura usa a mesma regra de barras a partir do PC, mantendo 9 mm nasal e 60 mm temporal.

## Limitacoes conhecidas

- `AVDepthData` de camera dupla e estimado por disparidade, portanto tende a ter mais ruido que LiDAR.
- A precisao deve ser validada em aparelho real porque simulador nao fornece depth traseiro fisico.
- Se o dispositivo nao entregar `cameraCalibrationData` no depth frame, a captura e bloqueada.
