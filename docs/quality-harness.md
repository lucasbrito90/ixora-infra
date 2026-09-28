# Quality harness baseline — Ixora ecosystem

**Status:** Active engineering baseline  
**Scope:** Minimal **local validation commands** per repository before PR / staging promotion  
**Applies to:** `back_vibes`, `ixora-admin`, `front_vibes`, `ixora-app`

> **Baseline only.** No Playwright, no Cypress in CI harness, no Android instrumented tests, no PHPStan/Larastan install (unless added later by ADR). Commands verified against the workspace **May 2026**.

**Related:** [Git Flow](standards/git-flow.md) · [Onboarding](onboarding/onboarding.md) · [Deploy pipeline](architecture/backend/deploy-pipeline.md)

---

## Purpose

Give every engineer the **same minimal quality gate**: exact commands, expected tooling, pass/fail meaning, and gaps — without changing product behaviour or adding heavy E2E frameworks.

Run harness checks on **`feature/*`** before opening PR → `develop`.

---

## Quick reference

| Repository | One-shot local gate (copy/paste) |
| --- | --- |
| **back_vibes** | `composer test && composer lint:pint` |
| **ixora-admin** | `npm run typecheck && npm run build && npm run test` |
| **front_vibes** | `npm run lint && npm run typecheck && npm run test:unit && npm run build` |
| **ixora-app** | `cd ixora-app && ./gradlew :shared:build` (Windows: `gradlew.bat`) |
| **Native sync (mobile, when plugins change)** | `cd front_vibes && npm run cap:sync:android` |

**Staging deploy** still follows [deploy-pipeline](architecture/backend/deploy-pipeline.md) — harness does **not** replace homologation QA.

---

## `back_vibes` (Laravel API)

**Path:** [`back_vibes/`](../../back_vibes)

### Prerequisites

| Tool | Version | Notes |
| --- | --- | --- |
| PHP | **8.3+** | `composer.json` requirement |
| Composer | 2.x | |
| SQLite (default) | file DB | `.env` from `.env.example`; `database/database.sqlite` for tests |
| Extensions | pdo, mbstring, … | Match Laravel 13 requirements |

```bash
cd back_vibes
cp .env.example .env   # first time
php artisan key:generate
composer install
php artisan migrate    # first time / after schema changes
```

Firebase / Spaces are **not** required for the default Pest suite (uses fakes / SQLite).

### Commands (verified)

| Check | Command | Pass | Verified |
| --- | --- | --- | --- |
| **Tests (Pest)** | `composer test` | Exit `0`; JSON line `"result":"passed"` | ✅ **1410** tests (2026-09-23) |
| **Style (Pint dry-run)** | `composer lint:pint` | Exit `0` | ⚠️ **Currently fails** — 16 files need formatting (run `composer format:pint` when ready) |
| **Style (Pint fix)** | `composer format:pint` | Rewrites files | ✅ command exists |
| **Pint (direct)** | `./vendor/bin/pint --test` | Same as `lint:pint` | ✅ |
| **PHPStan / Larastan** | — | — | ❌ **Not installed** in `require-dev` — do not add without team approval |

Equivalent raw test invocation:

```bash
php artisan config:clear --ansi
php artisan test
```

### Composer scripts added (harness)

```json
"test": "config:clear + artisan test",
"lint:pint": "vendor/bin/pint --test",
"format:pint": "vendor/bin/pint"
```

### Explicitly out of scope (today)

- Larastan / PHPStan baseline
- Dusk / browser E2E
- Staging integration tests in harness
- Running migrations against staging from harness doc

### Notes

- If `composer` refuses root user: `COMPOSER_ALLOW_SUPERUSER=1 composer test` (CI images only).
- Pint failure is **style drift**, not test failure — fix with `composer format:pint` in a dedicated commit if policy requires green Pint.

---

## `ixora-admin` (Nuxt 3)

**Path:** [`ixora-admin/`](../../ixora-admin)

