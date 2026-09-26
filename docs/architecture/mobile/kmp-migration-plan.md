# Plano de migração do front_vibes para Kotlin Multiplatform

**Status:** Direção aprovada pelo PO em 2026-09-23 (§0). Fase 1 concluída em 2026-09-25 (K07–K11). O restante do documento é o plano de execução dessa direção; nenhuma implementação é autorizada por este documento.
**Data:** 2026-09-23 · **Revisado:** 2026-09-23 (decisões definitivas do PO) · 2026-09-25 (K12 — resultado da Fase 1) · 2026-09-25 (D6 — visual novo, Design System v1) · 2026-09-26 (D7 — categorias de vibe)
**Escopo:** camada mobile do Ixora. Não altera `back_vibes`, `ixora-admin` nem contratos de API, **exceto a mudança aditiva de categorias de vibe da D7** (§0), que tem cards próprios (CAT-01 a CAT-04) e spec própria.
**Premissas confirmadas com o PO:** iOS depende da compra de um Mac (sem data); os motivadores são qualidade do player de áudio, experiência nativa de UI e consolidação em Kotlin; execução solo com apoio do Cursor.

---

## 0. Decisões definitivas do PO (2026-09-23)

Estas decisões são **posteriores ao corpo original deste documento e prevalecem sobre ele**. Foram tomadas pelo PO e não devem ser reabertas sem evidência técnica concreta.

| # | Decisão | Efeito neste plano |
| --- | --- | --- |
| **D1** | O app novo é desenvolvido em **`git@github.com:lucasbrito90/ixora-app.git`** (repositório já criado, vazio). `front_vibes` segue como referência e histórico. | Confirma a Opção A do §5.3 e fixa o nome. A recomendação anterior de `ixora-mobile` está descartada. |
| **D2** | **Feature freeze** no `front_vibes` durante toda a migração. Nenhuma feature nova; o objetivo é reproduzir o comportamento existente. | Resolve a questão 1 do §15 e muda a estratégia de migração (§11). |
| **D3** | **Sem migração de dados locais.** Áudio offline, cache de playback e o espelho SQLite são reconstruídos por download ou sincronização. | Resolve a questão 6 do §15 e remove o risco 7 do §14. |
| **D4** | **Fade deve ser recuperado** na nova arquitetura, como parte do K05 / ADR-040. | Resolve a questão 7 do §15 e amplia deliberadamente o escopo do player. Ver §10.4 para o que isso significa de fato. |
| **D5** | **Android primeiro**, com o `shared` nascendo KMP e o target iOS declarado. Sem Compose Multiplatform. | Já era a recomendação central do §1.2; agora é decisão. |
| **D6** | **Visual novo.** O PO decidiu (2026-09-25) uma nova identidade visual, moderna e relaxante, inspirada no clima, nas formas e na tipografia de um kit de referência licenciado (Sleepie), com paleta, fontes e voz próprias do Ixora e sem reproduzir telas, ilustrações nem assets do kit. Resultado: **Design System v1 do Ixora**, aprovado em 2026-09-25 (tokens em claro e escuro, brand book, componentes, ícones Lucide, guia de movimento e telas-chave: Home, Player, My Vibes, Settings e autenticação). | Substitui a paridade visual (questão 8, §16.14.8 e critérios das Fases 5 e 6). **D2 continua valendo para comportamento e funcionalidade**: nenhuma feature ou tela nova além das que o `front_vibes` já tem. Detalhe em §16.14 e na addendum da ADR-039. |
| **D7** | **Categorias de vibe (exceção pontual à D2).** O PO decidiu (2026-09-26) manter no Home os chips de categoria do Design System e adaptar o backend: uma vibe pode ter **várias categorias**, escolhidas de um **catálogo fixo definido pelo admin**. O admin atribui categorias aos presets; a vibe do usuário **herda as categorias no import do preset** (cópia única, ADR-003/005); vibe criada do zero fica **sem categoria** e aparece apenas em "Tudo". | **Única exceção à D2**: é funcionalidade nova em relação ao `front_vibes`, que **não recebe** a mudança (continua congelado; os clientes ignoram campos desconhecidos, então a mudança é aditiva e não o quebra). **Não abre precedente:** qualquer outro item novo continua exigindo decisão própria do PO. Sequência obrigatória: contrato e spec (CAT-01) → `back_vibes` (CAT-02) → `ixora-admin` (CAT-03) → `ixora-app` (CAT-04); o chip do Home só é implementado depois do contrato. Substitui a proposta de "remover os chips do Home" em `reconciliacao-d2.md` do Design System (item 2). |

### 0.1 Questões do §15 ainda em aberto

Fechadas por estas decisões: 1, 4, 6, 7 e 9. A questão 8 foi fechada por §16.14 (portar os tokens, sem redesenho) e **reaberta e refeita em 2026-09-25 pela D6 (visual novo)** e a questão 3 foi fechada em 2026-09-24: **`minSdk` 24**. **Permanecem em aberto após a Fase 1:** 2 (prazo ou projeto de fundo) e 5 (em que fase entra a instrumentação de telemetria — o *se* foi fechado por §16.13). Nenhuma das duas bloqueia a Fase 2.

Os requisitos transversais do projeto (multilinguagem, acessibilidade, deep links, armazenamento seguro e outros) estão consolidados em **§16**.

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
| Testes Vitest | 48 | 9.064 | 515 testes. Medido em 2026-09-25 com `node node_modules/vitest/vitest.mjs run` (`npx vitest` não funciona nesta máquina): 48 arquivos (45 `*.test.ts` + 3 `*.spec.ts` dentro de `src/`; `tests/e2e`, `tests/smoke` e `qa-android-native/` excluídos pelo `vite.config.ts`), todos passando. |
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
| Telemetria OTel | SDK por plataforma atrás de interface compartilhada — ver §16.13, fonte de verdade sobre observabilidade. |

**REMOVE/REPLACE — sai do projeto**

Capacitor e seus 12 plugins (`@capacitor/*`, `@capacitor-community/sqlite`, `@capacitor-firebase/messaging`, `@capawesome-team/capacitor-android-foreground-service`, `@capgo/native-audio`, `@codetrix-studio/capacitor-google-auth`), Ionic, Vue, Pinia, vue-router, Vite, `patch-package`, o fallback `HTMLAudioElement` para web, e os testes Vitest/Playwright/Cypress que cobrem componentes Vue.

**MIGRATION/REFACTOR — aproveitamento parcial**

- Os testes Vitest de lógica pura (`utils/`, `canonical-capabilities`) têm equivalente direto em `commonTest`. Devem ser **portados caso a caso como paridade**, não reescritos do zero: são a rede de segurança da migração.

  **Correção registrada em K12 (2026-09-25):** `player-engine` **não possui testes Vitest**. O K10 verificou o repositório `front_vibes` @ `1cf858e` e constatou que `player-engine.service.ts` não tem arquivo `.test.ts` ou `.spec.ts` correspondente — a função `buildVibeExecutionPlan` nunca foi coberta por Vitest. A paridade em `commonTest` foi estabelecida por golden-master de oracle externo (esbuild + Node) em K10 (17 casos manuais) e expandida em K11 (384 combinações de 1 som, 30 planos multi-som com PRNG seed 20260925, 3713 entradas de `formatDuration` 0..3700). A rede de segurança existe; sua origem não é um port de Vitest.
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
| Analytics / Telemetria | ○ | ● | ● | Interface compartilhada, SDK nativo. Critérios e escopo em §16.13. |
| Logging | ● | ○ | ○ | Abstração barata; saída por plataforma. |
| Tratamento de erros | ● | ○ | ○ | Tipos de erro de domínio compartilhados — ver §8. |
| UI | — | ● | ● | Decisão explícita do PO: sem Compose Multiplatform. A **linguagem visual** é comum e a implementação é nativa — detalhamento em §16.14. |
| Design language (tokens, princípios) | conceito | conceito | conceito | Regra única, mas **não é código no `shared`**. Sem módulo `design-system` KMP (§16.14.4). |
| Theme, componentes e telas | — | ● | ● | Compose e SwiftUI implementam separadamente a mesma linguagem (§16.14.6). |

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

