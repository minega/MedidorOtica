# Medidor Ótica

Este repositório contém o código-fonte do **Medidor Ótica**, um aplicativo iOS que utiliza ARKit para realizar medições de armações de óculos com o auxílio dos sensores TrueDepth e LiDAR.

## Estrutura

- `MedidorOticaApp/` – Projeto Xcode com o código do aplicativo. Dentro dele há um `README.md` mais detalhado. O gerenciamento da câmera foi organizado em extensões, deixando o arquivo `CameraManager.swift` mais simples.

## Requisitos

- Swift 5.5 ou superior
- Xcode 13 ou superior
- Dispositivo com sensor **TrueDepth** ou **LiDAR**

O aplicativo detecta automaticamente qual sensor está disponível e ajusta as verificações.

## Como contribuir

1. Leia as diretrizes em `AGENTS.md`.
2. Crie sua branch ou fork e faça suas alterações seguindo as regras de estilo.
3. Envie um pull request.

### Testes Rápidos
Execute `swift --version` para confirmar a versão do compilador antes de enviar suas alterações.

Para detalhes de uso e arquitetura acesse `MedidorOticaApp/README.md`.