### Prerequisites

| Tool | Version |
| --- | --- |
| Node.js | LTS 18+ / 20+ |
| npm | 9+ |

```bash
cd ixora-admin
cp .env.example .env   # NUXT_PUBLIC_* optional for build/typecheck
npm install              # runs nuxt prepare via postinstall
```

### Commands (verified)

| Check | Command | Pass | Verified |
| --- | --- | --- | --- |
| **Typecheck** | `npm run typecheck` | Exit `0` | ✅ (`nuxt prepare && nuxt typecheck`) |
| **Unit tests (Vitest)** | `npm run test` | Exit `0` | ✅ `passWithNoTests: true` — no `*.test.ts` files yet |
| **Production build** | `npm run build` | Exit `0` | ✅ Nuxt SSR build |
| **Staging static (App Platform)** | `npm run generate` | Exit `0` | ✅ outputs `.output/public` |
| **Lint (ESLint)** | — | — | ❌ **Not configured** — no ESLint in `devDependencies` |

Direct equivalents:

```bash
npx nuxt typecheck          # after nuxt prepare
npx vitest run
npm run build
npm run generate
```

### npm scripts added (harness)

```json
"typecheck": "nuxt prepare && nuxt typecheck"
```

(`test`, `build`, `generate` already existed.)

### Proposed smallest lint addition (not done)

When the team wants ESLint:

```bash
npm install -D eslint @nuxt/eslint-config
```

Then add `"lint": "eslint ."` — **requires explicit approval**; not part of this baseline.

### Explicitly out of scope (today)

- Playwright / Cypress E2E
- ESLint (until added)
- Firebase live integration in harness (build uses empty public env defaults)

---

## `front_vibes` (Ionic + Capacitor)

**Path:** [`front_vibes/`](../../front_vibes)

### Prerequisites

| Tool | Version |
| --- | --- |
| Node.js | LTS |
| npm | 9+ |
| Android SDK | For `cap sync android` / device builds |
| Java JDK | Capacitor Android |

```bash
cd front_vibes
npm install
```

### Commands (verified)

| Check | Command | Pass | Verified |
| --- | --- | --- | --- |
| **Lint (ESLint)** | `npm run lint` | Exit `0` | ✅ |
| **Typecheck** | `npm run typecheck` | Exit `0` | ✅ `vue-tsc --noEmit` |
| **Build** | `npm run build` | Exit `0` | ✅ includes `vue-tsc` + Vite |
| **Staging build** | `npm run build:staging` | Same as build with staging env | ✅ (same toolchain) |
| **Unit tests (Vitest)** | `npm run test:unit` | Exit `0` | ✅ **515** tests / **48** files (2026-09-23) |
| **Android unit (Gradle)** | `cd android && ./gradlew testDebugUnitTest` | Exit `0` | ✅ **26** tests (2026-09-23, app module JVM) |
| **Capacitor Android sync** | `npm run cap:sync:android` | Exit `0` | ✅ wraps `cap sync android` |
| **E2E (Cypress)** | `npm run test:e2e` | — | ⏸️ **Not in baseline** — exists but not required |

Direct Capacitor command:

```bash
npx cap sync android
```

### Harness cleanup (May 2026)

- Removed stale scaffold `tests/unit/example.spec.ts` (referenced deleted `Tab1Page.vue`) — blocked Vitest with import error.
- Added `passWithNoTests: true` in `vite.config.ts`.
- Added scripts: `typecheck`, `cap:sync:android`; `test:unit` now runs `vitest run` (non-watch).

### Explicitly out of scope (today)

- Cypress in mandatory harness (`test:e2e` remains optional)
- Android instrumented / Espresso tests
- iOS sync in baseline (add `cap:sync:ios` when iOS is active)

---

---

## `ixora-app` (Kotlin Multiplatform)

**Path:** [`ixora-app/`](../../ixora-app) — repositório `ixora-app` no workspace Ixora (quinto repositório, criado em K07).

