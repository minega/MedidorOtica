# Build iOS sem Mac local

Este projeto e nativo em SwiftUI/Xcode. Por isso, `EAS Build` nao e o caminho compativel aqui.

Os workflows adicionados usam runners macOS do GitHub Actions:

- `iOS CI`: faz checkout e executa `xcodebuild clean build-for-testing`.
- `iOS Release`: gera `archive`, exporta o `ipa` e pode enviar para o TestFlight.

## Segredo obrigatorio

Cadastre este segredo no repositorio do GitHub antes de rodar `iOS Release`:

- `APP_STORE_CONNECT_API_KEY_BASE64`

Os identificadores atuais da conta ja estao fixados no workflow:

- `APP_STORE_CONNECT_KEY_ID`: `G5V2B335RL`
- `APP_STORE_CONNECT_ISSUER_ID`: `c585729a-639d-41fa-b8d8-bfeb29e17f71`
- `Bundle ID`: `Manzolli.MedidorOticaApp`

## Como gerar o segredo base64

Converta o arquivo `.p8` da App Store Connect para base64 e salve o resultado em `APP_STORE_CONNECT_API_KEY_BASE64`.

Exemplo em PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_G5V2B335RL.p8"))
```

## Observacoes

- O workflow de release usa assinatura automatica com `App Store Connect API Key`.
- O `APPLE_TEAM_ID` atual foi mantido como `9T7N4J79TW`.
- O app ja foi encontrado na App Store Connect com o bundle `Manzolli.MedidorOticaApp`.
- Se a Apple exigir ajustes de assinatura para esse time, basta adaptar o workflow sem mudar o fluxo do app.