**Resultado da Fase 1 (K12, 2026-09-25):** a Opção A foi executada e validada em K07–K11. O módulo `shared` compila para `commonMain`, `androidHostTest` e os dois targets iOS (`iosArm64`, `iosSimulatorArm64`) no Windows, com Kotlin 2.3.20 / AGP 8.13.0 / Gradle 8.14.3 / JDK 21 (compilação para klib; link e execução de testes iOS exigem Mac). O `CommonMainBoundaryTest` (rejeita `java.*`, `javax.*`, `android.*`, `androidx.*`; inclui sentinelas de detecção e de não-detecção, 20 testes) verde em `androidHostTest`. Nenhuma pressão surgiu para dividir módulos durante a Fase 1; a recomendação de módulo único permanece válida para a Fase 2.

### 5.2 Estrutura de diretórios recomendada

```
ixora-app/
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
│       ├── ui/
│       │   ├── theme/                 # Colors · Typography · Dimensions · IxoraTheme (§16.14.3)
│       │   ├── components/            # componentes Compose do Design System
│       │   └── screens/               # telas por feature
│       ├── player/                    # Media3 + MediaSessionService
│       ├── googlehome/                # SDK Google Home (migrado do plugin atual)
│       ├── push/
│       └── platform/                  # actuals que precisam de Context
│
├── iosApp/                            # esqueleto Xcode, inerte até o Mac
│   └── UI/                            # Theme · Components · Screens — simétrico ao Android
│
└── contracts/smart-home/capability.v1.schema.json   # cópia vendorizada
```

### 5.3 Repositório: novo ou o mesmo?

| Opção | A favor | Contra |
| --- | --- | --- |
| **A. Novo repositório** | Raiz Gradle limpa; os dois apps coexistem sem conflito de tooling; `front_vibes` preservado como referência | Quinto repositório no workspace; CI e docs novos; exige atualizar `repo-responsibilities.md` |
| **B. Dentro do `front_vibes`** | Mantém histórico, Git Flow e evidências de QA; um lugar só | Conflito de raiz (npm/Vite vs. Gradle); o `android/` gerado pelo Capacitor colide com `androidApp/`; meses com duas stacks na mesma árvore |

**Decidido (D1): Opção A — repositório `ixora-app`** (`git@github.com:lucasbrito90/ixora-app.git`), já criado e vazio. Todo o trabalho a partir do K07 acontece nele, inclusive a Fase 1 — a variante anterior, de começar dentro do `front_vibes`, foi descartada junto com a estratégia strangler (§11).

O workspace passa de quatro para cinco repositórios. `repo-responsibilities.md`, `architecture-map.md` e o `CLAUDE.md` da raiz precisam refletir isso; o K04 (ADR-042) é o lugar certo para essa atualização.

`front_vibes` nunca é deletado; vira repositório de referência em feature freeze (D2), coerente com a política do projeto de não apagar histórico.

---

## 6. Stack tecnológica

Cada escolha abaixo tem alternativa documentada. Nenhuma foi feita por popularidade.

**Versões fixadas na Fase 1 (K07, 2026-09-25)** — registradas aqui como âncora para as Fases seguintes:

| Componente | Versão | Nota |
| --- | --- | --- |
| Kotlin | 2.3.20 | Plugin `org.jetbrains.kotlin.multiplatform` |
| AGP | 8.13.0 | Plugin `com.android.kotlin.multiplatform.library` |
| Gradle (wrapper) | 8.14.3 | |
| JDK (compilação) | 21 | |
| `kotlinx-serialization-json` | 1.11.0 | |
| `org.jetbrains.kotlin.plugin.serialization` | 2.3.20 | Plugin do compilador; versão igual à do Kotlin |

O plugin AGP usado é `com.android.kotlin.multiplatform.library` (não o par `com.android.library` + `androidTarget()` descrito na documentação mais antiga do KMP). Esse plugin expõe o target Android como `android { }` dentro do bloco `kotlin { }`, não como `androidTarget()`. Ver addendum do ADR-038, ponto 3.

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

Ambos suportam **fade real** — o recurso que a stack atual abandonou por limitação do plugin, documentado em [`audio-engine-fade-limitations.md`](../audio/audio-engine-fade-limitations.md) e decidido na [ADR-008](../../decisions/ADR-008-nativeaudio-limitations-over-unstable-dsp.md). Recuperar fade é o ganho mais concreto e demonstrável do motivador nº 1, mas exige reabrir aquela decisão de forma explícita (§18).

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
| Telemetria | **Interface + injeção** | OTel tem SDK Kotlin (JVM) e Swift, e nenhum viável em Kotlin/Native; o `commonMain` só conhece a interface. Fonte de verdade: §16.13. |

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

### 10.4 Fade (D4) — o que existe hoje, medido

A decisão D4 determina recuperar o fade. Antes de planejar o K05 é preciso registrar um fato verificado no código, porque ele muda a natureza do trabalho:

**Não existe comportamento de fade em runtime no `front_vibes` para ser reproduzido.** O que existe é o contrato completo, honrado em todas as camadas exceto no transporte de áudio:

| Camada | Estado | Evidência |
| --- | --- | --- |
| Banco e API | Persiste e expõe os campos | `vibe_sounds.fade_in_seconds` / `fade_out_seconds`; `VibeSoundResource`, `AttachVibeSoundRequest`, `UpdateVibeSoundRequest` |
| Plano de execução | Calcula e propaga | `player-engine.service.ts:168-169` mapeia para `fadeInSeconds` / `fadeOutSeconds` |
| UI | **Anuncia ao usuário** | `VibePlayerPage.vue:240-244` e `VibeSoundsPage.vue:279-280` exibem "fade in Ns" / "fade↓ Ns" |
| Painel de debug | Declara a lacuna | `PlayerDebugPanel.vue:142` imprime o valor seguido de "(stored but ignored)" |
| Transporte | **Ignora** | `audio-player.service.ts:15` — "fadeIn/fadeOut are intentionally NOT applied at runtime"; `native-audio.engine.ts:70` passa `fade: false` |

Duas consequências práticas:

1. **O K05 precisa especificar a semântica do fade, não copiá-la.** Não há fonte de verdade comportamental. A especificação precisa decidir, no mínimo: curva (linear ou logarítmica — para volume percebido, logarítmica), se o fade-out é ancorado em `endsAtSeconds` ou no fim do arquivo, comportamento em `interval` (fade por tick ou só nas bordas da camada), interação com pausa e retomada, e comportamento na borda do loop. Essas escolhas são novas por necessidade, não por vontade — e a instrução "não inventar um comportamento de fade diferente" deve ser lida como "não extrapolar além do que os campos já existentes descrevem".

2. **Recuperar o fade não viola o feature freeze (D2).** A UI já promete fade ao usuário e o áudio não entrega: é uma lacuna de implementação de um contrato existente, não uma feature nova. O freeze continua valendo para qualquer coisa além disso.

---

## 11. Estratégia de migração

### 11.1 Opções

| Estratégia | Descrição | Risco |
| --- | --- | --- |
| **A. Big-bang em repo paralelo** | Construir o app novo até a paridade, depois trocar | Meses sem entregar; risco alto de abandono no meio |
| **B. Strangler dentro do app atual** | Adicionar o módulo KMP e telas Compose ao projeto Android do Capacitor, migrando tela a tela | App sempre publicável; convivência de duas stacks por um período |
| **C. Híbrido** | Provar o núcleo no app atual (Fase 1–2), depois seguir em repositório novo | Combina validação cedo com estrutura limpa |

**Decidido (D1 + D2): Opção A — construção paralela em `ixora-app`.** As opções B e C ficam descartadas.

A recomendação original deste documento era a Opção C, e o argumento era um só: evitar um período longo sem entregar. **O feature freeze (D2) remove esse argumento** — com o `front_vibes` congelado e publicável como está, não há pressão de entrega durante a reconstrução, e a complexidade de manter duas stacks no mesmo APK deixa de se pagar. A combinação D1 + D2 + D3 forma uma estratégia coerente de *congelar e reconstruir*.

**Consequência a aceitar conscientemente:** o ganho do motivador nº 1 (player) não chega mais cedo, como chegaria no strangler. Ele chega quando o app novo estiver instalável. Em troca, o caminho é mais simples e não gera trabalho descartável de ponte entre o player nativo e a UI Vue.

**Mitigação obrigatória, já que o strangler não protege mais contra abandono:** o `ixora-app` precisa estar **instalável no aparelho a partir da Fase 4**, ainda que com UI mínima. Uma tela que lista vibes e toca uma delas já serve. O critério é que cada fase termine com algo demonstrável rodando no celular, não com testes verdes apenas.

### 11.2 Fases

Cada fase tem um critério de conclusão verificável e deixa o app funcionando.

---

