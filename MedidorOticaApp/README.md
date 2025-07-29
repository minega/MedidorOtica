# Medidor Ótica App

Aplicativo profissional para medições de ótica, utilizando recursos avançados de ARKit e visão computacional para captura precisa de imagens e medições de armações de óculos.

## 🚀 Recursos Principais

- **Captura Inteligente**: Sistema avançado de detecção facial e alinhamento
- **Verificações em Tempo Real**: Garante a qualidade das medições com feedback visual
- **Suporte a ARKit**: Utiliza realidade aumentada para medições precisas
- **Gerenciamento Otimizado**: Código robusto para evitar travamentos e vazamentos de memória
- **Interface Intuitiva**: Design focado na experiência do usuário
- **Suporte a Múltiplos Sensores**: TrueDepth (câmera frontal) e LiDAR (câmera traseira)
- **Processamento em Tempo Real**: Análise de imagens e dados de profundidade

## 🆕 Novidades

- Verificações simplificadas focadas apenas em rosto, distância e alinhamento.
- Captura automática com contagem regressiva quando todas as verificações estão verdes, podendo ser desativada pelo botão de timer.
- Requisitos mínimos atualizados para Swift 5.9.

## 📂 Estrutura do Projeto

### Core
| Caminho | Descrição |
|---------|-----------|
| `App/App.swift` | Ponto de entrada do aplicativo |
| `App/SceneDelegate.swift` | Gerenciamento do ciclo de vida da cena |

### Managers
| Caminho | Descrição |
|---------|-----------|
| `Managers/CameraManager.swift` | Controla o acesso e operação da câmera |
| `Managers/HistoryManager.swift` | Gerencia histórico de medições |
| `Managers/VerificationManager.swift` | Coordena as verificações de medição |

### Verifications
| Caminho | Descrição |
|---------|-----------|
| `Verifications/FaceDetectionVerification.swift` | Verificação de detecção de rosto |
| `Verifications/DistanceVerification.swift` | Verificação de distância ideal |
| `Verifications/CenteringVerification.swift` | Verificação de centralização do rosto |
| `Verifications/HeadAlignmentVerification.swift` | Verificação de alinhamento da cabeça |

### Models
| Caminho | Descrição |
|---------|-----------|
| `Models/VerificationModels.swift` | Define `VerificationType` e `Verification` |
| `Models/Measurement.swift` | Estrutura para armazenar dados de medição |

## 🔍 Fluxo de Verificações

O aplicativo executa verificações em sequência para garantir medições precisas:

1. **Detecção de Rosto**
   - Verifica a presença de um rosto no quadro
   - Suporte a TrueDepth (frontal) e LiDAR (traseira)

2. **Distância**
   - Distância ideal: 0.5m (40-60cm de tolerância)
   - Ajustes em tempo real

3. **Centralização**
   - Tolerância de 0.5cm
   - Garante posicionamento correto

4. **Alinhamento da Cabeça**
   - Tolerância de 2.0 graus
   - Verifica inclinação e rotação

## 🛠️ Requisitos Técnicos

- iOS 13.0 ou superior (iOS 17+ recomendado)
- Dispositivo com suporte a ARKit
- Câmera traseira (LiDAR) ou frontal (TrueDepth) recomendado
- Xcode 15+
- Swift 5.9+

## 📱 Compatibilidade

- iPhone 11 ou superior (recomendado)
- iPad Pro 11" ou 12.9" (3ª geração ou superior)
- Suporte a modo retrato e paisagem

## 📊 Tolerâncias de Medição

| Verificação | Tolerância |
|-------------|------------|
| Distância | 40-60cm |
| Centralização | ±0.5cm |
| Alinhamento | ±2.0° |
| Olhar | 0.001 |

## 📝 Licença

Este projeto está sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para mais detalhes.

## 👥 Contribuição

Contribuições são bem-vindas! Por favor, leia nosso guia de contribuição antes de enviar pull requests.

## 🧩 Componentes Principais

### CameraManager
- Gerencia o ciclo de vida da sessão da câmera
- Suporte a câmeras frontal (TrueDepth) e traseira (LiDAR)
- Controle de flash e configurações de exposição
- Tratamento robusto de erros e recuperação de falhas

### VerificationManager
- Coordena todas as verificações de medição
- Gerencia o estado das verificações em tempo real
- Integração com ARKit para análise de frames
- Feedback visual sobre o status das verificações

### HistoryManager
- Armazenamento seguro de medições
- Recuperação e gerenciamento do histórico
- Persistência em disco com tratamento de erros


## ⚙️ Configuração

### Permissões Necessárias
Adicione as seguintes permissões no arquivo `Info.plist`:

| Permissão | Chave | Valor |
|-----------|-------|-------|
| Câmera | `NSCameraUsageDescription` | "Precisamos acessar sua câmera para capturar as medições." |
| Fotos | `NSPhotoLibraryAddUsageDescription` | "Precisamos salvar as imagens capturadas no seu álbum de fotos." |
| Acesso ao Face ID (opcional) | `NSFaceIDUsageDescription` | "Usamos o sensor TrueDepth para medições precisas." |

## 👥 Guia de Contribuição

### Estrutura de Pastas
```
MedidorOticaApp/
├── App/                 # Configuração inicial do app
├── Models/              # Modelos de dados
├── Views/               # Telas e componentes de UI
├── Managers/            # Gerenciadores de funcionalidades
│   ├── CameraManager.swift
│   └── CameraComponents/  # Componentes reutilizáveis da câmera
└── Resources/           # Assets, cores, strings localizadas
```

### Diretrizes de Código
- Use `PascalCase` para nomes de tipos e protocolos
- Use `camelCase` para variáveis e funções
- Documente funções públicas com comentários `///`
- Mantenha as views o mais simples possível
- Extraia lógica complexa para os managers apropriados

### Adicionando Novas Verificações
1. Crie um novo arquivo em `Verifications/`
2. Implemente a lógica de verificação
3. Adicione um novo caso ao enum `VerificationType`
4. Atualize o `VerificationManager` para incluir a nova verificação
5. Atualize a UI para mostrar o feedback da nova verificação

## 📱 Como Usar

### Capturando uma Medição
1. Toque em "Tirar Medidas" na tela inicial
2. Siga as instruções na tela para posicionar o rosto
3. Aguarde as verificações de qualidade:
   - ✅ Rosto detectado
   - ✅ Distância correta
   - ✅ Alinhamento adequado
   - ✅ Boa iluminação
4. Toque em "Capturar" quando todas as verificações estiverem verdes
5. Revise a prévia e salve a medição

### Dicas para Melhor Captura
- Mantenha o dispositivo estável
- Certifique-se de ter boa iluminação
- Mantenha o rosto dentro do guia na tela
- Siga as instruções de posicionamento

## 🛠️ Solução de Problemas

### Câmera não inicia
- Verifique as permissões do aplicativo
- Feche outros aplicativos que estejam usando a câmera
- Reinicie o aplicativo

### Rastreamento AR instável
- Melhore a iluminação do ambiente
- Evite superfícies muito reflexivas ou sem textura
- Mantenha o dispositivo estável durante a captura

## 📈 Versão
*Última atualização: 01/07/2025*
*Versão: 2.0.0*
