# Pipeline da Camera Traseira com LiDAR

Este documento descreve somente o fluxo traseiro com LiDAR. Ele nao substitui o documento da camera frontal e nao muda as invariantes do TrueDepth.

## Objetivo

Criar uma captura traseira parecida com a frontal, usando `ARWorldTrackingConfiguration`, `sceneDepth`/`smoothedSceneDepth`, landmarks do `Vision` e uma malha local de profundidade para calcular escala real.

## Regras do modo traseiro

- Usar apenas dispositivos com LiDAR compativel.
- Manter o rosto entre `60 cm` e `100 cm`.
- Nao exigir `ARFaceAnchor`, pois a camera traseira usa `ARFrame` com profundidade de cena.
- Usar `Vision` para pupilas, linha media facial e pose aproximada.
- Usar a profundidade LiDAR no plano do `PC` para distancia, centralizacao e escala.
- Exibir aviso no pos-captura para revisar pupilas, `PC` e `DNP longe` antes de salvar.

## Arquivos do fluxo traseiro

- `MedidorOticaApp/MedidorOticaApp/Managers/RearLiDARMeasurementEngine.swift`
  Motor que combina landmarks do `Vision`, intrinsecos da camera e mapa de profundidade LiDAR.
- `MedidorOticaApp/MedidorOticaApp/Managers/CameraManager+ControleSessao.swift`
  Inicia a sessao traseira com `ARWorldTrackingConfiguration`.
- `MedidorOticaApp/MedidorOticaApp/Verifications/FaceDetectionVerification.swift`
  Detecta rosto no frame traseiro via `Vision`.
- `MedidorOticaApp/MedidorOticaApp/Verifications/DistanceVerification.swift`
  Mede a distancia real do rosto com profundidade LiDAR.
- `MedidorOticaApp/MedidorOticaApp/Verifications/CenteringVerification.swift`
  Usa o ponto 3D do `PC` para alinhar a camera traseira.
- `MedidorOticaApp/MedidorOticaApp/Verifications/HeadAlignmentVerification.swift`
  Usa a pose estimada pelo `Vision` quando o sensor ativo e LiDAR.
- `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureModels.swift`
  Guarda tambem a comparacao opcional por ponte real no resumo final.

## Comparacao por ponte real

No resumo da pos-captura, o usuario pode informar a ponte real da armacao em milimetros. O app preserva o resultado original dos sensores e cria uma segunda leitura proporcional:

1. mede a ponte calculada pelos sensores;
2. calcula o fator `ponte real / ponte medida`;
3. aplica o mesmo fator em largura, altura, DNP perto, DNP longe e altura pupilar;
4. mostra `Sensor` e `Ponte` lado a lado para auditoria.

Entradas fora de `5...35 mm` sao bloqueadas. Diferencas acima de `8%` geram aviso para revisar a marcacao da ponte.