**Status:** Fase 1 concluída (K07–K11, 2026-09-24/25); Fase 2 concluída (K13–K16, 2026-09-26); **Fase 3 concluída (K18–K23, 2026-09-28)** — domínio CSDM, scheduling, repositórios smart home, persistência ADR-043, apresentação/Google Home. Apenas módulo `shared` (KMP). Nenhum `androidApp/` nem `iosApp/` ainda.

### Prerequisites

| Tool | Version | Nota |
| --- | --- | --- |
| JDK | **21** | JAVA_HOME deve apontar para JDK 21 |
| Android SDK | compileSdk 36, build-tools 35.0.0 | `local.properties` com `sdk.dir` |
| Gradle | 8.14.3 (wrapper) | Usar `./gradlew` (PowerShell: `gradlew.bat`) |
| Kotlin | 2.3.20 | Fixado no version catalog |
| AGP | 8.13.0 | Plugin `com.android.kotlin.multiplatform.library` |

```powershell
cd ixora-app
# first time: criar local.properties com sdk.dir=C:\Users\...\AppData\Local\Android\Sdk
```

### Commands (verificados)

| Check | Comando | Pass | Verificado |
| --- | --- | --- | --- |
| **Build completo** | `./gradlew :shared:build` | Exit `0` | ✅ Build SUCCESS (K07, 2026-09-24; K24 revalidado 2026-09-28) |
| **Testes (androidHostTest — JVM)** | `./gradlew :shared:testAndroidHostTest` | Exit `0` | ✅ **360** casos / **3** skipped / **0** falhas (K24, 2026-09-28, `ixora-app` @ `4792bfe`) |
| **Compilação iOS (cross, sem link)** | `./gradlew :shared:compileKotlinIosArm64` | Exit `0` | ✅ executa no Windows com Kotlin 2.3.20 |
| **Compilação iOS Simulator** | `./gradlew :shared:compileKotlinIosSimulatorArm64` | Exit `0` | ✅ executa no Windows |
| **Verificação de dependências** | Automática no build | — | ✅ `gradle/verification-metadata.xml` mantido |

**Gate de PR para `feature/*` → `develop` no `ixora-app`:**

```powershell
cd ixora-app
./gradlew :shared:build
```

Deve retornar `BUILD SUCCESSFUL`. `:shared:build` já roda `testAndroidHostTest` (incluindo os testes de `commonTest` no host Android) e `compileKotlinIosArm64`, `compileKotlinIosSimulatorArm64`, `compileTestKotlinIosArm64`.

### Distribuição dos testes (baseline K16)

Medido em **2026-09-26** com `ixora-app` em `develop` @ **`6cb88fb`**, sem variáveis de staging: `.\gradlew.bat :shared:testAndroidHostTest --rerun-tasks` (exit `0`); `:shared:build --rerun-tasks` incluiu `compileKotlinIosArm64` e `compileTestKotlinIosSimulatorArm64` (não `NO-SOURCE`).

**Histórico:** baseline K11 = **33** testes (somente player engine + `CommonMainBoundaryTest`; 2026-09-25).

**Contagem a partir dos XML JUnit** (`shared/build/test-results/testAndroidHostTest/*.xml` — atributos `tests`, `skipped`, `failures` de cada `<testsuite>`):

```powershell
$dir = "shared/build/test-results/testAndroidHostTest"
Get-ChildItem $dir -Filter "*.xml" | ForEach-Object {
  [xml]$x = Get-Content $_.FullName
  $ts = $x.testsuite
  [PSCustomObject]@{
    Class = ($_.BaseName -replace '^TEST-','')
    Tests = [int]$ts.tests
    Skipped = [int]$ts.skipped
    Failures = [int]$ts.failures
  }
} | Sort-Object Class | Format-Table -AutoSize
# Totais: (Tests -Sum), (Skipped -Sum), (Failures -Sum)
```

