# Plano de migração do front_vibes para Kotlin Multiplatform

**Status:** Proposta para decisão — nenhuma implementação autorizada por este documento.
**Data:** 2026-09-23
**Escopo:** camada mobile do Ixora (`front_vibes`). Não altera `back_vibes`, `ixora-admin` nem contratos de API.
**Premissas confirmadas com o PO:** iOS depende da compra de um Mac (sem data); os motivadores são qualidade do player de áudio, experiência nativa de UI e consolidação em Kotlin; execução solo com apoio do Cursor.

---

## 1. Resumo executivo e recomendação central

### 1.1 O achado que muda a recomendação

Os três motivadores declarados — **qualidade do player**, **UI nativa** e **stack Kotlin** — são integralmente atendidos por um **app Android nativo (Kotlin + Compose)**. Nenhum deles exige Kotlin Multiplatform.

O KMP paga o seu custo quando existe uma **segunda plataforma consumindo a mesma lógica**. Hoje o iOS não existe no repositório (não há pasta `ios/`), não há Mac, e "lançar iOS" não foi marcado como motivador. Ou seja: o plano precisa entregar valor **antes** e **independentemente** do iOS, ou o investimento em KMP fica sem retorno por tempo indeterminado.

### 1.2 Recomendação

> **Construir Android nativo agora, com a lógica compartilhável isolada em um módulo KMP desde o primeiro dia, e com os targets iOS declarados mas não construídos.**

Concretamente:

- A lógica de domínio, rede, plano de execução e regras vai para `shared/commonMain`, escrita **sem nenhuma API exclusiva de Android**.
- O `androidApp` é o único app construído e publicado durante toda a migração.
- Os targets `iosArm64` / `iosSimulatorArm64` ficam **declarados no Gradle** e o `iosApp` existe como esqueleto, mas não há fase de UI iOS executável até o Mac chegar.
- A disciplina de "commonMain limpo" é garantida por **teste de fronteira**, no mesmo estilo dos guards do CSDM-07 que já existem no projeto — não por boa vontade.

O custo marginal de escrever a lógica em `commonMain` em vez de um módulo Android puro é pequeno (essencialmente: usar `kotlinx-datetime` em vez de `java.time`, Ktor em vez de OkHttp direto, SQLDelight em vez de Room-Android). O benefício é que o dia em que o Mac chegar, o iOS começa com a camada de negócio pronta e testada, em vez de começar do zero.

### 1.3 O que isso não resolve

Seja explícito sobre o tamanho real: **KMP compartilha hoje cerca de 15% do código existente.** A UI (13.640 linhas de Vue) é reescrita integralmente, e uma segunda vez quando o iOS entrar. O runtime de áudio (2.849 linhas) é reescrito nativo nas duas plataformas. Isso é inerente à decisão de UI nativa — não é um defeito do plano, mas precisa estar dimensionado antes de começar.

---

## 2. Inventário da aplicação atual (medido, não estimado)

Contagens obtidas em `front_vibes` @ `develop` (`1cf858e`), excluindo arquivos de teste.

| Área | Arquivos | Linhas | Observação |
| --- | --- | --- | --- |
| `views/` | 28 | 11.433 | Telas Ionic/Vue |
| `components/` | 7 | 2.207 | Inclui `PlayerDebugPanel` (861) e `MiniPlayer` (536) |
| `services/` | 43 | 7.956 | Camada mais heterogênea — ver §2.2 |
| `composables/` | 20 | 2.280 | Estado Vue sobre os services |
| `utils/` | 17 | 1.694 | Quase tudo lógica pura |
| `stores/` | 1 | 623 | `player.store.ts` (Pinia) |
| `router/` | 3 | 357 | 29 rotas |
| `telemetry/` | 3 | 541 | OpenTelemetry web |
| `types/` | 2 | 45 | |
| **Total `src/`** | **129** | **27.590** | |
| Testes Vitest | 48 | 9.064 | 515 testes |
| Kotlin nativo (`android/`) | 3 | 493 | Plugin Google Home |
| Testes Kotlin | 4 | 330 | |

Não existe pasta `ios/`. O `applicationId` real é `app.ixora.ixora`, embora `capacitor.config.ts` ainda declare `io.ionic.starter`.

### 2.1 Os três blocos que definem o esforço

1. **UI (13.640 linhas)** — reescrita total por plataforma. Nada aproveitável além das regras de apresentação já extraídas para `utils/`.
2. **Runtime de áudio (2.849 linhas)** — `audio-player.service.ts` (1.887), `audio-engine/` (903), `audio-focus.service.ts` (59). Substituído por Media3 no Android e AVAudioEngine no iOS.
3. **Lógica livre de plataforma (≈3.900 linhas)** — 17 services e 16 utils que **não importam** `@capacitor`, `@ionic`, `firebase`, `vue` nem `pinia`. Este é o conjunto que migra quase 1:1 para `commonMain`.

Acoplamento medido por import: `@ionic` em 40 arquivos, `vue` em 49, `@capacitor` em 27, `pinia` em 7, `firebase` em 4.

### 2.2 Classificação por componente

**SHARED — vai para `commonMain`**

| Componente | Linhas | Justificativa |
| --- | --- | --- |
| `player-engine.service.ts` (`buildVibeExecutionPlan`) | 188 | Transformação pura `VibeSound[] → VibeExecutionLayer[]`. É o contrato do ADR-008 e a peça de maior valor compartilhado do app inteiro. |
| Clientes de API (`vibe`, `sound`, `scene`, `schedule`, `device`, `provider-connection`, `preset-vibe`, `cover-bundle`, `vibe-sound`, `scene-device-action`, `scene-dispatch`, `schedule-execution`, `smart-home-dispatch`, `scene-action-execution-report`) | ≈2.000 | Wrappers REST sobre a API Laravel. Contrato idêntico nas duas plataformas. |
| `canonical-capabilities` + `canonical-contract` + `device-action` + `device-status` | 618 | Domínio CSDM. Já é provider-neutro por construção e protegido por guards de fronteira. |
| `automation-badges`, `automation-summary`, `schedule-datetime`, `schedule-format` | 543 | Regras de recorrência e rotulagem. Alto valor em teste compartilhado. |
| `offline-playback-status` | 167 | Decisão de disponibilidade offline — pura. |
| `soundPresentation`, `artwork`, `preset-artwork`, `sound-file-url`, `cover-bundle-apply`, `vibe-form-preview` | ≈310 | Regras de apresentação sem dependência de framework. |
| `google-home-execution.service.ts` | 289 | Orquestração pura; a chamada ao SDK fica atrás de uma interface (ver §9). |
| Espelho SQLite de schedules (lógica) | ≈200 | A lógica de sincronização é compartilhada; o driver SQL é por plataforma. |