**Fase 0 — Decisões arquiteturais**
Objetivo: fechar as questões do §15 e escrever os ADRs do §13.
Dependências: nenhuma.
Critério: ADRs em estado Accepted; questões de §15 respondidas.
Não iniciar antes: qualquer código.

**Fase 1 — Fundação KMP e prova do plano de execução**
Objetivo: repositório `ixora-app` inicializado e módulo `shared` compilando, com `buildVibeExecutionPlan` portado.
Componentes: Gradle/KMP, version catalog, kotlinx.serialization, kotlinx-datetime, teste de fronteira do `commonMain`, Git Flow do novo repositório.
Risco: baixo. É onde se aprende KMP sem pressão.
Critério original: ~~os testes Vitest de `player-engine` reproduzidos em `commonTest`, com os mesmos casos e resultados idênticos.~~
Critério corrigido (K12, 2026-09-25): **paridade de comportamento do `player-engine` provada por golden-master de oracle externo em `commonTest`**, com os mesmos inputs e outputs verificados contra o TypeScript de referência (`front_vibes` @ `1cf858e`). A formulação original estava incorreta: não existem testes Vitest para `player-engine` a reproduzir (ver §2.2 correção).
Testável: paridade do plano de execução entre TS e Kotlin.

✅ **Concluído em 2026-09-25 (K07–K11).** Saídas verificáveis produzidas:
- K07: `./gradlew :shared:build` verde; targets iOS declarados; `compileTestKotlinIosArm64` executa no Windows; `compileKotlinIosArm64` fica `NO-SOURCE` até haver código em `commonMain` (K09) e passa a executar de fato a partir daí. Git Flow configurado.
- K08: `CommonMainBoundaryTest` (rejeita `java.*`, `javax.*`, `android.*`, `androidx.*`; inclui sentinelas de detecção e de não-detecção, 20 testes) verde em `androidHostTest`.
- K09: `VibeSound` (15 campos, `@Serializable`), `PlayMode` (enum `@Serializable`) e `VibeExecutionLayer` em `commonMain`; fixture de staging real capturada (`back_vibes` @ `73f23d1c`); 5 testes de serialização em `commonTest`.
- K10: `buildVibeExecutionPlan`, `formatDuration` e `buildSummary` em `commonMain`; 17 casos manuais de golden-master em `commonTest`; prova de mutação.
- K11: 384 combinações de 1 som (3×4×4×4×2 matrix), 30 planos multi-som (PRNG seed 20260925), 3713 entradas de `formatDuration` (0..3700 + 12 pontos de borda); seção "Player engine parity" no `README.md` do `ixora-app`.

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
Objetivo: `PlaybackScheduler` compartilhado + transporte Media3 + foreground service + MediaSession + **fade (D4)**.
Dependências: Fases 1 e 3, e a ADR-040 aceita (K05) com a semântica de fade especificada.
Risco: **o mais alto do plano.** É a reescrita da parte mais sutil do app, agora com um comportamento novo a definir (§10.4).
Critério: uma vibe multi-camada toca com paridade comportamental comprovada contra o `front_vibes` congelado (loop, once, interval, pausa no intervalo, foco de áudio, background), verificada no mesmo aparelho; fade aplicado conforme a especificação da ADR-040.
Não iniciar antes: Fase 3 completa — o scheduler depende do plano e dos modelos.

**Fase 5 — Shell instalável**
Objetivo: o `ixora-app` vira um APK instalável e demonstrável: login, lista de vibes e reprodução. UI mínima, sem polimento.
Dependências: Fase 4.
Critério: instalar no aparelho, autenticar contra o staging, tocar uma vibe do início ao fim. Visual: o shell usa o tema do Design System v1 (`Colors.kt`, `Typography.kt`, `Dimensions.kt`, `IxoraTheme.kt`, com fontes embutidas como recursos do app) e confere com o design aprovado nas telas de autenticação, Home e Player.
Razão de existir: é a mitigação do risco nº 1. Sem o strangler, esta é a primeira prova concreta de que a reconstrução funciona — e o ponto a partir do qual todas as fases seguintes terminam com algo rodando no celular.

**Fase 6 — UI Compose por área**
Objetivo: telas migradas em ordem de valor: Vibes → Player → Sounds → Scenes/Devices → Schedules → Auth/Settings.
Dependências: Fase 5.
Critério por área: tela nativa com paridade **funcional** contra o `front_vibes` e **visual conforme o design aprovado** (Design System v1 e telas-chave), coberta por Compose UI Test. Tela sem desenho aprovado é desenhada com os componentes e tokens do Design System e aprovada pelo PO antes de implementar.
Escopo: reproduzir o comportamento existente (D2). O visual segue o design aprovado (D6); nenhuma feature ou tela nova além das existentes.

**Fase 7 — Google Home nativo**
Objetivo: o `GoogleHomePlugin.kt` vira módulo Android direto, sem invólucro Capacitor.
Dependências: Fase 6 na área de Devices.
Critério: descoberta e execução funcionando; guards de escala canônica do CSDM preservados.

**Fase 8 — Corte e descomissionamento**
Objetivo: o `ixora-app` substitui o `front_vibes` como aplicativo distribuído.
Dependências: Fases 6 e 7 completas, com paridade funcional verificada área a área.
Critério: **`applicationId` `app.ixora.ixora` e a mesma chave de assinatura**, sem o que o app novo não atualiza o instalado; `front_vibes` marcado como arquivado/referência, nunca deletado.
Nota: não há "remoção do Capacitor" a fazer — o Capacitor nunca existiu no `ixora-app`. O que há é a aposentadoria de um repositório inteiro.

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
| **ADR-039** | UI nativa (Compose + SwiftUI) sem Compose Multiplatform, o custo aceito de reescrever a UI duas vezes, **e a estratégia de Design System de §16.14** (linguagem comum, implementação nativa, sem módulo `design-system`) | **Sim** |
| **ADR-040** | Arquitetura do player: plano e scheduler compartilhados, transporte nativo | **Sim** — condiciona a Fase 4 |
| **ADR-041** | Contrato de estado e interop Kotlin↔Swift: StateFlow, `Result` selado, SKIE | **Sim** |
| **ADR-042** | Estratégia de migração e destino do repositório (construção paralela em `ixora-app`, feature freeze do `front_vibes`) | **Sim** — altera `repo-responsibilities.md`, `architecture-map.md` e o `CLAUDE.md` da raiz |
| **ADR-043** | Persistência mobile: SQLDelight, DataStore e armazenamento seguro do token | Não — pode ser decidido na Fase 3 |
| **ADR-044** | Autenticação Firebase em KMP via `expect/actual` | Não — pode ser decidido na Fase 2 |

Não recomendo ADR para DI nem para testes: são escolhas reversíveis de baixo acoplamento, que cabem no próprio plano. **Nem para o Design System:** ele não é uma decisão independente da ADR-039 — decidir "UI nativa nas duas plataformas" e "linguagem visual única com implementação separada" é a mesma decisão vista de dois ângulos. Separá-las criaria duas ADRs que precisariam ser lidas juntas para fazer sentido.

**Impacto documental fora dos ADRs:** `repo-responsibilities.md`, `architecture-map.md`, `contracts/README.md` (novo consumidor vendorizado) e `quality-harness.md` (novo baseline) precisam ser atualizados. A ADR-007 e a ADR-008 (execução device-side e contrato do plano) **continuam válidas** — a migração as reafirma, não as revoga.

---

## 14. Riscos e pontos de atenção

