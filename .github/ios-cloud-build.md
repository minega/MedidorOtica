# Build iOS sem Mac local

Este projeto é nativo em SwiftUI/Xcode. Por isso, `EAS Build` não é o caminho compatível aqui.

Os workflows adicionados usam runners macOS do GitHub Actions:

- `iOS CI`: faz checkout, seleciona um simulador disponível e executa `xcodebuild test`.
- `iOS Release`: gera `archive`, exporta o `ipa` e pode enviar para o TestFlight.

## Segredos obrigatórios

Cadastre estes segredos no repositório do GitHub antes de rodar `iOS Release`:

- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64`

## Como gerar o segredo base64

Converta o arquivo `.p8` da App Store Connect para base64 e salve o resultado em `APP_STORE_CONNECT_API_KEY_BASE64`.

Exemplo em PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXXXX.p8"))
```

## Observações

- O workflow de release usa assinatura automática com `App Store Connect API Key`.
- O `APPLE_TEAM_ID` atual foi mantido como `9T7N4J79TW`.
- Se a Apple exigir ajustes de assinatura para esse time, basta adaptar o workflow sem mudar o fluxo do app.