| Área | Classes (`androidHostTest` / `commonTest` no host) | Testes | Skipped | Conteúdo |
| --- | --- | --- | --- | --- |
| Player engine (K09–K11) | `VibeSoundSerializationTest`, `VibeExecutionLayerTest`, `ExecutionPlanBehaviorTest`, `ExecutionPlanGoldenMasterTest`, `ExecutionPlanCombinatorialParityTest`, `FormatDurationExhaustiveParityTest` | 13 | 0 | paridade `buildVibeExecutionPlan` / `formatDuration` / fixtures de som |
| Cliente HTTP (K14) | `HttpClientTest`, `DefaultEngineOkHttpTest` | 24 | 0 | Ktor mock, erros, refresh ADR-044, engine OkHttp |
| Repositórios (K15) | `HttpAuthRepositoryTest`, `HttpVibeRepositoryTest` | 15 | 0 | sync, listagem, sons por vibe |
| Serialização / modelos | `SyncedUserSerializationTest`, `VibeSerializationTest`, `DataEnvelopeSerializationTest` | 12 | 0 | `SyncedUser`, `Vibe`, envelope `data` |
| Fixtures reais | `StagingVibesFixtureTest` | 1 | 0 | JSON de vibes do staging |
| Guard de fronteira (K08) | `CommonMainBoundaryTest` | 20 | 0 | imports proibidos em `commonMain` |
| Infraestrutura de integração (K16) | `StagingIntegrationEnvTest`, `TokenMutatingProviderTest` | 5 | 0 | gate de env, mutação de token para testes |
| Integração staging opt-in (K16) | `StagingIntegrationTest` | 3 | 3 | skipped sem as 4 variáveis de ambiente (ver abaixo) |
| **Total** | **18** classes | **93** | **3** | **0** falhas |

### Distribuição dos testes (baseline K24)

Medido em **2026-09-28** com `ixora-app` em `develop` @ **`4792bfe`**, sem variáveis de staging: `.\gradlew.bat :shared:testAndroidHostTest --rerun-tasks` (exit `0`); totais conferidos nos XML JUnit abaixo.

**Histórico:** baseline K11 = **33** testes (somente player engine + `CommonMainBoundaryTest`; 2026-09-25); baseline K16 = **93** testes (2026-09-26); baseline K17 = **93** testes (fechamento da Fase 2, mesmo commit `6cb88fb`).

**Contagem a partir dos XML JUnit** (`shared/build/test-results/testAndroidHostTest/*.xml` — atributos `tests`, `skipped`, `failures` de cada `<testsuite>`):

```powershell
$dir = "shared/build/test-results/testAndroidHostTest"
Get-ChildItem $dir -Filter "*.xml" | ForEach-Object {
  [xml]$x = Get-Content $_.FullName
  $ts = $x.testsuite
  [PSCustomObject]@{
    Class = ($_.BaseName -replace '^TEST-','')
    Tests = [int]$ts.tests
    Skipped = [int]$ts.skipped
    Failures = [int]$ts.failures
  }
} | Sort-Object Class | Format-Table -AutoSize
# Totais: (Tests -Sum), (Skipped -Sum), (Failures -Sum)
```