| # | Risco | Probabilidade | Impacto | Mitigação |
| --- | --- | --- | --- | --- |
| 1 | **Migração abandonada no meio**, deixando o `front_vibes` congelado e o `ixora-app` incompleto | Alta | Alto | Com a construção paralela (D1) o strangler não protege mais. Mitigação: `ixora-app` instalável no aparelho desde a Fase 4, ainda que com UI mínima; cada fase termina com algo demonstrável no celular. |
| 2 | **Regressão no player** — a semântica de `interval` e pausa é sutil, e o fade (D4) não tem comportamento de origem para copiar (§10.4) | Alta | Alto | Scheduler determinístico com testes de tabela; comparação lado a lado com o `front_vibes` congelado, no mesmo aparelho, antes de considerar a Fase 4 concluída. |
| 3 | **iOS revela problemas em série na primeira compilação** | Alta | Médio | Assumido explicitamente. Teste de fronteira reduz, não elimina. Não escrever muito `iosMain` "no escuro". Parcialmente mitigado desde o K09: `compileKotlinIosArm64` executa no Windows e rejeita `java.*`/`android.*` em `commonMain` (ver addendum da ADR-038). Continuam não verificados: link do framework e qualquer código Swift/iOS. |
| 4 | **Retorno do KMP não chega** se o Mac não vier | Média | Médio | Recomendação já entrega valor só com Android; o KMP é custo marginal, não aposta. |
| 5 | **Perda da rede de testes** — 515 testes Vitest (48 arquivos, confirmado em 2026-09-25) e todos os specs WDIO do WebView | Certa | Alto | Paridade de lógica pura em `commonTest` como golden-master nomeado (player-engine já concluído na Fase 1 — K10/K11); demais `utils/` e `canonical-capabilities` portados na Fase 3. E2E refeito com seletores nativos. A perda dos testes Vitest é gerenciada, não eliminada — a rede de segurança é reconstruída gradualmente pelas fases. |
| 6 | **Quebra de atualização na Play Store** por `applicationId` ou chave diferente | Baixa | Crítico | Tratar como critério de aceite da Fase 8. |
| 7 | ~~Perda de dados de usuários~~ — **eliminado por D3** | — | — | Reset consciente decidido: áudio offline e espelho de schedules são reconstruídos por download e sincronização. |
| 8 | **Dependência de SKIE**, ferramenta comunitária, na fronteira Swift | Média | Médio | Só afeta a plataforma iOS; substituível por wrappers manuais. |
| 9 | **Curva de aprendizado simultânea** — KMP, Compose, Media3, Gradle, e depois SwiftUI | Alta | Médio | A ordem das fases é deliberadamente crescente em dificuldade. |
| 10 | **Escopo do app cresce durante a migração** | Média | Alto | Congelar features novas em `front_vibes` a partir da Fase 5, ou aceitar implementá-las duas vezes. |

Risco 1 é o dominante. Toda a estrutura de fases existe para contê-lo.

---

## 15. Questões a decidir antes de começar

1. ~~O app continua recebendo features durante a migração?~~ **Fechada por D2** — feature freeze durante toda a migração.
2. **Existe prazo ou é projeto de fundo?** Muda o tamanho das fatias, não a ordem. *(aberta — não bloqueia a Fase 2; PO decide antes do primeiro card da Fase 2)*
3. ~~`minSdk` alvo do app novo?~~ **Fechada em 2026-09-24 pelo PO: `minSdk` 24**, mantendo o piso atual do `front_vibes` (`android/variables.gradle`: `minSdkVersion 24`, `compileSdkVersion 36`, `targetSdkVersion 36`).

   O raciocínio, porque a conclusão não é a óbvia. **Não há base instalada a preservar** — o aplicativo nunca foi publicado, o que é a mesma premissa que sustenta o gate de keystore da ADR-042 Decisão 6. Logo, a pergunta não é quantos aparelhos se perde, e sim quanto código de compatibilidade se evita.

   Medido no código atual, existem exatamente duas ramificações por nível de API: o canal de notificação obrigatório antes do `startForegroundService` em **API 26+** (`backgroundAudio.service.ts:119`), e o SDK do Google Home, que exige **API 29** e se recusa a operar abaixo disso (`GoogleHomePlugin.kt:55-56`, `:367-368`). Nem Media3 nem Compose exigem mais do que 21.

   Portanto o único degrau que removeria alguma coisa é **26**, não 28 — e o que ele remove é uma ramificação de uma linha. Subir o piso não destrava nenhuma capacidade, e manter 24 preserva paridade com o `front_vibes`, o que facilita a comparação de comportamento da Fase 6. Se um dia houver motivo para subir, 26 é o degrau que paga; 28 não acrescenta nada sobre 26 para este aplicativo.
4. ~~Repositório novo confirmado?~~ **Fechada por D1** — `ixora-app`, já criado.
5. **Telemetria OTel: em que fase entra a instrumentação mínima?** §16.13 já decidiu que a nova arquitetura preserva e se integra ao OTel/Grafana/Loki/Tempo existentes — o *se* está fechado. Resta o *quando*: reimplementar cedo atrasa, e tarde cria ponto cego. *(aberta — decidir até o início da Fase 2; PO decide)*
6. ~~Dados existentes no aparelho migram?~~ **Fechada por D3** — sem migração; reconstrução por download e sincronização.
7. ~~Fade entra no escopo do player novo?~~ **Fechada por D4** — entra, como parte do K05 / ADR-040. Ver §10.4: o trabalho é especificar a semântica, não copiá-la.
8. ~~Design system: portar os tokens atuais ou redesenhar?~~ **Fechada por §16.14** — portar. **Refeita em 2026-09-25 pela D6: redesenhar (visual novo, Design System v1).** O texto seguinte é o histórico da primeira resposta. A linguagem visual existente (tokens do Figma, tema `system`/`light`/`dark`) é reproduzida como paridade; redesenho é mudança de produto e exige decisão própria do PO, fora de D2. A regra de consolidação de valores literais em tokens existentes está em §16.14.8.
9. ~~O que acontece com `front_vibes`?~~ **Fechada por D1/D2** — referência e histórico em feature freeze; nunca deletado.

---

## 16. Configurações e requisitos iniciais do projeto

Requisitos arquiteturais a considerar desde o início da reconstrução. **Esta seção não autoriza implementação.** Cada item é implementado no card/fase apropriado; durante a execução de cada card cabe verificar se algum destes requisitos é relevante para aquela implementação e incorporá-lo quando for. Não criar abstrações, módulos ou infraestrutura antecipadamente só para "deixar preparado" sem necessidade concreta, e não reabrir decisões já estabelecidas salvo com evidência técnica concreta de conflito arquitetural.

### 16.0 Estado atual de cada requisito (verificado no código)

A coluna decisiva é a última: distingue o que é **paridade** (reproduzir algo que já existe) do que é **acréscimo** (funcionalidade que o `front_vibes` não tem). O acréscimo precisa ser consciente, porque D2 congela escopo funcional.

| # | Requisito | Existe hoje no `front_vibes`? | Natureza |
| --- | --- | --- | --- |
| 1 | Multilinguagem | **Não.** Nenhuma biblioteca de i18n; strings em inglês no código | **Acréscimo** |
| 2 | Autenticação Firebase + Google | Sim (`auth.service.ts`, `@codetrix-studio/capacitor-google-auth`) | Paridade |
| 3 | Tema claro/escuro | **Sim** (`useThemeMode.ts`: `system`/`light`/`dark`, persistido, `ion-palette-dark`) | Paridade |
| 4 | Ambientes dev/staging/prod | Sim (`.env.development`, `.env.staging`) | Paridade |
| 5 | Push FCM | Sim (`@capacitor-firebase/messaging`, `push-token.service.ts`) | Paridade |
| 6 | Deep links | **Não.** Só `appStateChange`; nenhum handler de URL | **Acréscimo (preparação)** |
| 7 | Armazenamento seguro | **Não.** Token em `@capacitor/preferences`, sem cifra | **Correção** |
| 8 | Preferências do usuário | Sim (tema e manifesto offline em Preferences) | Paridade |
| 9 | Permissões | Parcial (`autoGrantPermissions` no Capacitor) | Paridade + formalização |
| 10 | Acessibilidade | Mínima (1–4 `aria-label` por tela) | **Acréscimo** |
| 11 | Localização regional | Parcial (`toLocaleString()` sem locale fixo — correto) | Paridade + formalização |
| 12 | Timezone | Sim (`schedule-datetime.ts` resolve a IANA do dispositivo) | Paridade |
| 13 | Observabilidade | Sim (OTel, 541 linhas, coletor de staging) | Paridade |
| 14 | Design System / tokens | Sim, informal (`variables.css`, com paleta dark) | **Substituído pela D6:** Design System v1 novo (visual novo, não paridade) |
| 15 | Feature flags | **Não** | **Acréscimo (avaliar)** |
| 16 | Testes | Sim (515 testes Vitest) | Paridade |
| 17 | Versionamento | Parcial (Gradle + `capacitor.config`) | Paridade + centralização |
| 18 | Política de cache | Por funcionalidade, não global | Paridade |
| 19 | Estado de sessão | Sim (`useAuth`) | Paridade |
| 20 | Logout | Sim (`auth.service.ts`) | Paridade |
| 21 | Segurança em logs | Sim (`telemetry/pii-sanitizer.ts`) | Paridade |
| 22 | Conectividade | Sim (`isDeviceOffline`, `offline-playback-status`) | Paridade |
| 23 | Player em background | Sim (foreground service + `backgroundAudio.service`) | Paridade |