**PLATFORM-SPECIFIC — implementação nativa por plataforma**

| Componente | Destino |
| --- | --- |
| Runtime de áudio | Android: Media3/ExoPlayer. iOS: AVAudioEngine. |
| Reprodução em background | Android: `MediaSessionService` + foreground service. iOS: `AVAudioSession` + background audio mode. |
| Notificação de mídia / controles | `MediaSession` (Android) e `MPNowPlayingInfoCenter` (iOS). |
| Foco de áudio / interrupções | `AudioManager` (Android) e notificações de interrupção do `AVAudioSession`. |
| Firebase Auth | SDK nativo de cada plataforma atrás de `expect/actual`. |
| Push (FCM) | SDK nativo; a lógica de registro/renovação de token é compartilhada. |
| Armazenamento seguro do token | `EncryptedSharedPreferences` / Keychain. |
| Permissões | API nativa de cada plataforma. |
| Navegação | Navigation Compose / `NavigationStack` do SwiftUI. |
| UI completa | Compose e SwiftUI. |
| Google Home SDK | **Android-only por natureza** (ADR-036). Vira módulo Android direto. |
| Telemetria OTel | SDK por plataforma atrás de interface compartilhada. |

**REMOVE/REPLACE — sai do projeto**

Capacitor e seus 12 plugins (`@capacitor/*`, `@capacitor-community/sqlite`, `@capacitor-firebase/messaging`, `@capawesome-team/capacitor-android-foreground-service`, `@capgo/native-audio`, `@codetrix-studio/capacitor-google-auth`), Ionic, Vue, Pinia, vue-router, Vite, `patch-package`, o fallback `HTMLAudioElement` para web, e os testes Vitest/Playwright/Cypress que cobrem componentes Vue.

**MIGRATION/REFACTOR — aproveitamento parcial**

- Os testes Vitest de lógica pura (`utils/`, `player-engine`, `canonical-capabilities`) têm equivalente direto em `commonTest`. Devem ser **portados caso a caso como paridade**, não reescritos do zero: são a rede de segurança da migração.
- Os specs WDIO/Appium em `qa/` apontam para o DOM do WebView e **morrem todos**. Precisam ser refeitos com seletores nativos (UiAutomator2 continua servindo).
- A cópia vendorizada de `capability.v1.schema.json` acompanha o novo app, com teste de coerência, conforme a regra de vendoring de `contracts/README.md`.

---

## 3. Matriz de responsabilidades

Legenda: ● implementa · ○ consome · — não participa

| Responsabilidade | KMP | Android | iOS | Justificativa |
| --- | --- | --- | --- | --- |
| Models / DTOs | ● | ○ | ○ | Contrato único com a API Laravel; divergência aqui é bug garantido. |
| Networking (HTTP) | ● | ○ | ○ | Ktor cobre as duas plataformas; o contrato REST é idêntico. |
| API clients | ● | ○ | ○ | Mesmo motivo; elimina duplicação de rotas e parsing. |
| Repositories | ● | ○ | ○ | Política de cache/offline é regra de negócio, não de plataforma. |
| Regras de negócio | ● | ○ | ○ | Razão de existir do módulo compartilhado. |
| Plano de execução da vibe | ● | ○ | ○ | Função pura e crítica; teste único vale para as duas plataformas. |
| Persistência relacional | ● | ○ | ○ | SQLDelight gera o mesmo schema e as mesmas queries nos dois lados. |
| Preferências não sensíveis | ● | ○ | ○ | DataStore multiplataforma. |
| Secure storage (token) | ○ | ● | ● | Keystore e Keychain não têm abstração honesta; interface no shared, implementação nativa. |
| **Transporte de áudio** | — | ● | ● | Media3 e AVAudioEngine não têm denominador comum. Tentar abstrair produz o mesmo beco do `@capgo/native-audio`. |
| **Agendamento das camadas** | ● | ○ | ○ | *Decidir o que deve tocar no instante t* é determinístico e testável — ver §10. |
| Reprodução em background | — | ● | ● | Foreground service vs. background mode: modelos de SO incompatíveis. |
| Vídeo / fundo animado | — | ● | ● | Não existe hoje; se entrar, é nativo. |
| Navegação | — | ● | ● | Navegação é parte da identidade de cada plataforma. |
| Push notifications | ○ | ● | ● | Registro/renovação de token compartilhados; entrega e exibição nativas. |
| Firebase Auth | ○ | ● | ● | Sem SDK oficial KMP; ver §6.7. |
| Home Assistant | — | — | — | Execução é **server-side** no `back_vibes` (ADR-036). O mobile só chama a API. |
| Google Home | ○ | ● | — | SDK exclusivo de Android; iOS nunca terá (ADR-036). |
| Permissões | — | ● | ● | APIs e fluxos de consentimento divergentes. |
| Background tasks | — | ● | ● | WorkManager vs. BGTaskScheduler. |
| Analytics / Telemetria | ○ | ● | ● | Interface compartilhada, SDK nativo. |
| Logging | ● | ○ | ○ | Abstração barata; saída por plataforma. |
| Tratamento de erros | ● | ○ | ○ | Tipos de erro de domínio compartilhados — ver §8. |
| UI | — | ● | ● | Decisão explícita do PO: sem Compose Multiplatform. |

Nenhuma responsabilidade foi marcada como compartilhada apenas por ser tecnicamente possível. Os três casos em que resistimos à tentação: transporte de áudio, navegação e UI.

