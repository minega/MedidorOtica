# Verificacoes da Camera Traseira com LiDAR

Este documento e exclusivo do modo traseiro. A camera frontal TrueDepth continua com regras proprias e nao deve herdar nenhum limite daqui.

## Distancia

- A faixa valida traseira e `50-100 cm`.
- A distancia oficial vem da profundidade LiDAR no plano do `PC`, nao da faixa `30-40 cm` da camera frontal.
- As amostras auxiliares de olhos e centro da face sao usadas apenas para robustez contra ruido do mapa de profundidade.

## Centralizacao

- O gate traseiro usa o deslocamento do `PC` em relacao ao centro visual do preview.
- Esse deslocamento e convertido para centimetros usando profundidade do `PC` e intrinsecos do `ARFrame`.
- O objetivo e alinhar com o que o usuario enxerga na tela, evitando erro de orientacao/espelhamento da camera traseira.

## Alinhamento

- A pose traseira vem do `Vision`, portanto usa tolerancia propria.
- O TrueDepth frontal continua usando as tolerancias frontais.
- A captura traseira exige menos frames estaveis para reduzir perda por balanco normal da mao.

## Camera

O modo traseiro deve continuar usando `ARWorldTrackingConfiguration` com `sceneDepth` ou `smoothedSceneDepth`. Esse caminho preserva o alinhamento entre RGB, intrinsecos e profundidade LiDAR, que e essencial para medida.