**Três itens ampliam escopo funcional além da paridade** — multilinguagem (1), acessibilidade (10) e deep links (6) — e um corrige uma falha existente (7). Estão nesta lista por decisão explícita do PO; o registro aqui serve para que a exceção a D2 seja consciente e não vire precedente para outras.

**Correção de documentação identificada:** o `CLAUDE.md` da raiz do workspace (linha 105) afirma que o tema é "light-only". Isso está **desatualizado** — o `front_vibes` tem dark mode completo desde `useThemeMode.ts`. O item 3 é, portanto, paridade e não feature nova.

### 16.1 Multilinguagem

- Idioma padrão: **inglês**.
- Idiomas inicialmente suportados: **inglês, francês, português, espanhol**.
- A arquitetura deve permitir adicionar novos idiomas depois sem alteração estrutural significativa.

Nota de implementação: o catálogo de strings pode viver no `shared` (uma fonte só) ou nos recursos nativos de cada plataforma (`strings.xml` e `.strings`/String Catalog). A segunda opção entrega pluralização, Dynamic Type e ferramentas de tradução nativas de graça; a primeira garante texto idêntico. A escolha pertence ao card de multilinguagem, não a este plano. Ver §3 (matriz) quando essa decisão for tomada.

**Nota da Fase 1 (K12):** `VibeExecutionLayer.humanReadableSummary` é gerado no `shared` com inglês fixo (`Loop`, `Plays once`, `Every …`, `Starts after …`, `Plays for …`). Foi portado fielmente do TypeScript (migração não é redesenho), mas é texto de apresentação dentro do domínio e conflita com este requisito de multilinguagem. Decidir na Fase 6 (UI) se o texto sai do `shared`.

### 16.2 Autenticação

- **Firebase Authentication**, com **login Google**.
- Sessão, estados de autenticação, logout e armazenamento seguro são definidos durante a implementação do login.

No plano: estratégia técnica em §6.7 (`expect/actual` sobre os SDKs nativos) e §9 (interface + injeção). Estados de sessão no item 16.19; logout no 16.20; armazenamento seguro no 16.7.

### 16.3 Tema claro/escuro

- Suporte a Light e Dark Mode.
- O Design System deve permitir que Compose e SwiftUI usem os **mesmos conceitos e tokens** de tema.
- O comportamento da preferência do usuário é definido durante a implementação.

No plano: ver item 16.14 (Design System) e a questão 8 do §15. Paridade: o comportamento atual é `system` / `light` / `dark` com persistência local, e é o alvo a reproduzir.

### 16.4 Ambientes

- **Development, Staging, Production.**
- A configuração deve separar endpoints, configurações e recursos por ambiente **sem duplicar a lógica da aplicação**.

No plano: §12 — build variants do Gradle com `buildConfigField`, substituindo os arquivos `.env` do Vite. Ver também o item 16.17 (versionamento).

### 16.5 Notificações Push

- **Firebase Cloud Messaging** quando aplicável.
- A integração específica por plataforma permanece nas camadas nativas.

No plano: §3 (registro e renovação de token compartilhados; entrega e exibição nativas) e §9 (interface + injeção).

### 16.6 Deep Links / Universal Links / App Links

- A arquitetura deve estar preparada para deep links.
- Android: **App Links** quando aplicável. iOS: **Universal Links** quando o desenvolvimento iOS começar.
- A navegação deve receber e interpretar links **sem acoplar a lógica de negócio à UI**.

Nota: não existe deep link no app atual. "Preparada para" aqui significa que o roteamento nativo aceite uma rota vinda de fora e a traduza em uma intenção de domínio — não construir infraestrutura de links antes de haver um link real para tratar.

### 16.7 Armazenamento seguro

- Tokens, credenciais e dados sensíveis usam **armazenamento seguro nativo**.
- Android: Android Keystore ou mecanismo seguro equivalente. iOS: **Keychain**.
- **Nunca** armazenar tokens sensíveis em armazenamento comum.

No plano: §6.3 e §9 (`expect/actual`). Este item **corrige** o comportamento atual: hoje o ID token do Firebase é gravado em `@capacitor/preferences`, que não é cifrado. A migração é a oportunidade de fechar essa lacuna, e por isso ela cabe dentro de D2.

### 16.8 Preferências do usuário

- Persistir preferências como **idioma, tema, configurações do player** e outras não sensíveis.
- O mecanismo segue a arquitetura definida no projeto.

No plano: §6.3 (DataStore para não sensíveis). A fronteira com o item 16.7 é rígida: preferência vai em DataStore, credencial vai em armazenamento seguro.

### 16.9 Permissões

- Estratégia **centralizada** para permissões específicas de cada plataforma.
- A lógica de negócio compartilhada **não** depende diretamente das APIs de permissão do Android ou do iOS.

No plano: §9 — interface no `commonMain` com implementação injetada, porque o fluxo é assíncrono e depende da resposta do usuário.

### 16.10 Acessibilidade

- Considerada **desde o início**, não ao final.
- Android: TalkBack e os recursos de acessibilidade do Compose. iOS: VoiceOver e os do SwiftUI.
- Considerar tamanho de fonte, contraste, labels, navegação por acessibilidade e **Dynamic Type** quando aplicável.

Nota: é trabalho majoritariamente novo — o app atual tem poucos `aria-label`, e praticamente nenhum estado de foco ou alvo mínimo declarado. Por ser transversal, o custo é muito menor quando embutido em cada tela da Fase 6 do que em um mutirão posterior. Recomenda-se que "acessibilidade verificada" faça parte do critério de conclusão de cada área de UI, e não vire um card próprio no fim.

**O Design System é o ponto central onde isso se sustenta** — um componente acessível por construção resolve o problema em todas as telas que o usam. Ver §16.14.7.

### 16.11 Localização regional

- Datas, horas, números e demais informações dependentes de locale respeitam a **configuração regional do usuário**.
- **Não assumir que idioma e região são a mesma coisa.**

Nota: o app atual já acerta nisso na exibição — usa `toLocaleString()` sem fixar locale. Atenção a um caso que **parece** violação e não é: `schedule-datetime.ts` fixa `'en-US'` dentro de `timeZoneOffsetMs` porque precisa de um formato estável para *parsing* de offset, não para exibição. Fixar locale para leitura de máquina é correto; o requisito vale para o que o usuário lê.

### 16.12 Timezone

- O timezone do usuário é tratado **explicitamente** onde for relevante: schedules, automações, playback e demais funcionalidades dependentes de horário.
- **Não assumir timezone fixo no código.**

No plano: §6.1 — `kotlinx-datetime` no `commonMain` é obrigatório justamente por isso; `java.time` quebraria o iOS. Paridade: o app atual já resolve a IANA do dispositivo em `schedule-datetime.ts`.

### 16.13 Tratamento global de erros e observabilidade

**Esta é a única fonte de verdade sobre observabilidade neste plano.** As demais menções (§3, §9, §15) apontam para cá.

Erros:

- Estratégia consistente de tratamento de erros em todo o aplicativo.
- Mensagens apresentadas ao usuário devem ser **localizáveis** (item 16.1).
- No plano: §7 — erro faz parte do estado, e a superfície pública usa `Result` selado em vez de exceção, inclusive porque exceção Kotlin não tratada encerra o processo no iOS (§8).

Observabilidade:

- A plataforma **já possui** observabilidade configurada com **OpenTelemetry, Grafana, Loki e Tempo**. A nova arquitetura **preserva e se integra** a esse sistema.
- **Não criar um sistema paralelo** de observabilidade sem necessidade arquitetural explícita.
- Deve permitir diagnosticar, quando aplicável: erros, eventos relevantes, problemas de performance, falhas de comunicação e problemas do player.
- Durante cada implementação, avaliar quais eventos, métricas, logs ou traces **realmente** fazem sentido, evitando instrumentação desnecessária.
- **Dados sensíveis, tokens e credenciais nunca aparecem em logs ou traces** (item 16.21).

Nota técnica: não há SDK OpenTelemetry viável em `commonMain` para Kotlin/Native. O padrão é interface compartilhada com implementação nativa — `opentelemetry-android` no Android e o SDK Swift no iOS — conforme §9. O app atual já sanitiza PII em `telemetry/pii-sanitizer.ts`, comportamento a preservar.

### 16.14 Design System / Design Tokens