---

## 4. Arquitetura proposta

```
┌──────────────────────────────┐   ┌──────────────────────────────┐
│         androidApp           │   │           iosApp             │
│  Jetpack Compose             │   │  SwiftUI                     │
│  Navigation Compose          │   │  NavigationStack             │
│  Media3 / MediaSessionService│   │  AVAudioEngine / AVSession   │
│  Firebase SDK (Android)      │   │  Firebase SDK (iOS)          │
│  Google Home SDK             │   │  (não aplicável)             │
└───────────────┬──────────────┘   └───────────────┬──────────────┘
                │        StateFlow / suspend        │
                │        (SKIE no lado Swift)       │
                └─────────────────┬─────────────────┘
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                        shared (KMP)                              │
│                                                                  │
│  presentation/   StateHolders por tela — StateFlow<UiState>      │
│                  + Channel<Effect> para eventos únicos           │
│  domain/         UseCases · buildVibeExecutionPlan · CSDM        │
│                  regras de recorrência · scheduler do player     │
│  data/           Repositories · Ktor client · SQLDelight         │
│                  DataStore · mapeadores                          │
│  platform/       expect/actual: secure storage, auth, áudio,     │
│                  push, permissões, telemetria                    │
└─────────────────────────────────┬────────────────────────────────┘
                                  │ HTTPS + Bearer Firebase JWT
                                  ▼
                        back_vibes (API Laravel)
```

A fronteira entre `shared` e os apps é **um contrato de estado**, não um conjunto de callbacks. Cada tela tem um StateHolder no `shared` que expõe `StateFlow<UiState>` e recebe intenções; a UI nativa apenas renderiza e despacha.

### 4.1 Padrão arquitetural

Recomendação: **UDF (fluxo unidirecional) com StateHolders no shared, sobre Repository + UseCases**, sem rotular de MVI formal.

- **Clean Architecture completa (entities/usecases/interface adapters em módulos separados):** rejeitada. Para um app deste tamanho com um desenvolvedor, o custo de cerimônia excede o ganho.
- **MVVM com ViewModel por plataforma:** rejeitada como padrão principal — duplicaria a lógica de estado nas duas plataformas, que é exatamente o que o KMP deveria evitar.
- **MVI canônico (reducer puro + intents):** parcialmente adotado. Usar `StateFlow` + intents sem a maquinaria de reducers/middlewares.
- **UseCases:** adotar **apenas onde há regra**, não como camada obrigatória. Um `getVibes()` que só repassa o repositório não merece uma classe.

---

## 5. Estrutura de módulos

### 5.1 Opções avaliadas

| Opção | Complexidade | Build | Adequação solo | Risco |
| --- | --- | --- | --- | --- |
| **A. Um módulo `shared`** com pacotes por domínio | Baixa | Rápido | Alta | Fronteiras dependem de disciplina |
| **B. Múltiplos módulos por domínio** (`core`, `network`, `vibes`, `player`, `smart-home`…) | Alta | Mais lento (8+ módulos Gradle) | Baixa | Refatoração constante de fronteiras no início |
| **C. Três módulos** (`shared-core`, `shared-domain`, `shared-data`) | Média | Médio | Média | Separação horizontal costuma gerar dependência circular |

**Recomendação: Opção A**, com uma condição — as fronteiras entre pacotes são protegidas por **teste de fronteira**, exatamente como os guards do CSDM-07 (`CanonicalBoundaryTest`) já fazem no backend. O projeto já demonstrou que esse mecanismo funciona e é barato.

Dividir em módulos Gradle depois, quando houver **motivo medido**: tempo de build incômodo, ou um domínio que precise de targets diferentes. Modularizar antes disso é otimização prematura que um desenvolvedor solo paga todo dia no Gradle sync.

### 5.2 Estrutura de diretórios recomendada

```
ixora-mobile/
├── settings.gradle.kts
├── gradle/libs.versions.toml          # version catalog
│
├── shared/
│   ├── build.gradle.kts
│   └── src/
│       ├── commonMain/kotlin/app/ixora/shared/
│       │   ├── domain/
│       │   │   ├── vibe/              # modelos + buildVibeExecutionPlan
│       │   │   ├── player/            # scheduler determinístico
│       │   │   ├── smarthome/         # CSDM canônico
│       │   │   ├── schedule/          # recorrência
│       │   │   └── auth/
│       │   ├── data/
│       │   │   ├── remote/            # Ktor + DTOs + mapeadores
│       │   │   ├── local/             # SQLDelight + DataStore
│       │   │   └── repository/
│       │   ├── presentation/          # StateHolders por tela
│       │   ├── platform/              # declarações expect
│       │   └── di/
│       ├── commonTest/kotlin/
│       ├── androidMain/kotlin/        # actual Android
│       ├── androidUnitTest/kotlin/
│       ├── iosMain/kotlin/            # actual iOS (escrito, não compilado até o Mac)
│       └── iosTest/kotlin/
│
├── androidApp/
│   └── src/main/kotlin/app/ixora/android/
│       ├── ui/                        # Compose por feature
│       ├── player/                    # Media3 + MediaSessionService
│       ├── googlehome/                # SDK Google Home (migrado do plugin atual)
│       ├── push/
│       └── platform/                  # actuals que precisam de Context
│
├── iosApp/                            # esqueleto Xcode, inerte até o Mac
│
└── contracts/smart-home/capability.v1.schema.json   # cópia vendorizada
```

### 5.3 Repositório: novo ou o mesmo?

| Opção | A favor | Contra |
| --- | --- | --- |
| **A. Novo repo `ixora-mobile`** | Raiz Gradle limpa; os dois apps coexistem sem conflito de tooling; `front_vibes` preservado como referência | Quinto repositório no workspace; CI e docs novos; exige atualizar `repo-responsibilities.md` |
| **B. Dentro do `front_vibes`** | Mantém histórico, Git Flow e evidências de QA; um lugar só | Conflito de raiz (npm/Vite vs. Gradle); o `android/` gerado pelo Capacitor colide com `androidApp/`; meses com duas stacks na mesma árvore |