| Área | Classes (`androidHostTest` / `commonTest` no host) | Testes | Skipped | Conteúdo |
| --- | --- | --- | --- | --- |
| Player engine (K09–K11) | `VibeSoundSerializationTest`, `VibeExecutionLayerTest`, `ExecutionPlanBehaviorTest`, `ExecutionPlanGoldenMasterTest`, `ExecutionPlanCombinatorialParityTest`, `FormatDurationExhaustiveParityTest` | 13 | 0 | paridade `buildVibeExecutionPlan` / `formatDuration` / fixtures de som |
| Cliente HTTP (K14) | `HttpClientTest`, `DefaultEngineOkHttpTest` | 24 | 0 | Ktor mock, erros, refresh ADR-044, engine OkHttp |
| Repositórios base (K15) | `HttpAuthRepositoryTest`, `HttpVibeRepositoryTest` | 15 | 0 | sync, listagem, sons por vibe |
| Serialização / modelos | `SyncedUserSerializationTest`, `VibeSerializationTest`, `DataEnvelopeSerializationTest` | 12 | 0 | `SyncedUser`, `Vibe`, envelope `data` |
| Fixtures reais | `StagingVibesFixtureTest` | 1 | 0 | JSON de vibes do staging |
| Guard de fronteira (K08) | `CommonMainBoundaryTest` | 21 | 0 | imports proibidos em `commonMain` (incl. allowlist DataStore ADR-043) |
| Infraestrutura de integração (K16) | `StagingIntegrationEnvTest`, `TokenMutatingProviderTest` | 5 | 0 | gate de env, mutação de token para testes |
| Integração staging opt-in (K16) | `StagingIntegrationTest` | 3 | 3 | skipped sem as 4 variáveis de ambiente (ver abaixo) |
| CSDM canônico e guards (K19) | `CapabilityContractCoherenceTest`, `CsdmBoundaryTest`, `ActionTypeLabelTest`, `ActionTypeOptionsTest`, `AvailableActionTypeOptionsTest`, `BuildParametersTest`, `ConstraintAndCapabilityTest`, `DefaultValueForTest`, `IsMvpActionTypeTest`, `IsValidActionDraftTest`, `ParseCapabilitiesTest`, `ProviderNeutralityTest`, `SupportedActionTypesTest`, `ValidateActionDraftTest`, `ValidateCanonicalValueTest` | 70 | 0 | schema vendorizado ↔ `CanonicalContract`, guards CSDM, domínio canônico |
| Recorrência e rotulagem (K20) | `ActiveSchedulesCountTest`, `ActiveSchedulesSummaryTest`, `AutomationBadgeMappingTest`, `FormatInstantInZoneTest`, `FormatWeekdayListTest`, `HasActiveScheduleTest`, `HasDeviceActionsTest`, `IsWeeklyConfigValidTest`, `RecurrenceSummaryTest`, `RecurrenceTypeLabelTest`, `ResolveScheduleVibeNameTest`, `ScheduleAutomationBadgeLabelTest`, `ScheduleAutomationBadgeTest`, `ScheduleAutomationStatusLabelTest`, `UtcISOToZonedWallTimeTest`, `VibeAutomationBadgeLabelTest`, `VibeAutomationBadgeTest`, `ZonedWallTimeToUtcISOTest` | 54 | 0 | `schedule-datetime`, `schedule-format`, `automation-badges`, `automation-summary` |
| Repositórios smart home / schedule (K21) | `VibeSmartHomeDispatchClientTest`, `HttpDeviceRepositoryTest`, `HttpSceneRepositoryTest`, `HttpSceneDeviceActionRepositoryTest`, `HttpSceneDispatchRepositoryTest`, `HttpSceneActionExecutionReportRepositoryTest`, `HttpScheduleRepositoryTest`, `HttpScheduleExecutionRepositoryTest`, `GetProviderTypesTest`, `GetProviderConnectionsTest`, `GetProviderConnectionTest`, `CreateProviderConnectionTest`, `UpdateProviderConnectionTest`, `DeleteProviderConnectionTest`, `SyncProviderConnectionTest`, `SyncReportedDevicesTest`, `PayloadToStringRedactionTest` | 66 | 0 | clientes REST restantes (scene, device, provider-connection, schedule, dispatch) |
| Persistência SQLDelight / DataStore (K22) | `SqlDelightScheduleMirrorRepositoryTest`, `SqlDelightOfflineVibeManifestRepositoryTest`, `SqlDelightOfflineAudioManifestRepositoryTest`, `DataStoreIxoraPreferencesRepositoryTest`, `IxoraDatabaseSchemaInitializerTest` | 26 | 0 | espelho de agendamentos, dois manifestos offline, preferências ADR-043, inicializador único de schema |
| Apresentação e Google Home (K23) | `SoundArtworkPresentationParityTest`, `OfflinePlaybackStatusTest`, `GoogleHomeExecutionServiceTest`, `DelayNeedsAppOpenTest` | 50 | 0 | artwork/som (parcial), saúde offline, orquestração Google Home (sem SDK) |
| **Total** | **77** classes | **360** | **3** | **0** falhas |

