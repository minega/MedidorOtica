# AGENT Guidelines

## Code Style
- Utilize Swift 5 e organize o código com `// MARK:` para seções.
- Documente funções públicas usando comentários `///`.
- Remova código duplicado ou não utilizado sempre que possível.
- Prefira variáveis e funções em `camelCase` e tipos em `PascalCase`.
- Escreva comentários e mensagens em português.
- Inclua no início de cada arquivo um breve comentário descrevendo sua finalidade.

## Development
- Antes de abrir a câmera, garanta que o dispositivo possui TrueDepth ou LiDAR.
- Simplifique as verificações e evite imports desnecessários.
- Ao adicionar novas funcionalidades, mantenha o código modular e fácil de ler.
- Utilize extensões para isolar responsabilidades, mantendo classes principais enxutas.
- Verifique se ao abrir a câmera pela tela inicial todas as verificações começam automaticamente.
- Se o rosto já estiver no quadro ao iniciar, o app não deve apresentar erros e deve seguir a sequência normalmente.

## Checks
- Após alterações, execute `swift --version` apenas para validar o ambiente.