**Recomendação: Opção A — novo repositório `ixora-mobile`**, criado a partir do momento em que a Fase 2 começar. A Fase 1 (prova do módulo compartilhado) pode ocorrer dentro do `front_vibes` atual, porque o projeto Android gerado pelo Capacitor é um projeto Gradle comum e aceita um módulo KMP — isso permite validar a tese sem criar repositório algum. Ver §11.

`front_vibes` nunca é deletado; vira repositório congelado de referência, coerente com a política do projeto de não apagar histórico.

---

## 6. Stack tecnológica

Cada escolha abaixo tem alternativa documentada. Nenhuma foi feita por popularidade.

### 6.1 Core

`Kotlin` + `Kotlin Multiplatform` + `kotlinx.coroutines` + `kotlinx.serialization` + `kotlinx-datetime`.

`kotlinx-datetime` não é opcional: o app tem recorrência de agendamento com fuso horário, e `java.time` no `commonMain` quebraria o iOS. É exatamente o tipo de erro que o teste de fronteira do §5.1 precisa pegar.

### 6.2 Networking

| Opção | Maturidade KMP | Prós | Contras |
| --- | --- | --- | --- |
| **Ktor Client** | Alta — é a referência | Engines nativos por plataforma; integra com kotlinx.serialization; plugin de Auth com refresh | API mais verbosa que Retrofit; breaking changes entre majors |
| Ktorfit | Média | Sintaxe estilo Retrofit sobre Ktor | Camada extra via KSP, dependência comunitária |
| Retrofit/OkHttp | Nula em KMP | Familiar no Android | Não roda em iOS — inviável |

**Recomendação: Ktor Client** com `ContentNegotiation`, `HttpTimeout` e um plugin de autenticação que injeta o Bearer do Firebase e trata renovação em 401. Sem Ktorfit no início.

Ponto de atenção medido: o `laravel-http.ts` atual existe em boa parte para contornar CORS e mixed-content do WebView. **Esse problema desaparece com o app nativo** — a camada de rede fica substancialmente mais simples do que a atual.

### 6.3 Persistência

| Opção | Maturidade KMP | Prós | Contras |
| --- | --- | --- | --- |
| **SQLDelight** | Alta | SQL verificado em compilação; drivers Android/iOS estáveis; API idêntica nos dois lados | Escrever SQL à mão; migrações manuais |
| Room KMP | Crescente | Google; familiar; migrações automáticas | KSP em targets nativos ainda gera atrito; mais novo em KMP |

**Recomendação: SQLDelight.** O uso atual é modesto — um espelho somente-leitura de schedules — e o SQL é simples. A maturidade em iOS importa mais aqui do que conveniência de anotação.

- **Preferências não sensíveis:** `androidx.datastore` (multiplataforma) — coroutines/Flow nativos.
- **Token e credenciais:** nunca em DataStore. `EncryptedSharedPreferences` no Android, Keychain no iOS, atrás de interface. O app atual já persiste o token em `@capacitor/preferences`; **a migração é a oportunidade de corrigir isso para armazenamento seguro de verdade.**
- **Áudio offline:** arquivos em disco, com manifesto em SQLDelight em vez de preferências. Ver §15, questão 6.

### 6.4 Injeção de dependência

| Opção | Prós | Contras |
| --- | --- | --- |
| **Koin** | KMP de primeira classe; curva baixa; sem geração de código | Resolução em runtime — erro aparece ao executar, não ao compilar |
| kotlin-inject / Metro | Verificação em compilação | Mais cerimônia; ecossistema menor |
| **Manual (AppGraph escrito à mão)** | Zero dependência; totalmente explícito | Cresce mal acima de algumas dezenas de dependências |

**Recomendação: Koin.** Para um app com essa quantidade de serviços, a DI manual começa confortável e envelhece mal. Vale registrar que a DI manual é uma escolha defensável se a preferência for minimizar dependências — não seria um erro.

### 6.5 Estado

`StateFlow` no `shared`. No Android, `collectAsStateWithLifecycle`. No iOS, `SKIE` converte `Flow` em `AsyncSequence` e expõe sealed classes como enums com `switch` exaustivo em Swift.

**SKIE é a recomendação mais importante desta seção.** Sem ele, consumir `Flow` e sealed classes em Swift exige wrappers manuais que envelhecem mal e são a principal fonte de frustração relatada em projetos KMP com SwiftUI.

Alternativa: `KMP-NativeCoroutines`, que resolve o mesmo problema com anotações. Ambos são comunitários; SKIE cobre mais casos (enums, default args, nomes).

### 6.6 Áudio

- **Android:** `androidx.media3` (ExoPlayer) + `MediaSessionService`.
- **iOS:** `AVAudioEngine` com `AVAudioPlayerNode` por camada e um mixer.

Ambos suportam **fade real** — o recurso que a stack atual abandonou por limitação do plugin, documentado em [`audio-engine-fade-limitations.md`](../audio/audio-engine-fade-limitations.md) e decidido na [ADR-008](../../decisions/ADR-008-nativeaudio-limitations-over-unstable-dsp.md). Recuperar fade é o ganho mais concreto e demonstrável do motivador nº 1, mas exige reabrir aquela decisão de forma explícita (§17).

### 6.7 Firebase

| Opção | Prós | Contras |
| --- | --- | --- |
| **`expect/actual` sobre os SDKs nativos** | Sem terceiros; controle total; só o que o app usa | Escrever a ponte (estimativa: ~200 linhas para Auth + FCM) |
| GitLive `firebase-kotlin-sdk` | API unificada pronta | Wrapper comunitário; atrasa em relação aos SDKs oficiais; dependência crítica fora do controle |

**Recomendação: `expect/actual` sobre os SDKs nativos.** A superfície usada é pequena (login e-mail/senha, Google Sign-In, reset de senha, ID token, FCM token). Não justifica assumir risco de terceiro em algo tão central quanto autenticação.

### 6.8 Testes

