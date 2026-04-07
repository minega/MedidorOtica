# AGENT Guidelines

## Docs
- Antes de mexer no pipeline de mediÃ§Ã£o, leia `docs/pipeline-precisao.md`.
- Antes de subir uma build para o TestFlight, leia `docs/testflight-release.md`.

## Code Style
- Utilize Swift 5.9 e organize o código com `// MARK:` para seções.
- Documente funções públicas usando comentários `///`.
- Remova código duplicado ou não utilizado sempre que possível.
- Prefira variáveis e funções em `camelCase` e tipos em `PascalCase`.
- Escreva comentários e mensagens em português.
- Inclua no início de cada arquivo um breve comentário descrevendo sua finalidade.
- Adicione comentários explicando a função de cada trecho relevante do código.
- Nas instruções exibidas na câmera utilize pares fixos de emojis: primeiro o ator (📱 ou 🙂) e depois a direção (setas, rotação, etc.).
- Mantenha os textos na interface curtos, garantindo que caibam em telas menores.

## Development
- Antes de abrir a câmera, garanta que o dispositivo possui TrueDepth ou LiDAR.
- Simplifique as verificações e evite imports desnecessários.
- Ao adicionar novas funcionalidades, mantenha o código modular e fácil de ler.
- Utilize extensões para isolar responsabilidades, mantendo classes principais enxutas.
- Verifique se ao abrir a câmera pela tela inicial todas as verificações começam automaticamente.
- Se o rosto já estiver no quadro ao iniciar, o app não deve apresentar erros e deve seguir a sequência normalmente.
- Garanta que todas as verificações funcionem tanto com a câmera frontal (TrueDepth) quanto com a traseira (LiDAR).
- Nunca adicione métricas que permitam capturar fotos com a câmera frontal sem o sensor TrueDepth ativo.
- Bloqueie o uso da câmera em dispositivos que não possuam o sensor necessário.
- Otimize o código ao máximo, identificando claramente cada trecho e removendo qualquer duplicação ou funcionalidade sem uso.
- Utilize sempre as APIs mais recentes, priorizando recursos de iOS 17 ou superior.
- Ao usar `VNDetectFace*`, defina a revisão mais atual para obter melhores resultados.
- A captura automática deve estar habilitada por padrão, mantendo um botão para que o usuário possa desativá-la.
- A captura automática deve disparar imediatamente no primeiro bloco curto de frames perfeitos; não reintroduza countdown visual.

## Pós-captura
- Calcule o Ponto Central (PC) usando a linha média facial na banda óptica como base do eixo X, com ponte/dorso nasal apenas como refinamento quando houver convergência geométrica, e a média da altura das pupilas no eixo Y.
- Posicione as barras nasais e temporais sempre a 9 mm e 60 mm do PC, respectivamente, respeitando o lado do olho ativo.
- Mantenha a nitidez da imagem pós-captura ativando interpolação de alta qualidade em todas as exibições estáticas.
- Sempre mantenha `DNP validada`, `DNP nariz` e `DNP ponte` coerentes; se nariz e ponte divergirem além da tolerância, trate a captura como inconsistente.

## Checks
- Após alterações, execute `swift --version` apenas para validar o ambiente.
