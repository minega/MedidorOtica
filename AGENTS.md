# AGENT Guidelines

## Code Style
- Utilize Swift 5.9 e organize o código com `// MARK:` para seções.
- Documente funções públicas usando comentários `///`.
- Remova código duplicado ou não utilizado sempre que possível.
- Prefira variáveis e funções em `camelCase` e tipos em `PascalCase`.
- Escreva comentários e mensagens em português.
- Inclua no início de cada arquivo um breve comentário descrevendo sua finalidade.
- Adicione comentários explicando a função de cada trecho relevante do código.

## Development
- Antes de abrir a câmera, garanta que o dispositivo possui TrueDepth ou LiDAR.
- Simplifique as verificações e evite imports desnecessários.
- Ao adicionar novas funcionalidades, mantenha o código modular e fácil de ler.
- Utilize extensões para isolar responsabilidades, mantendo classes principais enxutas.
- Verifique se ao abrir a câmera pela tela inicial todas as verificações começam automaticamente.
- Se o rosto já estiver no quadro ao iniciar, o app não deve apresentar erros e deve seguir a sequência normalmente.
- Garanta que todas as verificações funcionem tanto com a câmera frontal (TrueDepth) quanto com a traseira (LiDAR).
- Bloqueie o uso da câmera em dispositivos que não possuam o sensor necessário.
- Otimize o código ao máximo, identificando claramente cada trecho e removendo qualquer duplicação ou funcionalidade sem uso.
- Utilize sempre as APIs mais recentes, priorizando recursos de iOS 17 ou superior.
- Para rastreamento de olhar, prefira `VNGazeTrackingRequest` quando disponível.
- Ao usar `VNDetectFace*`, defina a revisão mais atual para obter melhores resultados.

## Checks
- Após alterações, execute `swift --version` apenas para validar o ambiente.
