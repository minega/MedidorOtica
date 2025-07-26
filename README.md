# Medidor Ótica

Este repositório contém o código-fonte do **Medidor Ótica**, um aplicativo iOS que utiliza ARKit para realizar medições de armações de óculos com o auxílio dos sensores TrueDepth e LiDAR.

## Estrutura

- `MedidorOticaApp/` – Projeto Xcode com o código do aplicativo. Dentro dele há um `README.md` mais detalhado. O gerenciamento da câmera foi organizado em extensões, deixando o arquivo `CameraManager.swift` mais simples.

## Novidades

- Rastreamento de olhar unificado usando detecção de pupilas via Vision.
- Todas as verificações utilizam as revisões mais recentes do Vision.
- Código modernizado e otimizado, removendo duplicações.
- Detecção automática dos limites internos da armação e das pupilas na foto.
- Ferramenta de ajuste manual das linhas da armação e das pupilas pós-captura.
- Tabela sobreposta exibindo medidas detalhadas da armação e do usuário.
- Indicador de armação em tempo real exibido independentemente das demais etapas.
- Correção da orientação e do recorte ao salvar a foto.

## Requisitos

- Swift 5.9 ou superior
- Xcode 15 ou superior
- iOS 13 ou superior (recomendado iOS 17+)
- Dispositivo com sensor **TrueDepth** ou **LiDAR**

O aplicativo detecta automaticamente qual sensor está disponível e ajusta as verificações.

## Comportamentos Verificados

- Ao tocar em **Iniciar Medidas**, a câmera é ativada e a sequência de verificações começa automaticamente.
- Caso um rosto já esteja enquadrado no momento da abertura da câmera, o sistema continua a execução normalmente sem apresentar erros.
- As verificações de rosto, distância, centralização, alinhamento e olhar são executadas nessa ordem e cada etapa precisa estar correta para prosseguir.

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