### Teste opt-in de integração com staging (K16)

Prova **somente leitura** contra `https://staging-api.ixora-app.app/api` (host `androidHostTest`). **Não** entra no gate padrão de PR; **não** rodar em CI sem injeção controlada de segredos.

**O que prova** (`StagingIntegrationTest` — três fluxos):

1. Token Firebase válido → `POST /auth/sync` (uma vez) → `GET /vibes` → `GET /vibes/{id}/sounds`.
2. Primeira requisição com JWT corrompido → 401 do staging → um refresh forçado → `GET /vibes` ok (regra ADR-044 em servidor real).
3. Todas as requisições com JWT corrompido → após refresh + retry, `listVibes()` retorna `DomainError.Unauthorized` (401 real, não falha local de token).

**Variáveis de ambiente** (apenas nomes; valores locais em `front_vibes/.env` — nunca commitar):

| Variável | Uso |
| --- | --- |
| `IXORA_STAGING_INTEGRATION` | Deve ser `1`; caso contrário os **3** testes são **skipped** (JUnit `Assume`) |
| `VITE_FIREBASE_API_KEY` | Firebase Web API key |
| `E2E_USER_EMAIL` | Conta QA |
| `E2E_USER_PASSWORD` | Senha da conta QA |

**Execução local (PowerShell, a partir de `ixora-app/`):** definir as quatro variáveis **só no processo deste comando** (não ecoar valores). Usar `--no-daemon` para não reutilizar daemon com env antigo. Usar `cleanTestAndroidHostTest` porque variáveis de ambiente **não** são inputs de cache do Gradle — sem clean, skip/pass anterior pode vir do cache.

```powershell
$envFile = "..\front_vibes\.env"
foreach ($k in 'VITE_FIREBASE_API_KEY','E2E_USER_EMAIL','E2E_USER_PASSWORD') {
  $line = Select-String -Path $envFile -Pattern "^$k=" | Select-Object -First 1
  if ($line) { Set-Item -Path "Env:$k" -Value ($line.Line.Substring($k.Length + 1)) }
}
$env:IXORA_STAGING_INTEGRATION = '1'
.\gradlew.bat --no-daemon :shared:cleanTestAndroidHostTest :shared:testAndroidHostTest --tests "*StagingIntegrationTest*"
Remove-Item Env:VITE_FIREBASE_API_KEY,Env:E2E_USER_EMAIL,Env:E2E_USER_PASSWORD,Env:IXORA_STAGING_INTEGRATION -ErrorAction SilentlyContinue
```

**Limites (API staging, `back_vibes` `AppServiceProvider`):** `POST /api/auth/sync` — limiter `auth`, **10** requisições/minuto por IP; a suíte chama sync **no máximo uma vez por execução JVM** (fluxo 1). Rotas autenticadas — limiter `api`, **60** requisições/minuto por usuário (fallback IP se não autenticado). HTTP 429 em sync: parar e aguardar — não repetir em loop.

Sem as quatro variáveis, o mesmo `--tests "*StagingIntegrationTest*"` reporta **3 skipped**, 0 falhas.

Detalhes e links para fontes: seção **Staging integration test (opt-in, K16)** do `README.md` do `ixora-app`.

### iOS tests (não executáveis no Windows)

O target `iosTest/` compila (`compileTestKotlinIosArm64` funciona), mas os testes não executam sem Mac/Xcode/simulador. O gate de PR acima não requer execução iOS; ela é um artefato da chegada do Mac.

### Verificação de dependências

`gradle/verification-metadata.xml` é mantido. Ao adicionar dependências novas, regenerar com:

