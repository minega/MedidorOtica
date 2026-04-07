# Medidor Ótica

Este repositório contém o código-fonte do **Medidor Ótica**, um aplicativo iOS que utiliza ARKit para realizar medições de armações de óculos com o auxílio dos sensores TrueDepth e LiDAR.

## Estrutura

- `MedidorOticaApp/` – Projeto Xcode com o código do aplicativo. Dentro dele há um `README.md` mais detalhado. O gerenciamento da câmera foi organizado em extensões, deixando o arquivo `CameraManager.swift` mais simples.
- `docs/pipeline-precisao.md` – Mapa técnico do pipeline de captura, `PC`, escala local do `TrueDepth` e `DNP perto/longe`.
- `docs/testflight-release.md` – Passo a passo real para subir uma build ao TestFlight e confirmar o estado na Apple.

## Novidades

- Novo fluxo pós-captura com três etapas interativas (pupila, horizontal e vertical) para cada olho.
- Divisão automática da imagem pelo ponto central (PC) com análise da foto e suporte geométrico do TrueDepth.
- Ajuste manual com barras arrastáveis para medir largura, altura, ponte, DNP e altura pupilar.
- Resultado final com `DNP perto` e `DNP longe` a partir da mesma captura, sem tabela fixa.
- Tela final exibe resumo completo, permite compartilhar e salvar/editar medições no histórico.
- Captura automática instantânea no primeiro bloco curto de frames perfeitos, sem contagem regressiva, com opção de desativar pelo botão "timer".
- A calibração local usa a malha útil completa do TrueDepth, ponto a ponto, para reduzir deformações de perspectiva.
- Todas as verificações utilizam as revisões mais recentes do Vision.
- Correção da orientação e do recorte ao salvar a foto.
- Instruções na câmera usam pares fixos de emojis (ator + direção) para guiar os ajustes.

## Requisitos

- Swift 5.9 ou superior
- Xcode 15 ou superior
- iOS 13 ou superior (recomendado iOS 17+)
- Dispositivo com sensor **TrueDepth** ou **LiDAR**

O aplicativo detecta automaticamente qual sensor está disponível e ajusta as verificações.

> **Regra obrigatória:** Nunca desenvolva métricas ou fluxos que permitam capturar fotos com a câmera frontal sem o sensor **TrueDepth** ativo; a precisão absoluta depende exclusivamente dele.

## Comportamentos Verificados

- Ao tocar em **Iniciar Medidas**, a câmera é ativada e a sequência de verificações começa automaticamente.
- Caso um rosto já esteja enquadrado no momento da abertura da câmera, o sistema continua a execução normalmente sem apresentar erros.
- As verificações de rosto, distância (`30-40 cm`), centralização (`X ±0,10 cm`, `Y ±0,15 cm`) e alinhamento (`yaw/roll ±0,8°`, `pitch ±1,0°`) são executadas nessa ordem e cada etapa precisa estar correta para prosseguir.
- A DNP de longe usa a mesma captura com geometria ocular 3D do `TrueDepth`; ela nunca depende de tabela populacional fixa.

## Invariantes de Precisao

- Nunca liberar medições frontais sem `TrueDepth` ativo.
- Nunca resumir a malha local útil do `TrueDepth` em uma grade grosseira quando a foto final estiver sendo calibrada.
- O `PC` do pós-captura deve usar `Y` na média das pupilas e `X` corrigido pela linha média facial com suporte do `TrueDepth`.
- A captura frontal deve continuar válida entre `30 cm` e `40 cm` usando a profundidade real do plano do `PC`, nunca o tamanho do rosto no oval.
- A `DNP longe` deve ser calculada pela mesma captura, usando vergência ocular e geometria 3D real, sem tabela fixa.
- A `DNP validada` deve nascer da convergência entre `DNP nariz` e `DNP ponte`; divergência acima da tolerância indica captura inconsistente.
- As variações de `DNP` exibidas no resumo servem para auditoria do eixo `X`; diferenças grandes entre elas indicam que o `PC` precisa ser revisto.
- Mudanças nesses pontos devem vir acompanhadas de atualização da documentação e de testes de regressão.

## Mapa Rápido da Precisão

Para se localizar rápido no projeto, siga esta ordem:

1. `docs/pipeline-precisao.md`
2. `docs/testflight-release.md`
3. `MedidorOticaApp/README.md`
4. arquivos críticos:
   - `MedidorOticaApp/MedidorOticaApp/Managers/CameraManager+CapturaFoto.swift`
   - `MedidorOticaApp/MedidorOticaApp/Verifications/DepthUtils.swift`
   - `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureProcessor.swift`
   - `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureCentralPointResolver.swift`
   - `MedidorOticaApp/MedidorOticaApp/PostCapture/PostCaptureFarDNPResolver.swift`

## Como contribuir

1. Leia as diretrizes em `AGENTS.md`.
2. Crie sua branch ou fork e faça suas alterações seguindo as regras de estilo.
3. Envie um pull request.

### Documentação do Código
- Sempre descreva a função de cada trecho relevante com comentários.
- Remova trechos duplicados ou que não estejam em uso.

### Testes Rápidos
Execute `swift --version` para confirmar a versão do compilador antes de enviar suas alterações.

Para detalhes de uso e arquitetura acesse `MedidorOticaApp/README.md`.
