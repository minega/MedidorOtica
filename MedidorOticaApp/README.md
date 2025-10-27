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
- Fluxo pós-captura remodelado com marcação automática da pupila, barras ajustáveis e resumo completo das medições (horizontal maior, vertical maior, ponte, DNP e altura pupilar).

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
   - Distância ideal: 25-50 cm do sensor
   - Ajustes em tempo real

3. **Centralização**
   - Tolerância de 0.5cm
   - Garante posicionamento correto

4. **Alinhamento da Cabeça**
   - Tolerância de ±3.0°
   - Verifica inclinação e rotação com referência à câmera

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
| Distância | 25-50cm |
| Centralização | ±0.5cm |
| Alinhamento | ±3.0° |
| Olhar | 0.001 |

## 📏 Fluxo Pós-Captura

Após a captura, o aplicativo abre a etapa de pós-processamento com a imagem recortada para focar o rosto:

1. **Divisão pelo ponto central (PC)**
   - O rosto é separado em dois lados usando o nariz como referência.
   - Sempre iniciamos pelo olho direito da pessoa fotografada.

2. **Etapa 1 – Localizar Pupila**
   - A Vision detecta a pupila automaticamente e posiciona um marcador circular de 2 mm (virtual) no centro.
   - O usuário pode arrastar o marcador para ajustes finos.

3. **Etapa 2 – Medir Horizontal**
   - Duas barras verticais de 50 mm são mostradas.
   - A primeira barra surge a 9 mm do PC (lado nasal) e a segunda 50 mm após a primeira (lado temporal).
   - Ambas podem ser arrastadas para coincidir com os limites da lente.

4. **Etapa 3 – Medir Vertical**
   - Duas barras horizontais de 60 mm auxiliam na marcação das bordas superior e inferior da lente.
   - A barra inferior inicia 15 mm abaixo da pupila e a superior 20 mm acima, permitindo ajustes por arraste.

5. **Olho Esquerdo**
   - As medidas do olho direito são espelhadas automaticamente para o esquerdo.
   - O usuário revisa e ajusta se necessário (apenas por garantia).

6. **Resumo Final**
   - A tela final apresenta a foto com as marcações e todas as medidas calculadas: horizontal maior (OD/OE), vertical maior (OD/OE), ponte, DNP (OD/OE) e altura pupilar (OD/OE), além da DP total.
   - É possível compartilhar a composição ou salvar no histórico informando o nome do cliente.
   - Cada item salvo pode ser reaberto posteriormente para editar novamente as etapas.

### Controles Disponíveis

- **Refazer:** retorna para a câmera para capturar outra foto.
- **Voltar/Próximo:** navegam entre as etapas do pós-captura.
- **Salvar/Atualizar:** grava ou atualiza a medição no histórico mantendo o mesmo ID.
- **Compartilhar:** gera imagem com as barras sobrepostas e resumo textual das medidas.

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