> **Atualização de 2026-09-25 (D6 — visual novo).** O PO decidiu uma nova identidade visual; o resultado é o **Design System v1 do Ixora**, aprovado nessa data. Isto **altera três pontos** desta seção e **mantém o resto**:
> - **§16.14.1 (o que já existe)** passa a ser o inventário do sistema visual **antigo**, útil como referência de comportamento e como fonte do que a interface precisa cobrir; **não é mais o alvo** de portabilidade.
> - **§16.14.5 (Figma como origem)**: a origem da linguagem visual passa a ser o Design System v1 (tokens em `tokens.json`, brand book, componentes e guia de movimento), não o nó 127:2 do Figma. O kit de referência é só inspiração de estilo.
> - **§16.14.8 (paridade e consolidação)**: a paridade **visual** deixa de ser o critério. A regra de consolidação de literais é substituída pela regra de **portar os tokens do Design System v1 exatamente, sem arredondar nem reinterpretar**.
> - **Mantidos:** §16.14.2 a §16.14.4, §16.14.6 e §16.14.7 (compartilhado só como conceito; estrutura de referência; sem módulo `design-system`; responsabilidade por plataforma; acessibilidade no Design System). Compose Multiplatform continua fora de escopo e o iOS continua SwiftUI, preparado e não construído.
> - **Novo:** duas fontes livres (Outfit e DM Sans) entram como recursos do app em cada plataforma; ícones da família Lucide como assets vetoriais; contraste WCAG AA medido para todos os pares de tokens em claro e escuro.

Requisito arquitetural com peso próprio: é o que impede Android e iOS de desenvolverem interpretações visuais independentes do produto. Nada aqui autoriza implementação.

**Princípio, em uma frase:**

> **Mesma linguagem visual e mesmos princípios de design, com implementação nativa em cada plataforma.**

O KMP compartilha **comportamento e domínio**. O Design System compartilha **linguagem e regras visuais**. As plataformas implementam a **UI nativamente**.

```
                    IXORA
                      │
             ┌────────┴────────┐
        KMP Shared         Design Language
             │                 │
      Business Logic       Design Tokens
      State / Data         UI Principles
             │                 │
       ┌─────┴─────┐      ┌────┴─────┐
    Android       iOS   Compose    SwiftUI
       │           │      │          │
     Native      Native  Native    Native
       UI          UI  Components Components
```

#### 16.14.1 O que já existe (inventariado no código)

O Design System **não começa do zero** — ele existe, é coerente e tem origem declarada no Figma. `variables.css:3` diz literalmente: *"Ionic design tokens mapped from Figma Design System (node 127:2)"*.

| Categoria | Estado atual | Origem |
| --- | --- | --- |
| Cores semânticas | `--app-color-bg`, `surface`, `surface-subtle`, `border`, `text-primary/secondary/muted` | `variables.css` |
| Escalas de cor | `primary-100…600`, `secondary-100…500` | `variables.css` |
| Marca | primária `#1dac92`, secundária `#252d41`, gradiente primário | `variables.css` |
| Tipografia | `h1…h6` (48→18px), `body-lg/md/sm/xs` (16→10px), 3 line-heights, 3 pesos | `variables.css` |
| Espaçamento | escala `--app-space-1…11` (4px → 60px) | `variables.css` |
| Raio | `sm 8px`, `md 12px`, `lg 20px` | `variables.css` |
| Sombras | `--app-shadow-card`, `--app-shadow-soft`, com valores próprios no dark | `variables.css` |
| Movimento | `fast 140ms`, `base 240ms`, `slow 360ms`, 2 curvas de easing, stagger 48ms | `motion.css` |
| Tema | `system` / `light` / `dark`, com paleta dark completa | `variables.css` + `useThemeMode.ts` |
| Redução de movimento | `prefers-reduced-motion` zera as durações | `motion.css` |
| Componentes reutilizáveis | `AppEmptyState`, `AppErrorState`, `AppLoadingState`, `AppAutomationBadge`, `MiniPlayer`, `CoverBundlePickerModal` | `components/` |
| Estados visuais | `:disabled` (81 usos), `:active` (18), `:hover` (2), `:focus` (1) | telas e CSS |

**Conclusão:** portar este conjunto para Compose é **paridade**, não criação de Design System novo.

#### 16.14.2 Compartilhado como conceito, nunca como UI

**Pode ser compartilhado conceitualmente:** design tokens, cores, tipografia, espaçamentos, dimensões, border radius, elevações/sombras, estados visuais, regras de componentes, princípios de acessibilidade, convenções de nomenclatura, regras gerais de interação e o design language do Ixora.

**Não deve existir como abstração de UI compartilhada.** Explicitamente proibido criar no `shared`:

```
SharedButton      SharedTextField     SharedCard
SharedNavigationBar   SharedPlayerView    SharedScreen
```

Nem transformar Compose e SwiftUI em camada visual comum. Isso reafirma a decisão de UI nativa (§3, K03/ADR-039) e mantém **Compose Multiplatform fora de escopo**.

A UI permanece:

```
Android → Jetpack Compose → Theme · Components · Screens
iOS     → SwiftUI          → Theme · Components · Screens
```

#### 16.14.3 Estrutura de referência

Referência arquitetural, **não uma ordem para criar estes arquivos agora**. Complementa §5.2.

```
shared/            domain/ · data/ · presentation/ · platform/

androidApp/ui/
    theme/         Colors.kt · Typography.kt · Dimensions.kt · IxoraTheme.kt
    components/
    screens/

iosApp/UI/
    Theme/         Colors.swift · Typography.swift · Dimensions.swift · IxoraTheme.swift
    Components/
    Screens/
```

A simetria entre as duas árvores é deliberada: garante que a implementação SwiftUI futura tenha onde encaixar sem redesenhar a arquitetura.

#### 16.14.4 Sem módulo `design-system` no KMP

**Não criar um módulo KMP `design-system/`.** Criar essa abstração exige justificativa por necessidade real, medida — não por simetria.

A estratégia preferencial é:

- `shared` KMP → lógica de negócio, estado, dados e contratos;
- Android → implementação do Design System em Compose;
- iOS → implementação do Design System em SwiftUI;
- documentação e decisões → definem a linguagem visual comum.

Se no futuro algum token fizer sentido ser compartilhado **tecnicamente** (por exemplo, um valor que a lógica de domínio precise conhecer), isso é avaliado na hora, com o caso concreto na mão. Não é presumido agora. Coerente com §5.1: módulo novo só com motivo medido.

#### 16.14.5 Figma como origem visual

```
Figma  →  Design Tokens / Design Language  →  Android (Compose)
                                           →  iOS (SwiftUI)
```

O Figma é a **referência e origem** da linguagem visual, e já é assim hoje (`variables.css:3` cita o nó de origem). O objetivo é impedir que cada plataforma derive sua própria interpretação do produto.

**Não construir agora infraestrutura de sincronização automática Figma → código.** Se um dia isso se justificar, será por volume de mudança visual, não por elegância.

#### 16.14.6 Responsabilidade por plataforma

Detalha a linha "UI" de §3 sem contradizê-la.

| Responsabilidade | Shared | Android | iOS |
| --- | --- | --- | --- |
| Business rules | ✅ | | |
| Domain models | ✅ | | |
| Application state | ✅ | | |
| Design language | conceito | conceito | conceito |
| Design tokens | possível avaliação futura (§16.14.4) | implementação | implementação |
| Theme | | Compose | SwiftUI |
| UI Components | | Compose | SwiftUI |
| Screens | | Compose | SwiftUI |
| Navigation UI | | Compose | SwiftUI |
| Player UI | estado compartilhado quando aplicável | Compose | SwiftUI |

"Conceito" significa: a regra existe e é única, mas não é código no `shared`.

#### 16.14.7 Acessibilidade é responsabilidade do Design System

O Design System é o **ponto central** onde a acessibilidade (§16.10) se sustenta — um componente acessível por construção resolve o problema em todas as telas que o usam.

Quando aplicável: contraste, tamanho mínimo de área interativa, estados de foco, estados disabled, labels, suporte a Dynamic Type e escalabilidade de fonte, semântica e tecnologias assistivas nativas (TalkBack e VoiceOver).

Base atual: 24 `aria-label`, 18 `role`, 33 `aria-hidden`, apenas 4 declarações de alvo mínimo (48px/44px) e **um único** `:focus` em todo o app. Ou seja: estado de foco e alvo mínimo são essencialmente ausentes hoje e devem nascer no componente, não na tela.

Nada a implementar agora — apenas a responsabilidade arquitetural estabelecida.

#### 16.14.8 Paridade e a regra de consolidação de tokens