| Camada | Ferramenta |
| --- | --- |
| Lógica compartilhada | `kotlin.test` + `kotlinx-coroutines-test` + **Turbine** (asserção sobre Flows) |
| API compartilhada | Ktor `MockEngine` |
| Banco compartilhado | Driver SQLDelight in-memory |
| UI Android | Compose UI Test |
| UI iOS | XCTest |
| E2E em aparelho | Appium/WDIO com seletores nativos UiAutomator2 — reaproveitando a infraestrutura de `qa/` |

Regra de disciplina: **todo teste Vitest de lógica pura portado deve manter o mesmo nome e os mesmos casos**, para que a paridade seja auditável arquivo a arquivo.

---

## 7. Arquitetura de estado e fluxo de dados

```
Ktor (API)  ──▶  Repository  ──▶  UseCase (só onde há regra)
                     │                      │
                SQLDelight            StateHolder (shared)
                DataStore                   │
                                    StateFlow<UiState>
                                    Channel<Effect>
                          ┌─────────────────┴─────────────────┐
                   Compose (Android)                   SwiftUI (iOS)
```

**Onde o estado vive:** no `shared`, em um StateHolder por tela. As plataformas não guardam estado de domínio — guardam apenas estado efêmero de UI (scroll, foco, animação).

**Quem atualiza:** somente o StateHolder, em resposta a intenções (`onPlayClicked`) ou a emissões do repositório. Nada na UI escreve estado de domínio.

**Loading e erro fazem parte do estado**, não são canais paralelos:

```kotlin
data class VibeListState(
    val items: List<Vibe> = emptyList(),
    val isLoading: Boolean = false,
    val error: DomainError? = null,
)
```

**Efeitos únicos** (toast, navegação, diálogo) vão por `Channel`/`SharedFlow`, nunca no estado — senão reaparecem na recomposição.

**Erros nunca atravessam a fronteira como exceção.** Exceção Kotlin não capturada mata o processo no iOS. Todo retorno público é `Result<T, DomainError>` com `DomainError` selado.

**Ciclo de vida:** o StateHolder tem um `CoroutineScope` próprio, criado e cancelado pela plataforma. No Android, ancorado ao `ViewModel` (`androidx.lifecycle.ViewModel` já é multiplataforma, mas manter o ancoramento no lado Android é mais previsível). No iOS, cancelado no `deinit` do observável SwiftUI.

**Sobre igualar as plataformas:** o StateHolder compartilhado é o limite. Navegação, animação e apresentação ficam livres em cada lado. Forçar Android e iOS a parecerem iguais anularia o motivo de escolher UI nativa.

---

## 8. Interop Kotlin ↔ Swift

Cuidados que precisam estar decididos antes da primeira linha de `iosMain`, porque corrigir depois é caro:

1. **Exceções.** Só viram `NSError` se anotadas com `@Throws`; qualquer outra encerra o app. Contorno: `Result` selado em toda API pública.
2. **`Flow`.** Não tem equivalente em Swift. Resolver com SKIE (recomendado) ou wrapper manual desde o começo — não depois.
3. **Funções `suspend`.** Mapeiam para `async` em Swift, mas o cancelamento tem nuances; SKIE melhora a fidelidade.
4. **Sealed classes.** Sem SKIE, chegam como classes sem `switch` exaustivo, perdendo a segurança que motivou usá-las.
5. **Argumentos default.** Não são expostos ao Swift — cada variação vira sobrecarga explícita.
6. **Genéricos.** Apagados para `Any` na interop ObjC; evitar genéricos na superfície pública.
7. **Memória.** O novo gerenciador de memória do Kotlin/Native eliminou o `freeze`, mas ciclos de referência entre Kotlin e Swift ainda vazam. Cuidado especial com callbacks retidos.
8. **Threading.** O StateFlow deve emitir na main thread para o SwiftUI; definir isso no StateHolder, não na UI.
9. **Build.** O framework iOS é lento de compilar; usar framework estático e `binaryOptions` adequados.

**Risco específico deste projeto:** sem Mac, nada disso é verificável. O código `iosMain` escrito antes da compra do Mac é, na prática, **não testado** — e a experiência comum é que a primeira compilação iOS revela problemas em série. O plano assume isso explicitamente em §11 e §14.

---

## 9. Integrações nativas — estratégia por caso

Critério: `expect/actual` quando a API é **pequena e estável**; interface no `commonMain` com implementação injetada quando é **grande, tem estado ou precisa de mock em teste**.

| Integração | Estratégia | Justificativa |
| --- | --- | --- |
| Secure storage | `expect/actual` | API mínima: get/set/remove. |
| Plataforma/versão/locale | `expect/actual` | Valores simples. |
| Firebase Auth | **Interface + injeção** | Tem estado (sessão) e precisa de fake nos testes. |
| Push / FCM | **Interface + injeção** | Idem; registro precisa ser testável. |
| Player de áudio | **Interface + injeção** | Superfície grande e com estado; é o ponto onde um fake destrava o teste do scheduler compartilhado. |
| Permissões | **Interface + injeção** | Fluxo assíncrono com resultado do usuário. |
| Background tasks | Nativo, sem abstração | WorkManager e BGTaskScheduler não têm denominador comum honesto. |
| Deep links | Nativo | Não existe no app hoje (só `appStateChange`); quando existir, é roteamento nativo. |
| Filesystem | **Interface + injeção** | Usado por áudio offline; precisa de fake. |
| Google Home | Módulo Android direto | Android-only por decisão arquitetural (ADR-036). O `commonMain` só conhece a interface de execução. |
| Home Assistant | Nada no dispositivo | Execução é server-side; o mobile só chama a API. |
| Bluetooth | Fora de escopo | Não existe no app atual. |
| Telemetria | **Interface + injeção** | OTel tem SDK Kotlin (JVM) e Swift; o `commonMain` só conhece a interface. |

O `GoogleHomePlugin.kt` (378 linhas) e o `CanonicalBrightness.kt` já existentes **migram praticamente sem alteração** — perdem apenas o invólucro de plugin Capacitor. É o único código do app que a migração aproveita integralmente.