```powershell
./gradlew --write-verification-metadata sha256 :shared:build
```

O metadata atual cobre apenas Windows (`Select-String` em `gradle/verification-metadata.xml`: artefato nativo `kotlin-native-prebuilt-2.3.20-windows-x86_64.zip`; sem entradas Linux/Mac equivalentes). As dependências K14 (Ktor **3.5.2**, `ktor-client-mock`, engines OkHttp e Darwin), com **kotlinx-coroutines** resolvido em **1.11.0** (`:shared:dependencies --configuration commonMainResolvableDependenciesMetadata`), estão registradas no metadata. Para outro SO (Linux CI, Mac): rodar o comando nesse SO e **mesclar** as entradas, nunca sobrescrever. Ao adicionar qualquer dependência nova, regenere o metadata depois que ela entra.

### Guards e paridade

O `CommonMainBoundaryTest` (K08) protege a fronteira do `commonMain`: rejeita qualquer import de `java.*`, `javax.*`, `android.*` ou `androidx.*` em fontes de `commonMain`, com sentinelas que provam tanto detecção quanto não-detecção.

As suítes de paridade do player engine (K10/K11) provam comportamento do `buildVibeExecutionPlan`, `formatDuration` e `buildSummary` contra o TypeScript real. O procedimento de oracle (esbuild + Node) e a cobertura dos casos estão documentados na seção "Player engine parity" do `README.md` do `ixora-app`.

### Explicitly out of scope (today)

- `androidApp/` (ainda não existe)
- `iosApp/` (aguarda Mac; Fase 10 do plano)
- Testes instrumentados Android (aguarda `androidApp/`)
- SKIE (entra com o `iosApp`)
- CI (GitHub Actions) — não definido ainda

### Notas

- `iosApp/` ainda não existe (o projeto Xcode não pode ser criado no Windows); os targets iOS vivem em `shared/build.gradle.kts`.
- `dependency-verification=strict` é o padrão; nunca desabilitar permanentemente.
- Windows: usar `gradlew.bat` ou `./gradlew` no PowerShell (o wrapper PowerShell funciona com `./gradlew`).

---

## CSDM boundary tests (baseline)

Permanent source-scan guards for the canonical Smart Home model (ADR-037). Run as part of each repo’s normal unit suite — **not** a separate command.

| Repo | Test file | Verified |
| --- | --- | --- |
| `back_vibes` | `tests/Unit/SmartHome/Canonical/CanonicalBoundaryTest.php` | ✅ included in `composer test` (2026-09-23) |
| `back_vibes` | `tests/Unit/SmartHome/Canonical/CapabilityContractCoherenceTest.php` | ✅ schema ↔ PHP |
| `back_vibes` | `tests/Unit/SmartHome/ProviderExtensibilityBoundaryTest.php` | ✅ ADR-032 D.1 (domain provider slugs) |
| `front_vibes` | `src/utils/__tests__/canonical-boundary.test.ts` | ✅ included in `npm run test:unit` |
| `front_vibes` | `src/utils/__tests__/capability-contract-coherence.test.ts` | ✅ schema ↔ TS constants |
| `front_vibes` Android | `android/app/src/test/java/app/ixora/googlehome/CanonicalScaleBoundaryTest.kt` | ✅ included in `testDebugUnitTest` |

Contract vendoring: [`contracts/README.md`](../../contracts/README.md).

---

## Cross-repo expectations

| Rule | Detail |
| --- | --- |
| **No product changes for green harness** | Harness fixes are scripts, docs, stale test removal — not feature refactors |
| **Server rules stay in Laravel** | [repo-responsibilities](architecture/repo-responsibilities.md) |
| **No client Spaces writes** | [ADR-002](decisions/ADR-002-laravel-only-storage-writes.md) |
| **Specs/ADRs unchanged by harness** | Harness does not alter acceptance criteria |
| **Per-repo Git Flow** | Run harness on `feature/*` before PR |

