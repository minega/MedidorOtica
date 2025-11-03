# Medidor Ótica

Este repositório contém o código-fonte do **Medidor Ótica**, um aplicativo iOS que utiliza ARKit para realizar medições de armações de óculos com o auxílio dos sensores TrueDepth e LiDAR.

## Estrutura

- `MedidorOticaApp/` – Projeto Xcode com o código do aplicativo. Dentro dele há um `README.md` mais detalhado. O gerenciamento da câmera foi organizado em extensões, deixando o arquivo `CameraManager.swift` mais simples.

## Novidades

- Novo fluxo pós-captura com três etapas interativas (pupila, horizontal e vertical) para cada olho.
- Divisão automática da imagem pelo ponto central (nariz) com detecção inicial via Vision.
- Ajuste manual com barras arrastáveis para medir largura, altura, ponte, DNP e altura pupilar.
- Tela final exibe resumo completo, permite compartilhar e salvar/editar medições no histórico.
- Captura automática com contagem regressiva após todas as verificações básicas, com opção de desativar pelo botão "timer".
- Todas as verificações utilizam as revisões mais recentes do Vision.
- Correção da orientação e do recorte ao salvar a foto.
- Instruções na câmera foram condensadas e usam pares de emojis (ator + direção) para guiar os ajustes.

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
- As verificações de rosto, distância (25-50 cm), centralização e alinhamento (±3°) são executadas nessa ordem e cada etapa precisa estar correta para prosseguir.

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