---

## 10. Arquitetura do player (motivador nº 1)

O ponto mais delicado do plano, e o que mais justifica atenção.

### 10.1 A divisão

```
┌────────────────────── shared/commonMain ──────────────────────┐
│  buildVibeExecutionPlan(VibeSound[]) → VibeExecutionLayer[]    │
│  PlaybackScheduler: estado + plano + instante t                │
│                     → conjunto de comandos de transporte       │
│  Determinístico, sem I/O, sem timer, 100% testável             │
└───────────────────────────────┬────────────────────────────────┘
                                │  LayerCommand (start/stop/volume/seek)
                ┌───────────────┴───────────────┐
        AudioTransport (Android)        AudioTransport (iOS)
        Media3 / ExoPlayer              AVAudioEngine
        MediaSessionService             AVAudioSession
```

A regra: **o `shared` decide o que deveria estar tocando; a plataforma faz tocar.** O relógio e o áudio ficam na plataforma, porque precisam da thread de áudio e do serviço em foreground; a interpretação do plano fica compartilhada, porque é onde mora a complexidade real.

### 10.2 Por que isso importa

A semântica atual do `audio-player.service.ts` é sutil e cara de reproduzir: guarda de sobreposição no modo `interval`, pausa durante o intervalo de silêncio com retomada do tempo restante, teardown de callbacks para evitar ticks fantasma, foco de áudio, retomada após interrupção. São 1.887 linhas em grande parte dedicadas a *timing*, não a áudio.

Colocar essa lógica em um scheduler determinístico e compartilhado significa escrevê-la **uma vez**, com testes de tabela em `commonTest`, em vez de duas vezes com divergência garantida. É o argumento mais forte a favor de KMP neste projeto — mais forte, inclusive, do que compartilhar clientes de API.

### 10.3 Ganho concreto

Media3 e AVAudioEngine expõem controle de volume por nó, o que torna **fade-in e fade-out viáveis** — recurso hoje desativado por limitação do `@capgo/native-audio`, com os campos `fade_in_seconds`/`fade_out_seconds` já presentes no schema aguardando um runtime capaz de honrá-los.

---

## 11. Estratégia de migração

### 11.1 Opções

| Estratégia | Descrição | Risco |
| --- | --- | --- |
| **A. Big-bang em repo paralelo** | Construir o app novo até a paridade, depois trocar | Meses sem entregar; risco alto de abandono no meio |
| **B. Strangler dentro do app atual** | Adicionar o módulo KMP e telas Compose ao projeto Android do Capacitor, migrando tela a tela | App sempre publicável; convivência de duas stacks por um período |
| **C. Híbrido** | Provar o núcleo no app atual (Fase 1–2), depois seguir em repositório novo | Combina validação cedo com estrutura limpa |

**Recomendação: Opção C.** Um app Capacitor é um projeto Android comum: aceita módulo Gradle KMP e Activities Compose, e o projeto já tem o precedente de código nativo (`GoogleHomePlugin`). Isso permite provar a tese — inclusive o player nativo, que é o motivador nº 1 — **sem** um período longo sem entregar, e sem criar repositório antes de ter confiança na arquitetura.

Para uma pessoa só, com Cursor, esse é o fator decisivo: cada fase precisa terminar com algo instalável no aparelho.

### 11.2 Fases

Cada fase tem um critério de conclusão verificável e deixa o app funcionando.

---

**Fase 0 — Decisões arquiteturais**
Objetivo: fechar as questões do §15 e escrever os ADRs do §13.
Dependências: nenhuma.
Critério: ADRs em estado Accepted; questões de §15 respondidas.
Não iniciar antes: qualquer código.

**Fase 1 — Fundação KMP e prova do plano de execução**
Objetivo: módulo `shared` compilando dentro do projeto Android atual, com `buildVibeExecutionPlan` portado.
Componentes: Gradle/KMP, version catalog, kotlinx.serialization, kotlinx-datetime, teste de fronteira do `commonMain`.
Risco: baixo. É onde se aprende KMP sem pressão.
Critério: os testes Vitest de `player-engine` reproduzidos em `commonTest`, com os mesmos casos e resultados idênticos; APK ainda instala e funciona.
Testável: paridade do plano de execução entre TS e Kotlin.

**Fase 2 — Networking e autenticação**
Objetivo: Ktor client contra o staging, com Bearer do Firebase.
Dependências: Fase 1.
Componentes: Ktor, DTOs, `expect/actual` de Auth, secure storage.
Risco: médio — renovação de token e erro 401.
Critério: listar vibes reais do staging a partir do Kotlin, com token válido, e renovar após expiração.

**Fase 3 — Domínio e dados**
Objetivo: repositórios, SQLDelight, CSDM canônico, regras de recorrência.
Dependências: Fase 2.
Componentes: os ≈3.900 linhas de lógica pura identificados no §2.1, mais o schema vendorizado com teste de coerência.
Critério: testes portados verdes; guards de fronteira do CSDM reproduzidos em Kotlin.

**Fase 4 — Player nativo Android**
Objetivo: `PlaybackScheduler` compartilhado + transporte Media3 + foreground service + MediaSession.
Dependências: Fases 1 e 3.
Risco: **o mais alto do plano.** É a reescrita da parte mais sutil do app.
Critério: uma vibe multi-camada toca com paridade comportamental comprovada contra o app atual (loop, once, interval, pausa no intervalo, foco de áudio, background), verificada em aparelho real.
Não iniciar antes: Fase 3 completa — o scheduler depende do plano e dos modelos.

**Fase 5 — Corte do player**
Objetivo: o player nativo substitui o player Vue dentro do app atual, com o restante da UI ainda em WebView.
Dependências: Fase 4.
Risco: a ponte entre o estado nativo do player e o MiniPlayer em Vue é trabalho descartável.
Critério: usuário toca uma vibe pelo runtime nativo em build de staging, sem regressão.
Nota: é aqui que o motivador nº 1 é entregue, muito antes do fim da migração.

