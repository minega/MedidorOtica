# Pipeline da Camera Traseira com LiDAR

Este documento descreve somente o fluxo traseiro com LiDAR. Ele nao substitui o documento da camera frontal e nao muda as invariantes do TrueDepth.

## Objetivo

Criar uma captura traseira parecida com a frontal, usando `ARWorldTrackingConfiguration`, `sceneDepth`/`smoothedSceneDepth`, landmarks do `Vision` e uma malha local de profundidade para calcular escala real.

## Regras do modo traseiro

- Usar apenas dispositivos com LiDAR compativel.
- Manter o rosto entre `35 cm` e `55 cm`, mirando perto de `45 cm` quando possivel.
- Nao exigir `ARFaceAnchor`, pois a camera traseira usa `ARFrame` com profundidade de cena.
- Usar `Vision` para pupilas, linha media facial e pose aproximada.
- Usar a profundidade LiDAR no plano do `PC` para distancia e escala.
- Usar o deslocamento visual do `PC` no preview para centralizacao, pois e a referencia que o usuario enxerga ao ajustar o celular.
- Renderizar a foto final com a mesma orientacao que o `Vision`/LiDAR usou para calcular `PC`, face bounds e escala local.
- Salvar uma geometria ocular 3D estimada por LiDAR para a pos-captura traseira nao cair no estado de geometria indisponivel.
- Manter o recorte da pos-captura baseado no `faceBounds`; o posicionamento das barras deve ser corrigido na escala, nao no recorte.
- Posicionar as barras iniciais traseiras a `9 mm` e `60 mm` do `PC` usando a DNP medida daquele olho como ancora visual quando a leitura for confiavel.
- Estimar pose por landmarks + LiDAR e so liberar captura quando `roll`, `yaw` e `pitch` tiverem sido medidos no frame atual.
- Manter a captura traseira com politica propria de estabilidade, sem alterar os limites da camera frontal.
- Exibir aviso no pos-captura para revisar pupilas, `PC` e `DNP longe` antes de salvar.

## Camera traseira principal

O fluxo traseiro deve permanecer em `ARWorldTrackingConfiguration` com `sceneDepth`/`smoothedSceneDepth`. Esse caminho entrega a imagem RGB e o mapa de profundidade calibrados no mesmo `ARFrame`, o que e mais importante para precisao do que tentar forcar ultra-wide ou tele.

Para este app, a melhor base traseira e a camera principal associada ao LiDAR:

- melhor qualidade e menor ruido que ultra-wide em rosto a `35-55 cm`;
- menor deformacao facial que ultra-wide;
- profundidade alinhada ao frame do ARKit;
- tele nao e uma boa base porque reduz campo util, aumenta tremor aparente e nao e o caminho padrao do `sceneDepth`.

## Arquivos do fluxo traseiro

- `MedidorOticaApp/MedidorOticaApp/Managers/RearLiDARMeasurementEngine.swift`
  Motor que combina landmarks do `Vision`, intrinsecos da camera e mapa de profundidade LiDAR.
- `MedidorOticaApp/MedidorOticaApp/Managers/CameraManager+ControleSessao.swift`
  Inicia a sessao traseira com `ARWorldTrackingConfiguration`.
- `MedidorOticaApp/MedidorOticaApp/Managers/CameraManager+CapturaFoto.swift`
  Renderiza a foto traseira usando a orientacao validada pela analise LiDAR.
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