Distinção que precisa ficar rígida:

- **Reproduzir o sistema visual existente → paridade.** É o escopo da migração.
- **Criar experiência visual nova → mudança de produto.** Precisa de decisão explícita do PO e está fora de D2.

**Não introduzir redesenho durante a migração.** `system`/`light`/`dark` é **paridade** (§16.0, item 3), não feature nova.

Há um detalhe real a tratar. O sistema de tokens existe, mas **convive com valores literais**: `border-radius: 12px` aparece 14 vezes enquanto `--app-radius-md` vale exatamente 12px; `font-size: 18px` aparece 21 vezes enquanto `--app-font-size-h6` vale 18px. A regra ao portar:

1. Valor literal que **coincide** com um token existente → usar o token. Mesmo resultado visual, nome recuperado. Isso é consolidação, não redesenho.
2. Valor literal **sem** token correspondente → manter o valor e **registrar a divergência**, sem inventar token novo nem arredondar para o token mais próximo. Arredondar muda pixel, e mudar pixel é redesenho.

Ver questão 8 do §15, agora fechada.

**Atualização de 2026-09-25 (D6).** O texto acima descreve a regra original e **deixa de valer para valores visuais**. Regra vigente: (1) o comportamento continua em paridade (D2); (2) os valores visuais vêm do **Design System v1** e são portados **exatamente**: cor, tipografia, espaçamento, raio e sombra, sem arredondar para outro valor nem "melhorar" na tradução; (3) o que o Design System v1 não desenhou é desenhado com seus componentes e tokens e aprovado pelo PO antes de implementar; (4) qualquer necessidade de componente novo volta como mudança ao Design System, não como solução local na tela.

### 16.15 Feature Flags / Remote Configuration

- Avaliar suporte a feature flags e configuração remota **quando houver necessidade**.
- **Não implementar um sistema complexo antecipadamente.**
- Durante cada implementação, avaliar se a funcionalidade realmente precisa de configuração remota.

### 16.16 Testes automatizados

- A estrutura nasce preparada para `commonTest`, testes unitários e de integração no Android, e testes iOS quando aquele desenvolvimento começar.
- **Os testes acompanham a migração das regras de negócio e do player** — não vêm depois.

No plano: §6.8 (ferramentas) e §11.2 (testes são critério de conclusão de cada fase, não uma fase final). A regra de paridade nomeada dos testes portados está em §6.8.

### 16.17 Versionamento

- Centralizar **versão do aplicativo, build number, configuração de ambiente** e demais metadados de release.
- Preservar compatibilidade com os requisitos existentes do aplicativo quando aplicável.

No plano: §12. O requisito crítico de compatibilidade é o `applicationId` `app.ixora.ixora` com a mesma chave de assinatura — sem isso o app novo não atualiza o instalado (Fase 8, risco 6 do §14).

### 16.18 Política de armazenamento e cache

- **Não** definir antecipadamente uma política completa para todo o aplicativo.
- Durante cada implementação, quando a funcionalidade envolver armazenamento, cache ou dados locais, avaliar qual estratégia faz sentido, considerando explicitamente: **dados temporários, dados persistentes, dados descartáveis, necessidade de sincronização e comportamento offline**.
- Conforme **D3**, não haverá migração dos dados locais existentes do `front_vibes`.

### 16.19 Estado global de sessão

- **Não implementar antecipadamente.**
- Durante a implementação do login, definir os estados necessários: `authenticated`, `unauthenticated`, `loading`, `expired` e outros identificados na implementação.

No plano: §7 define *como* o estado é modelado e exposto; *quais* estados de sessão existem é decisão do card de autenticação.

### 16.20 Logout

- Definido durante a implementação do login, considerando: **encerramento da sessão Firebase, limpeza segura dos tokens e credenciais locais, limpeza do estado de sessão e comportamento dos dados e cache relacionados à sessão**.
- **Não implementar antes do card/fase de autenticação.**

### 16.21 Segurança

- Evitar exposição acidental de **tokens, credenciais, dados sensíveis, informações privadas do usuário e dados de autenticação**.
- Logs, erros e traces devem ser revisados para evitar vazamento de informação sensível.

Relacionado: item 16.7 (armazenamento seguro), item 16.13 (nada sensível em telemetria) e §12 (secrets fora do versionamento, em `local.properties` e GitHub Secrets).

### 16.22 Conectividade

- A arquitetura deve permitir identificar e reagir ao estado de conectividade **quando isso for relevante**.
- Funcionalidades que dependem de rede definem explicitamente seu comportamento: **online, offline, reconexão e falha de rede**.
- **Não criar uma abstração global complexa sem necessidade** — introduzir conforme as funcionalidades exigirem.

Paridade: `isDeviceOffline` e `offline-playback-status` já expressam essa lógica hoje, e `offline-playback-status` está classificado como SHARED em §2.2.

### 16.23 Player em background

- Requisito arquitetural **desde o início**.
- Considerar: execução em background, controles de mídia, interrupções, áudio em segundo plano, audio focus/session, retomada, comportamento durante bloqueio de tela e integração com os mecanismos nativos de cada plataforma.
- Os detalhes são definidos no trabalho do player (**K05 / ADR-040**).

No plano: §10 e §3. A divisão vale também aqui: o `shared` decide o que deveria estar tocando; foreground service (Android) e `AVAudioSession` (iOS) fazem tocar.

---

## 17. Backlog inicial de tarefas arquiteturais

Fatias pequenas o bastante para execução assistida, cada uma com resultado verificável. Fases 0 e 1 apenas — o backlog seguinte se escreve depois da Fase 1, com aprendizado real.