**Fase 6 — Repositório novo e UI Compose**
Objetivo: `ixora-mobile` criado; telas migradas por área, em ordem de valor: Vibes → Player → Sounds → Scenes/Devices → Schedules → Auth/Settings.
Dependências: Fase 5.
Critério por área: tela nativa com paridade funcional, coberta por Compose UI Test.

**Fase 7 — Google Home nativo**
Objetivo: o plugin Kotlin vira módulo Android, sem invólucro Capacitor.
Dependências: Fase 6 na área de Devices.
Critério: descoberta e execução funcionando; guards de escala canônica preservados.

**Fase 8 — Remoção do Capacitor**
Objetivo: eliminar Ionic, Vue, Capacitor e os 12 plugins.
Dependências: Fases 6 e 7 completas.
Critério: APK sem WebView; `applicationId` e chave de assinatura preservados.

**Fase 9 — Preparação de iOS (contínua, não uma fase final)**
Objetivo: manter o `commonMain` compilável para iOS.
Realidade: **sem Mac, isso não é verificável.** O teste de fronteira reduz o risco, mas não o elimina.
Critério possível hoje: nenhuma API JVM-only no `commonMain`, verificado por teste.

**Fase 10 — App iOS**
Bloqueada por hardware. Só começa com Mac, Xcode e conta Apple.

Testes e CI **não são fases** — são critério de conclusão de cada fase acima.

---

## 12. CI/CD e ambiente

**Hoje:** Android compila em Linux sem restrição; `./gradlew assembleDebug` já roda no ambiente atual. O `front_vibes` não tem pipeline de deploy — a distribuição é manual via Capacitor. Não há CI em nenhum dos quatro repositórios ([`quality-harness.md`](../../quality-harness.md)).

**Proposta mínima, coerente com o tamanho do time:**

- **GitHub Actions — Android:** em PR para `develop`, rodar `shared` (commonTest + androidUnitTest) e `assembleDebug`. É o primeiro CI real do ecossistema; introduzi-lo aqui é natural porque o projeto Gradle já tem tudo o que um runner precisa.
- **iOS:** impossível sem runner macOS. Adiar; quando existir Mac, avaliar `macos-latest`, que tem custo por minuto mais alto.
- **Ambientes:** manter `development` / `staging` / `production` como hoje, via build variants do Gradle (`buildConfigField`) em vez de arquivos `.env` do Vite.
- **Secrets:** hoje há credenciais de QA em `front_vibes/.env` local. Na migração, mover para `local.properties` (fora do versionamento) e GitHub Secrets no CI.
- **Assinatura:** ponto crítico — **preservar `app.ixora.ixora` e a chave de assinatura atual**. Sem isso, o app novo não atualiza o instalado e vira outro app na Play Store.
- **Versionamento:** manter Conventional Commits e Git Flow conforme [`git-flow.md`](../../standards/git-flow.md), que já governa os quatro repositórios.

---

## 13. ADRs recomendados

Apenas decisões com impacto arquitetural real. Numeração seguindo a sequência do projeto (a última aceita é a ADR-037).

| ADR | Assunto | Bloqueia implementação? |
| --- | --- | --- |
| **ADR-038** | KMP como camada compartilhada do mobile: o que vai, o que não vai e por quê | **Sim** |
| **ADR-039** | UI nativa (Compose + SwiftUI) sem Compose Multiplatform, e o custo aceito de reescrever a UI duas vezes | **Sim** |
| **ADR-040** | Arquitetura do player: plano e scheduler compartilhados, transporte nativo | **Sim** — condiciona a Fase 4 |
| **ADR-041** | Contrato de estado e interop Kotlin↔Swift: StateFlow, `Result` selado, SKIE | **Sim** |
| **ADR-042** | Estratégia de migração e destino do repositório (strangler + `ixora-mobile`) | **Sim** — altera `repo-responsibilities.md` |
| **ADR-043** | Persistência mobile: SQLDelight, DataStore e armazenamento seguro do token | Não — pode ser decidido na Fase 3 |
| **ADR-044** | Autenticação Firebase em KMP via `expect/actual` | Não — pode ser decidido na Fase 2 |

Não recomendo ADR para DI nem para testes: são escolhas reversíveis de baixo acoplamento, que cabem no próprio plano.

**Impacto documental fora dos ADRs:** `repo-responsibilities.md`, `architecture-map.md`, `contracts/README.md` (novo consumidor vendorizado) e `quality-harness.md` (novo baseline) precisam ser atualizados. A ADR-007 e a ADR-008 (execução device-side e contrato do plano) **continuam válidas** — a migração as reafirma, não as revoga.

---

## 14. Riscos e pontos de atenção

| # | Risco | Probabilidade | Impacto | Mitigação |
| --- | --- | --- | --- | --- |
| 1 | **Migração abandonada no meio**, deixando duas stacks vivas | Alta | Alto | Estratégia strangler: toda fase termina instalável. Nunca permitir um período longo sem entrega. |
| 2 | **Regressão no player** — a semântica de `interval` e pausa é sutil | Alta | Alto | Scheduler determinístico com testes de tabela; comparação lado a lado com o app atual em aparelho antes do corte. |
| 3 | **iOS revela problemas em série na primeira compilação** | Alta | Médio | Assumido explicitamente. Teste de fronteira reduz, não elimina. Não escrever muito `iosMain` "no escuro". |
| 4 | **Retorno do KMP não chega** se o Mac não vier | Média | Médio | Recomendação já entrega valor só com Android; o KMP é custo marginal, não aposta. |
| 5 | **Perda da rede de testes** — 515 testes Vitest e todos os specs WDIO do WebView | Certa | Alto | Portar testes de lógica pura como paridade nomeada; refazer E2E com seletores nativos. |
| 6 | **Quebra de atualização na Play Store** por `applicationId` ou chave diferente | Baixa | Crítico | Tratar como critério de aceite da Fase 8. |
| 7 | **Perda de dados de usuários** — áudio offline e espelho de schedules | Média | Médio | Decidir migração ou reset consciente (§15, questão 6). |
| 8 | **Dependência de SKIE**, ferramenta comunitária, na fronteira Swift | Média | Médio | Só afeta a plataforma iOS; substituível por wrappers manuais. |
| 9 | **Curva de aprendizado simultânea** — KMP, Compose, Media3, Gradle, e depois SwiftUI | Alta | Médio | A ordem das fases é deliberadamente crescente em dificuldade. |
| 10 | **Escopo do app cresce durante a migração** | Média | Alto | Congelar features novas em `front_vibes` a partir da Fase 5, ou aceitar implementá-las duas vezes. |

