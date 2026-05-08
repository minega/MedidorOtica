# Verificacoes da Camera Traseira com LiDAR

Este documento e exclusivo do modo traseiro. A camera frontal TrueDepth continua com regras proprias e nao deve herdar nenhum limite daqui.

## Distancia

- A faixa valida traseira e `35-55 cm`.
- O alvo pratico de enquadramento e ficar perto de `45 cm`, evitando o rosto pequeno no preview.
- A distancia oficial vem da profundidade LiDAR no plano do `PC`, nao da faixa `30-40 cm` da camera frontal.
- As amostras auxiliares de olhos e centro da face sao usadas apenas para robustez contra ruido do mapa de profundidade.

## Centralizacao

- O gate traseiro usa o deslocamento do `PC` em relacao ao centro visual do preview.
- Esse deslocamento e convertido para centimetros usando profundidade do `PC` e intrinsecos do `ARFrame`.
- O objetivo e alinhar com o que o usuario enxerga na tela, evitando erro de orientacao/espelhamento da camera traseira.
- Quando `roll`, `yaw` ou `pitch` ainda estao fora, a UI pode usar uma faixa assistida de centralizacao baseada em um ponto neutro entre `PC`, olhos e centro facial. Isso reduz o loop de centralizar, girar e perder a centralizacao.
- Essa faixa assistida nunca libera a foto. Quando a cabeca entra nos tres eixos, a centralizacao volta ao limite final do `PC` antes da captura.

## Alinhamento

- A pose traseira usa landmarks, profundidade LiDAR e, quando util, os angulos nativos do `Vision`.
- A pose traseira e medida antes da centralizacao para decidir se a UI deve entrar na faixa assistida de alinhamento.
- A captura traseira fica bloqueada quando `roll`, `yaw` ou `pitch` nao foram medidos no frame atual.
- O `roll` usa a linha dos olhos; o `yaw` prefere a diferenca de profundidade entre os olhos; o `pitch` usa a normal 3D aproximada da face.
- O TrueDepth frontal continua usando as tolerancias frontais.
- A captura traseira exige menos frames estaveis para reduzir perda por balanco normal da mao.
- A foto final deve preservar a orientacao validada pelo `Vision`; se o motor usar uma orientacao de fallback, renderizacao, `PC`, escala e pos-captura usam essa mesma orientacao.

## Pos-captura

- O modo traseiro salva centros 3D estimados dos olhos usando landmarks do `Vision` e profundidade LiDAR.
- Essa geometria nao substitui o rastreamento real do TrueDepth, mas evita que a DNP longe e a revisao de alinhamento entrem no fallback de geometria indisponivel.
- Quando o Vision nao entrega pupilas, a geometria usa pontos oculares inferidos dentro do recorte facial para manter a revisao possivel.
- O recorte exibido na pos-captura traseira volta a seguir o `faceBounds`; as barras iniciais usam a DNP medida do proprio olho para respeitar a proporcao visual de `9 mm` e `60 mm` a partir do `PC`.

## Camera

O modo traseiro deve continuar usando `ARWorldTrackingConfiguration` com `sceneDepth` ou `smoothedSceneDepth`. Esse caminho preserva o alinhamento entre RGB, intrinsecos e profundidade LiDAR, que e essencial para medida.
