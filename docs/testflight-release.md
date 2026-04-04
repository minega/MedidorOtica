# Como Subir para o TestFlight

Este documento descreve o fluxo real para enviar uma build nova do app para o TestFlight e confirmar que ela foi processada pela Apple.

## Objetivo

Permitir que um chat novo consiga:

1. confirmar que está na branch certa;
2. subir o código para o GitHub;
3. disparar o workflow correto de release;
4. confirmar o número da build enviada;
5. consultar o estado real da build na Apple.

## Regras importantes

- `push` sozinho **não** sobe o app para o TestFlight.
- O upload real acontece pelo workflow `ios-release.yml` com `workflow_dispatch`.
- O número da build enviada para a Apple é o `run_id` do workflow `iOS Release`.
- O workflow `appstore-build-status.yml` deve ser chamado com o `build_number` exato da release quando a confirmação precisa importar.
- Só considerar a entrega concluída quando a Apple retornar:
  - `processingState = VALID`
  - `internalBuildState = IN_BETA_TESTING` ou `READY_FOR_BETA_TESTING`

## Pré-requisitos

- Estar no repositório `MedidorOtica`.
- Estar na branch de trabalho correta, normalmente `codex/...`.
- O commit desejado já precisa estar pronto localmente.
- O `gh` precisa estar autenticado.
- Os segredos do GitHub/App Store Connect já precisam existir no repositório.

## Passo a Passo

### 1. Confirmar branch e estado local

No terminal:

```powershell
git branch --show-current
git status --short
```

O objetivo é:

- confirmar a branch atual;
- garantir que o que precisa entrar na build já foi commitado.

### 2. Fazer commit e push

Se houver mudanças que precisam entrar na build:

```powershell
git add -- <arquivos>
git commit -m "Mensagem objetiva"
git push origin <branch-atual>
```

Observação:

- o `push` envia o código para o GitHub;
- o `push` **não** envia o app para o TestFlight.

### 3. Disparar a release do iOS

Executar:

```powershell
gh workflow run ios-release.yml --ref <branch-atual> -f upload_to_testflight=true
```

Exemplo real:

```powershell
gh workflow run ios-release.yml --ref codex/capture-precision-rewrite -f upload_to_testflight=true
```

Esse comando retorna a URL do run da release.

### 4. Acompanhar a release até o fim

Executar:

```powershell
gh run watch <run_id_da_release> --exit-status
```

Se tudo der certo, o workflow:

1. faz archive no macOS;
2. exporta o IPA;
3. envia para o TestFlight via `altool`.

## Como descobrir o número da build

O número da build é o próprio `run_id` do workflow `iOS Release`.

Exemplo:

- release: `23958676022`
- build enviada para a Apple: `23958676022`

## Confirmar o estado da build na Apple

### Opção recomendada

Rodar o workflow utilitário com o número exato da release:

```powershell
gh workflow run appstore-build-status.yml --ref <branch-atual> -f build_number=<run_id_da_release> -f timeout_minutes=20
```

Exemplo:

```powershell
gh workflow run appstore-build-status.yml --ref codex/capture-precision-rewrite -f build_number=23958676022 -f timeout_minutes=20
```

Depois acompanhar:

```powershell
gh run watch <run_id_do_status> --exit-status
```

E, se precisar ver o JSON final:

```powershell
gh run view <run_id_do_status> --log
```

## O que procurar no log final

No log do `App Store Build Status`, procurar a linha JSON final parecida com:

```json
{"buildNumber":"23958676022","processingState":"VALID","internalBuildState":"READY_FOR_BETA_TESTING","externalBuildState":"READY_FOR_BETA_SUBMISSION"}
```

Estados aceitos para considerar a build pronta:

- `processingState = VALID`
- `internalBuildState = IN_BETA_TESTING` ou `READY_FOR_BETA_TESTING`

## Comandos reais usados no projeto

Fluxo mínimo:

```powershell
git push origin codex/capture-precision-rewrite
gh workflow run ios-release.yml --ref codex/capture-precision-rewrite -f upload_to_testflight=true
gh run watch <run_id_release> --exit-status
gh workflow run appstore-build-status.yml --ref codex/capture-precision-rewrite -f build_number=<run_id_release> -f timeout_minutes=20
gh run watch <run_id_status> --exit-status
gh run view <run_id_status> --log
```

## Erros comuns

### 1. “Subi para o GitHub, então está no TestFlight”

Errado. O `push` sozinho não envia IPA nenhum para a Apple.

### 2. Workflow automático de status olhando a build errada

O workflow de status acionado por `push` pode acabar consultando a última release bem-sucedida da branch. Quando a confirmação precisa importar, rode manualmente o `appstore-build-status.yml` com `build_number=<run_id_da_release>`.

### 3. Release concluída, mas sem confirmação da Apple

Isso significa que o upload terminou, mas ainda falta checar o processamento real no App Store Connect.

### 4. Build não aparece no TestFlight

Antes de concluir que o upload falhou, confirme:

- `processingState = VALID`
- o grupo de teste interno existe;
- a build foi adicionada ao grupo ou o grupo tem acesso automático;
- o tester está no grupo;
- o aparelho está em iOS compatível.

## Arquivos envolvidos

- `.github/workflows/ios-release.yml`
- `.github/workflows/appstore-build-status.yml`

## Regra para futuros chats

Se um chat novo precisar subir uma build:

1. ler este documento;
2. confirmar branch e commit;
3. disparar `ios-release.yml`;
4. confirmar a build exata com `appstore-build-status.yml`;
5. só então responder que “está no TestFlight”.