Risco 1 é o dominante. Toda a estrutura de fases existe para contê-lo.

---

## 15. Questões a decidir antes de começar

1. **O app continua recebendo features durante a migração?** Se sim, cada feature nova custa duas implementações a partir da Fase 5.
2. **Existe prazo ou é projeto de fundo?** Muda o tamanho das fatias, não a ordem.
3. **`minSdk` alvo do app novo.** Media3 e Compose permitem subir o piso; vale verificar a base instalada antes.
4. **Repositório novo (`ixora-mobile`) confirmado?** Altera `repo-responsibilities.md` e o contrato de 4 repositórios descrito no `CLAUDE.md`.
5. **Telemetria OTel entra desde o começo ou depois?** São 541 linhas hoje; reimplementar cedo atrasa, e tarde cria ponto cego.
6. **Dados existentes no aparelho:** os áudios offline (`Directory.Data` + manifesto em Preferences) e o espelho SQLite de schedules migram, ou aceita-se que o usuário rebaixe e re-sincronize na primeira abertura do app novo?
7. **Fade entra no escopo do player novo?** É o ganho mais visível do motivador nº 1, mas amplia a Fase 4. Recomendo entregar a Fase 4 com paridade e adicionar fade logo depois, como feature própria.
8. **Design system:** portar os tokens atuais (tema claro, `variables.css`) para um `Theme` Compose, ou redesenhar aproveitando a mudança?
9. **O que acontece com `front_vibes`** depois da Fase 8: congelado, arquivado ou mantido como referência viva?

---

## 16. Backlog inicial de tarefas arquiteturais

Fatias pequenas o bastante para execução assistida, cada uma com resultado verificável. Fases 0 e 1 apenas — o backlog seguinte se escreve depois da Fase 1, com aprendizado real.

| # | Tarefa | Fase | Saída verificável |
| --- | --- | --- | --- |
| K01 | Responder as 9 questões do §15 | 0 | Decisões registradas |
| K02 | ADR-038 — KMP como camada compartilhada | 0 | ADR Accepted |
| K03 | ADR-039 — UI nativa Compose + SwiftUI | 0 | ADR Accepted |
| K04 | ADR-042 — Estratégia de migração e repositório | 0 | ADR Accepted + `repo-responsibilities.md` atualizado |
| K05 | ADR-040 — Arquitetura do player | 0 | ADR Accepted |
| K06 | ADR-041 — Contrato de estado e interop | 0 | ADR Accepted |
| K07 | Adicionar módulo `shared` (KMP) ao projeto Android atual, com version catalog e targets android + iOS declarados | 1 | `./gradlew :shared:build` verde; APK do app atual continua instalando |
| K08 | Teste de fronteira do `commonMain` (sem API JVM-only nem Android-only), com sentinela que prova a falha | 1 | Teste verde + sentinela detectando violação deliberada |
| K09 | Portar modelos `VibeSound` e `VibeExecutionLayer` com kotlinx.serialization | 1 | Serialização redonda testada |
| K10 | Portar `buildVibeExecutionPlan` para `commonMain` | 1 | Função implementada |
| K11 | Portar os testes de `player-engine` para `commonTest`, preservando nomes e casos | 1 | Paridade auditável caso a caso contra o Vitest |
| K12 | Documentar o resultado da Fase 1 e revisar este plano com o aprendizado | 1 | Plano atualizado antes da Fase 2 |

K12 não é burocracia: a Fase 1 é a primeira vez que o projeto encosta em KMP de verdade, e a maioria das estimativas deste documento merece revisão depois dela.

---

## 17. Relação com outros documentos

- [ADR-007 — Execution plan as mobile playback runtime contract](../../decisions/ADR-007-execution-plan-runtime-contract.md) — o contrato do plano de execução é **reafirmado**: continua device-side e o `back_vibes` segue sem engine de playback. Mas a ADR nomeia explicitamente `player-engine.service.ts`, `player.store` e `audio-player.service` como a implementação vigente; quando a Fase 5 concluir, ela precisa de um addendum apontando para o `PlaybackScheduler` em Kotlin. A decisão não muda, a implementação citada sim.
- [ADR-008 — NativeAudio limitations over unstable JS-driven DSP](../../decisions/ADR-008-nativeaudio-limitations-over-unstable-dsp.md) — **esta é a única ADR que a migração efetivamente reabre.** Ela removeu fades em runtime porque o `@capgo/native-audio` e a ponte Capacitor não sustentavam DSP confiável. Com Media3 e AVAudioEngine essa premissa deixa de valer, e a proibição precisa ser revisitada — provavelmente por uma ADR nova, não por revogação silenciosa. Ver §15, questão 7.
- [ADR-036](../../decisions/ADR-036-google-home-execution-model.md) — modelo de execução do Google Home: o SDK segue Android-only; o iOS nunca terá Google Home.
- [ADR-037](../../decisions/ADR-037-canonical-smart-home-device-model.md) e [CSDM](../../specs/smart-home/canonical-device-model.md) — o modelo canônico migra para Kotlin com os mesmos guards.
- [`playback-runtime.md`](../audio/playback-runtime.md) e [`audio-engine-fade-limitations.md`](../audio/audio-engine-fade-limitations.md) — descrevem o runtime que este plano substitui; devem ser marcados como histórico quando a Fase 5 concluir.
- [`contracts/README.md`](../../../contracts/README.md) — o app novo vira consumidor vendorizado do schema canônico.
- [`repo-responsibilities.md`](../repo-responsibilities.md) — precisa refletir o novo repositório, se a Opção A do §5.3 for confirmada.