| # | Tarefa | Fase | Saída verificável |
| --- | --- | --- | --- |
| K01 | **Consolidar decisões arquiteturais** | 0 | ✅ **Concluído em 2026-09-23** por esta revisão: §0 registra D1–D5; questões 1, 4, 6, 7 e 9 do §15 fechadas; §5.3, §10.4, §11, §14 e §15 atualizados. Restam abertas as questões 2, 3, 5 e 8, nenhuma bloqueante. |
| K02 | **ADR-038 — KMP Shared Layer** | 0 | ✅ **Concluído em 2026-09-23.** ADR Accepted: o que vai para `commonMain`, o que não vai, e o critério de decisão (a matriz do §3). Addendum pós-aceitação registrado em K12. |
| K03 | **ADR-039 — Native UI: Compose + SwiftUI** | 0 | ✅ **Concluído em 2026-09-23.** ADR Accepted: sem Compose Multiplatform; custo aceito de reescrever a UI duas vezes; estratégia de Design System de §16.14 registrada como decisão (linguagem comum, implementação nativa, sem módulo `design-system`, Figma como origem). |
| K04 | **ADR-042 — Migration / Repository Strategy** | 0 | ✅ **Concluído em 2026-09-23.** ADR Accepted + `repo-responsibilities.md`, `architecture-map.md` e `CLAUDE.md` da raiz refletindo o quinto repositório (`ixora-app`) e o feature freeze. |
| K05 | **ADR-040 — Native Player Architecture** | 0 | ✅ **Concluído em 2026-09-23.** ADR Accepted cobrindo: plano e scheduler compartilhados, transporte nativo, **e a especificação da semântica de fade (§10.4)**. Declara explicitamente que supersede a proibição de fade da ADR-008. |
| K06 | **ADR-041 — State Management / Swift Interop** | 0 | ✅ **Concluído em 2026-09-23.** ADR Accepted: StateFlow, `Result` selado, efeitos por `Channel`, SKIE. Addendum pós-aceitação com resultados K07 registrado em K12. |
| K07 | **Criar módulo `shared` KMP** no repositório `ixora-app`, com version catalog e targets android + iOS declarados | 1 | ✅ **Concluído em 2026-09-24.** `./gradlew :shared:build` verde; targets iOS declarados; `compileTestKotlinIosArm64` executa no Windows; `compileKotlinIosArm64` fica `NO-SOURCE` até haver código em `commonMain` (K09) e passa a executar de fato a partir daí. Git Flow configurado; `gradle/verification-metadata.xml` gerado. |
| K08 | **Criar boundary tests** do `commonMain` (sem API JVM-only nem Android-only), com sentinelas que provam detecção e não-detecção | 1 | ✅ **Concluído em 2026-09-24.** `CommonMainBoundaryTest` (rejeita `java.*`, `javax.*`, `android.*`, `androidx.*`; inclui sentinelas de detecção e de não-detecção, 20 testes) verde em `androidHostTest`. |
| K09 | **Migrar `VibeSound` e `VibeExecutionLayer`** com kotlinx.serialization | 1 | ✅ **Concluído em 2026-09-24.** `VibeSound` (15 campos, `@Serializable`), `PlayMode` (enum) e `VibeExecutionLayer` em `commonMain`; `kotlinx-serialization-json 1.11.0` adicionado; fixture de staging real capturada (`back_vibes` @ `73f23d1c`); 5 testes de serialização em `commonTest`, incluindo falha por campo ausente e `PlayMode` desconhecido. |
| K10 | **Migrar `buildVibeExecutionPlan`** para `commonMain` | 1 | ✅ **Concluído em 2026-09-25.** `buildVibeExecutionPlan`, `formatDuration` e `buildSummary` em `commonMain`; oracle esbuild + Node (player-engine não possui Vitest — ver §2.2 correção); 17 casos de golden-master em `commonTest`; prova de mutação. |
| K11 | **Expandir paridade do player engine** em `commonTest` com cobertura exaustiva | 1 | ✅ **Concluído em 2026-09-25.** 384 combinações de 1 som (3×4×4×4×2), 30 planos multi-som (PRNG seed 20260925), 3713 entradas de `formatDuration` (0..3700 + 12 pontos de borda); fixtures divididas em partes ≤50 KB (limite JVM `const val`); anti-vacuidade guards (≥17 casos, ≥14 formatDuration entries); seção "Player engine parity" no `README.md`; 5 mutações provadas. |
| K12 | **Documentar o resultado da Fase 1** e revisar este plano com o aprendizado | 1 | **Em revisão (PR #65); concluído com o merge.** ADR-038 e ADR-041 com addenda pós-aceitação; `kmp-migration-plan.md` revisado com aprendizado real; `quality-harness.md` com seção `ixora-app`. **Revisão registrada em 2026-09-25:** a D6 (visual novo, Design System v1) foi incorporada ao plano (§0, §11.2 Fases 5 e 6, §15 questão 8, §16.0 item 14, §16.14) e à addendum da ADR-039. |

Ordem de execução: K01 → K02–K06 (as cinco ADRs, que podem ser escritas em qualquer ordem entre si) → K07 → K08 → K09 → K10 → K11 → K12. O K05 é o mais denso das ADRs, porque acumula a especificação de fade.

K12 não é burocracia: a Fase 1 é a primeira vez que o projeto encosta em KMP de verdade, e a maioria das estimativas deste documento merece revisão depois dela.

### 17.1 Resultado da Fase 1 e decisão da Fase 2

**Fase 0 concluída:** todas as cinco ADRs (K02–K06) aceitas em 2026-09-23. Questões 1, 3, 4, 6, 7, 8 e 9 do §15 fechadas. Questões 2 e 5 permanecem abertas e não bloqueiam a Fase 2.

**Fase 1 concluída:** K07–K12 concluídos em 2026-09-24 e 2026-09-25. O módulo `shared` existe, compila para Android e iOS no Windows, é protegido por teste de fronteira automatizado, e contém `VibeSound`, `PlayMode`, `VibeExecutionLayer`, `buildVibeExecutionPlan`, `formatDuration` e `buildSummary` com cobertura golden-master exaustiva (3713 + 384 + 30 casos). A Fase 1 entregou o que foi prometido.

**Aprendizados que corrigem estimativas do plano:**
1. `player-engine` não tinha testes Vitest — a paridade foi construída por golden master contra o TS real, não por port de testes existentes. **Isso não vale para os demais módulos de lógica pura:** `utils/` e `canonical-*` **têm** testes Vitest (por exemplo `canonical-capabilities`, `capability-contract-coherence`, `canonical-boundary`, `device-action`, `device-status`, `schedule-format`, `schedule-datetime` — confirmado com `git ls-files | Select-String "\.test\.ts$" | Select-String "canonical|device-|schedule-"` em `front_vibes` @ `develop`), a serem portados como paridade nomeada conforme §6.8. A estimativa da Fase 3 para esses módulos não muda por causa do achado do `player-engine`.
2. A compilação iOS executa no Windows com Kotlin 2.3.20. O teste de fronteira não é o único mecanismo de proteção da fronteira — ver addendum do ADR-038.
3. O limite JVM de `const val` (65.535 bytes UTF-8) emerge quando fixtures de teste são grandes. A solução (split em partes + `listOf(...).joinToString("")`) é conhecida; cabe lembrar disso na Fase 3 quando o CSDM e os testes de scheduling forem portados.
4. O AGP 8.13.0 com `com.android.kotlin.multiplatform.library` não usa `androidTarget()` — ver addendum do ADR-038.

**Recomendação para a Fase 2** (Ktor, autenticação Firebase por `expect/actual`, armazenamento seguro): iniciar. A pré-condição técnica está satisfeita: módulo `shared` compilando, guards ativos e comportamento do plano de execução provado contra o TypeScript real. Condições: (1) responder as questões 2 e 5 do §15 antes do primeiro card da Fase 2 (a 5 tem prazo declarado: até a Fase 2); (2) decidir na Fase 2 ou na Fase 4 como validar URLs de arquivo de áudio, já que `hasValidExecutionFileUrl` e `isExecutionLayerPlayable` não foram portados (dependem do parser WHATWG, sem equivalente em `commonMain` sem Ktor); (3) a tensão entre `androidx.datastore` e a Decision 5 da ADR-038 fica para a ADR-043 (Fase 3) e não bloqueia a Fase 2; (4) a paridade de `utils/` e `canonical-*` na Fase 3 parte de testes Vitest existentes.

Este documento não autoriza implementação; registra apenas que a pré-condição técnica da Fase 2 (Fase 1 concluída) está satisfeita.

**Decisão do PO sobre iniciar a Fase 2:** _pendente — a registrar pelo PO._

---

## 18. Relação com outros documentos

- [ADR-007 — Execution plan as mobile playback runtime contract](../../decisions/ADR-007-execution-plan-runtime-contract.md) — o contrato do plano de execução é **reafirmado**: continua device-side e o `back_vibes` segue sem engine de playback. Mas a ADR nomeia explicitamente `player-engine.service.ts`, `player.store` e `audio-player.service` como a implementação vigente; quando a Fase 5 concluir, ela precisa de um addendum apontando para o `PlaybackScheduler` em Kotlin. A decisão não muda, a implementação citada sim.
- [ADR-008 — NativeAudio limitations over unstable JS-driven DSP](../../decisions/ADR-008-nativeaudio-limitations-over-unstable-dsp.md) — **esta é a única ADR que a migração efetivamente reabre, e a decisão D4 já determinou que ela será reaberta.** Ela removeu fades em runtime porque o `@capgo/native-audio` e a ponte Capacitor não sustentavam DSP confiável; com Media3 e AVAudioEngine a premissa deixa de valer. A ADR-040 (K05) deve **supersedê-la explicitamente na parte de fade**, declarando que a proibição valia para a stack Capacitor e não se transfere para a nova. A ADR-008 passa a Superseded-in-part e o [`audio-engine-fade-limitations.md`](../audio/audio-engine-fade-limitations.md) vira documento histórico quando a Fase 4 concluir. Revogação silenciosa não é aceitável — a decisão original foi tomada com razão técnica e merece ser encerrada com a mesma formalidade.
- [ADR-036](../../decisions/ADR-036-google-home-execution-model.md) — modelo de execução do Google Home: o SDK segue Android-only; o iOS nunca terá Google Home.
- [ADR-037](../../decisions/ADR-037-canonical-smart-home-device-model.md) e [CSDM](../../specs/smart-home/canonical-device-model.md) — o modelo canônico migra para Kotlin com os mesmos guards.
- [`playback-runtime.md`](../audio/playback-runtime.md) e [`audio-engine-fade-limitations.md`](../audio/audio-engine-fade-limitations.md) — descrevem o runtime que este plano substitui; devem ser marcados como histórico quando a Fase 5 concluir.
- [`contracts/README.md`](../../../contracts/README.md) — o app novo vira consumidor vendorizado do schema canônico.
- [`repo-responsibilities.md`](../repo-responsibilities.md) — precisa refletir o novo repositório, se a Opção A do §5.3 for confirmada.
- [`quality-harness.md`](../../quality-harness.md) — atualizado em K12 com a seção `ixora-app`: baseline de 33 testes (`androidHostTest`), gates de qualidade da Fase 1 e instruções de execução. O backlog da Fase 2 é escrito no primeiro card da Fase 2, não aqui.