### Suggested PR checklist

- [ ] Harness commands for **each touched repo** pass (or documented exception, e.g. Pint drift)
- [ ] Central spec/ADR updated if behaviour changed
- [ ] Cross-repo features: harness run in **all** affected repos

---

## CI / future work (not implemented)

| Item | Status |
| --- | --- |
| GitHub Actions per repo | Not defined in this baseline |
| Shared workflow in `ixora-infra` | Future |
| PHPStan/Larastan | Not installed — propose ADR before adding |
| Admin ESLint | Not installed |
| Playwright | Explicitly deferred |
| Android automated UI tests | Explicitly deferred |

---

## Verification log

Commands executed in workspace **2026-05-23**:

| Repo | Command | Result |
| --- | --- | --- |
| back_vibes | `composer test` | 100 passed |
| back_vibes | `composer lint:pint` | Fail — 16 files need Pint |
| back_vibes | `vendor/bin/phpstan` | Binary absent |
| ixora-admin | `npm run typecheck` | Pass |
| ixora-admin | `npm run build` | Pass |
| ixora-admin | `npm run generate` | Pass |
| ixora-admin | `npm run test` | Pass (no tests) |
| front_vibes | `npm run lint` | Pass |
| front_vibes | `npm run typecheck` | Pass |
| front_vibes | `npm run build` | Pass |
| front_vibes | `npm run test:unit` | Pass (no tests) |
| front_vibes | `npm run cap:sync:android` | Pass |

**CSDM-07 harness refresh (2026-09-23):**

| Repo | Command | Result |
| --- | --- | --- |
| back_vibes | `composer test` | **1410** passed, **6976** assertions |
| front_vibes | `npm run test:unit` | **515** passed, **48** files |
| front_vibes | `cd android && ./gradlew testDebugUnitTest` | BUILD SUCCESSFUL, **26** JVM unit tests |

**K12 — ixora-app Fase 1 (2026-09-25):**

| Repo | Command | Result |
| --- | --- | --- |
| ixora-app | `./gradlew :shared:build --rerun-tasks --console=plain` | BUILD SUCCESSFUL in 2m 59s (36 tasks executed); Kotlin 2.3.20 / AGP 8.13.0 / Gradle 8.14.3 / JDK 21 |
| ixora-app | `testAndroidHostTest` (incluído no build acima) | 33 testes — CommonMainBoundaryTest=20, VibeSoundSerializationTest=5, VibeExecutionLayerTest=1, ExecutionPlanBehaviorTest=2, ExecutionPlanGoldenMasterTest=2, ExecutionPlanCombinatorialParityTest=2, FormatDurationExhaustiveParityTest=1; 0 falhas |
| ixora-app | `compileKotlinIosArm64` (incluído no build acima) | Executado (cross-compile Windows → klib; link iOS exige Mac) |
| front_vibes | `node node_modules/vitest/vitest.mjs run` | **515** tests / **48** files — confirmado (45 `*.test.ts` + 3 `*.spec.ts` em `src/`; `npx vitest` não funciona nesta máquina — `node_modules/.bin/vitest` ausente —, `node node_modules/vitest/vitest.mjs run` funciona; `tests/e2e`, `tests/smoke`, `qa-android-native/` excluídos pelo `vite.config.ts`; sem alteração no repositório) |

---

## Related documentation

| Document | Topic |
| --- | --- |
| [README.md](README.md) | Documentation index |
| [onboarding/onboarding.md](onboarding/onboarding.md) | New engineer setup |
| [architecture/repo-responsibilities.md](architecture/repo-responsibilities.md) | Where logic belongs |
| [standards/git-flow.md](standards/git-flow.md) | Branch promotion |
| [architecture/mobile/kmp-migration-plan.md](architecture/mobile/kmp-migration-plan.md) | Fase 1 concluída; resultado e aprendizados em §17.1 |

When harness commands change, update **this file first**, then repo README pointers.
