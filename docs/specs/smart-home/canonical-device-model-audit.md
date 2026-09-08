# Auditoria: modelo canônico de Device do Ixora — flags vs. modelo composto

**Date:** 2026-09-07
**Type:** Investigation only. No production code changed, no ADR changed, no migration created, no implementation card created.
**Consumed by:** [ADR-037](../../decisions/ADR-037-canonical-smart-home-device-model.md) (CSDM-00), which formalizes the architecture this audit recommends.

---

## A. Estado atual factual

**Tabela `devices`** (`back_vibes/database/migrations/2026_06_14_000002_harden_devices_table.php` + `2026_09_04_000001_add_capabilities_to_devices_table.php`):

| Coluna | Tipo | Papel |
|---|---|---|
| `id` | bigint PK | chave interna — é o que Scenes/Vibes referenciam, nunca o ID do provider |
| `user_id`, `provider_connection_id` | FK | ownership/conexão |
| `provider` | string | slug (`home_assistant`, `google_home`) |
| `provider_device_id` | string | ID opaco do provider, escopado por connection |
| `name` | string | nome de exibição |
| `type` | string, nullable | `DeviceType` enum: `Lighting`, `Switchable`, `Media`, `Ventilation`, `Other` |
| `metadata` | json, nullable | payload bruto do provider, passthrough |
| `capabilities` | json, nullable | mapa `{capability_key: constraint_object}` |
| `status` | string | `DeviceStatus`: `Online`/`Offline`/`Unknown` — **conectividade, não estado funcional** |
| `last_seen_at` | timestamp | — |

**DTOs do contrato** (`ProviderAdapter`):
- `ProviderDevice` (retorno de `listDevices()`): `provider_device_id, name, type: string, status, metadata, capabilities: ?array`.
- `DeviceStatusResult` (retorno de `readStatus()`): `provider_device_id, status: DeviceStatus, raw_state: ?string, attributes: array, last_changed: ?string`.

**`ActionType`** (`app/SmartHome/ActionType.php`): enum fechado `turn_on | turn_off | toggle | set_brightness`. Cada caso mapeia 1:1 para uma capability obrigatória (`requiredCapability()`).

**Gate de capability** (`ActionType::isBlockedByDeviceCapabilities()`): checa apenas se a CHAVE da capability existe no mapa. Fail-open se `capabilities === null`.

**`SceneAction.parameters`**: `json`, nullable, schema livre. Validado no `FormRequest` apenas como `['nullable', 'array']` — **nenhuma validação de schema do conteúdo**.

**`HomeAssistantAdapter::executeAction()`**: `$payload = array_merge(['entity_id' => $deviceId], $parameters);` — os `parameters` da SceneAction são enviados **crus e sem validação de valor** para a API HTTP do Home Assistant.

**Frontend** (`front_vibes/src/utils/device-action.ts`): `ACTION_TYPES = ['turn_on', 'turn_off', 'toggle']` — **`set_brightness` não existe no vocabulário de UI**. A capability `can_set_brightness` já é derivada e devolvida pela API desde T16/T17, mas hoje não há como o usuário criar uma ação de brilho pelo app.

---

## Respostas às 15 perguntas

**1. Modelo canônico de Device hoje:** uma linha em `devices` com identidade (`id` interno + `provider_device_id` opaco por connection), categoria grosseira (`type`), payload bruto (`metadata`), e um mapa de capabilities. **Não existe um modelo de estado canônico** — só conectividade (`status`).

**2. O que `type` representa:** categoria grosseira para ícone/rótulo na UI (5 valores). Não descreve operações nem parâmetros. `HomeAssistantAdapter::mapDeviceType()` mapeia domínio HA → esse enum; o domínio HA original fica em `metadata`.

**3. O que `capabilities` representa:** um mapa `{capability_key: constraint_object}`. `capability_key` é hoje **sinônimo de "posso executar este ActionType"** — não existe capability que não corresponda a exatamente um `ActionType`.

**4. Capabilities descrevem operações/parâmetros/ranges/units/constraints?** Parcialmente, e de forma ad-hoc:
- **Ranges/constraints:** sim, mas só para `can_set_brightness` (`{min,max,step}`) — é a ÚNICA capability com objeto de constraint não-vazio hoje. Nenhum schema formal define esse formato; é convenção implícita de uma única implementação (`HomeAssistantAdapter::deriveCapabilities()`).
- **Units:** **não existe campo de unidade em lugar nenhum.** O `{min:0,max:255,step:1}` de brightness não diz "isso é uma escala 0-255 sem unidade real" — é implícito.
- **Operations:** **não existe lista de operações por capability.** Uma capability é 1 chave = 1 ação. Não há espaço para "uma capability com múltiplas operações" (ex.: `position` com `open/close/set/stop`).
- **Capabilities somente-leitura (sensores):** **não existem.** O modelo só descreve "o que posso comandar", nunca "o que posso ler continuamente" (ex.: consumo de energia, temperatura atual).

**5. Onde o estado atual de um device é representado:** **em lugar nenhum do domínio, de forma canônica.** `readStatus()` devolve `raw_state: ?string` e `attributes: array` — nomeados assim deliberadamente para sinalizar "não normalizado, passthrough do provider". Nada disso é persistido; é buscado sob demanda.

**6. Onde parâmetros como brightness são validados hoje:** **em lugar nenhum, no valor.** Confirmado lendo o código: o `FormRequest` só valida que `parameters` é um array; o gate de capability só checa a presença da chave `can_set_brightness`, nunca o valor numérico contra `{min,max,step}`; `HomeAssistantAdapter::executeAction()` repassa `$parameters` cru para a API HTTP do HA. Um `{"brightness": 9999}` passaria por todas as camadas do Ixora sem erro — só falharia (ou não) do lado do Home Assistant.

**7. `0–255` é decisão formal do domínio Ixora ou vazamento do Home Assistant?** **Vazamento, confirmado pelo próprio texto da ADR-033**, que descreve o valor como "matching HA's 0-255 convention" — não há nenhuma justificativa de domínio própria do Ixora para esse número. E o próprio GH04 (produzido nesta sessão) já registrou isso explicitamente: *"ADR-033's HA-derived {max: 255} constraint cannot be reused verbatim for Google Home devices"*. Sua suspeita está confirmada, e já havia sido parcialmente flagrada — mas apenas como ressalva pontual do GH04, não como problema estrutural do modelo.

**8. Outros lugares onde conceito específico do HA já é tratado como canônico:**
- **`ActionType` é literalmente o vocabulário de serviços do Home Assistant.** `ACTION_SERVICE_MAP` no adapter mapeia `turn_on → turn_on`, `toggle → toggle` — é praticamente identidade. `toggle` como ActionType só existe porque HA tem `light.toggle`/`switch.toggle` nativos. O GH04 já precisou inventar uma composição (ler estado → inverter → on()/off()) porque o Google Home **não tem** comando nativo de toggle — ou seja, o vocabulário de ações do Ixora já não é provider-neutro na prática, só não tinha sido testado contra um segundo provider até agora.
- **O formato do constraint object** (`{min,max,step}`, sem unidade) nasceu para descrever exatamente o range de brightness do HA, não de um princípio de domínio.

**9. O modelo consegue representar Light A/B/C, Plug+energy, Thermostat sem condicional por provider no domínio?**

| Device | Resultado | Onde quebra |
|---|---|---|
| Light A (on/off) | ✅ Funciona | — |
| Light B (on/off + brightness) | ⚠️ Funciona de forma frágil | sem unidade, sem validação de valor, faixa é convenção do HA |
| Light C (+ color, color temp) | ❌ **Quebra** | não existe capability para cor — a própria ADR-033 §3 exclui `can_set_color`/`can_set_color_temp` explicitamente do vocabulário fechado |
| Plug + energy measurement | ❌ **Quebra** | não existe conceito de capability somente-leitura/telemetria contínua |
| Thermostat (current temp, target temp, HVAC mode) | ❌ **Quebra em 3 pontos** | (a) leitura contínua de temperatura atual — mesmo gap do plug; (b) target temperature poderia reusar `{min,max,step}` SE existisse a capability, mas não existe; (c) HVAC mode é um parâmetro de **enum de valores permitidos** — o constraint object nunca precisou descrever isso, só numérico, então nem a forma do schema está pronta |

**10. Onde exatamente o modelo quebra:** três pontos estruturais, não um só — (a) vocabulário fechado de capabilities não tem entrada para cor/temperatura/telemetria; (b) constraint object não tem forma para "enum de valores" nem campo de unidade; (c) não existe nenhum jeito de expressar uma capability somente-leitura (sensor) — o modelo assume que toda capability corresponde a um comando executável.

**11-12. Comparação com a proposta do usuário e com a ADR-033 atual:**

| O que a proposta pede | ADR-033 já resolve? |
|---|---|
| `DeviceType` | ✅ já existe (T15), sem mudança necessária |
| `Capability.id` | ✅ já existe (a chave do mapa) |
| `Capability.operations` | ❌ não existe — hoje é 1 chave = 1 operação implícita |
| `Capability.constraints` | ⚠️ existe só para brightness, sem schema formal, sem unidade, sem forma de enum |
| `DeviceState` | ❌ não existe — só conectividade; estado funcional é raw passthrough |
| `Operation parameters` (tipados) | ❌ não existe — `SceneAction.parameters` é JSON livre, sem schema, sem validação de valor |
| `Provider mapper` (fronteira explícita) | ✅ **já existe, e já é o único ponto de mapeamento** — `HomeAssistantAdapter::deriveCapabilities()`/`mapDeviceType()` são exatamente essa fronteira; GH04 já projeta a mesma fronteira do lado Google Home (na camada Kotlin, ainda a implementar) |

**O que já está bem resolvido (não precisa reinventar):**
- A separação `devices.id` (interno) vs. `provider_device_id` (opaco por provider) — Scenes/Vibes nunca tocam o ID do provider. Essa é exatamente a "boundary" que a proposta do usuário pede, e ela já existe.
- O padrão de mapper único por provider (`HomeAssistantAdapter`, e o equivalente Kotlin do GH04) — nenhum outro lugar do domínio faz mapeamento próprio.
- O fail-open de capability ausente/desconhecida (ADR-033 §5) — já é o comportamento correto para um modelo evolutivo.

**O que pode ser estendido sem quebrar a ADR-033:**
- Adicionar `unit` ao constraint object de uma capability (aditivo, não quebra nada existente).
- Adicionar novas capabilities ao vocabulário fechado (ex.: `can_set_color`) — a ADR-033 já prevê isso explicitamente: *"Adding them follows the same pattern: new string in the closed set, new ActionType case, new row in this table"*.
- Adicionar validação de valor contra o constraint object no gate — é aditivo, fecha um gap real, não muda formato de dado existente.

**O que exigiria nova ADR ou supersessão:**
- Introduzir capabilities somente-leitura/telemetria (sensor) — muda a premissa central da ADR-033 de que capability = comando executável.
- Introduzir `operations` como lista dentro de uma capability (hoje é 1:1 implícito) — muda a forma do dado persistido em `devices.capabilities`, exige migração de dado.
- Formalizar um schema de constraint com tipos variados (numérico com unidade, enum de valores, booleano) — é mudança de contrato, não just aditiva.
- Desacoplar `ActionType` de ser 1:1 com "verbo de serviço do HA" (ex.: resolver o caso `toggle` sem comando nativo em outros providers) de forma genérica, não caso a caso como o GH04 fez.

**Impacto em back_vibes:** `Device.capabilities` casts, `ActionType`, `DeviceResource`, `ActionType::isBlockedByDeviceCapabilities()`, `HomeAssistantAdapter::deriveCapabilities()`, potencialmente uma migration de formato (não de dado perdido — é aditivo se bem desenhado).

**Impacto em front_vibes:** `device-action.ts` (`ACTION_TYPES`, `CAPABILITY_REQUIRED`), `SceneDeviceActionEditModal.vue` — hoje já ignoram `set_brightness` completamente, então o impacto real é "finalmente construir a UI que falta", não "migrar UI existente que quebra".

**Impacto no Kotlin/Google Home:** o GH04 (`trait-capability-mapping.md`) já documenta os dois achados reais (toggle sem comando nativo, brightness 0-254) exatamente no formato que essa evolução formalizaria — a peça Kotlin de P09 seria o primeiro "provider mapper" a nascer já ciente do modelo novo, se a evolução acontecer antes de P09.

**Impacto em Scenes/Vibes:** nenhum impacto estrutural — `SceneAction.parameters` já é JSON livre; passa a ser validado contra um schema tipado por capability, o que é estritamente uma restrição adicional, não uma mudança de shape.

**Impacto em dados já persistidos:** `devices.capabilities` existente (`{}` para booleanas, `{min,max,step}` para brightness) continua válido sob um schema estendido que adicione `unit`/`operations` como campos opcionais — não exige backfill destrutivo se a extensão for aditiva.

---

## D. Exemplos concretos (HA vs. Google Home)

- **Brightness:** HA 0–255 (inteiro, sem unidade documentada) vs. Google Home Matter `LevelControl.currentLevel` 0–254 (255 reservado como "indefinido" no protocolo). Confirmado por leitura direta do javadoc do SDK (GH04). Hoje o Ixora "resolve" isso normalizando na camada Kotlin (0–254→0–255) — ou seja, **traduzindo Google Home para o vocabulário do HA**, não para um vocabulário próprio do Ixora. Funciona, mas é o sintoma exato da preocupação: 255 nunca foi uma escolha do domínio.
- **Toggle:** HA tem `light.toggle`/`switch.toggle` nativos. Google Home `OnOffTrait` não tem comando toggle — GH04 já precisou propor implementação client-side (ler → inverter → on()/off()). Isso só apareceu porque um segundo provider real foi implementado; o modelo atual não previa a possibilidade.
- **Cor:** nenhum dos dois providers foi mapeado para cor ainda, mas ambos suportam nativamente (`ColorControlTrait` no Google Home, bits de cor no HA `supported_features`). A ADR-033 exclui cor explicitamente — não é um gap silencioso, é um gap **documentado e deliberado**, mas ainda assim confirma que o vocabulário fechado atual não cobre um caso real e conhecido.

---

## E. Risco de continuar a v1.6.0 sem resolver isso

**Baixo a médio, não alto — com uma condição.** O escopo aprovado de P01–P14 é: on/off, toggle (via composição já documentada no GH04), e brightness **na mesma forma frágil que já existe para HA hoje** (P09 normaliza 0-254→0-255, replicando exatamente o padrão HA existente, não inventando nada novo). Nenhuma das tasks aprovadas introduz cor, telemetria, ou thermostat. **A v1.6.0 não precisa do modelo composto para entregar o que já foi aprovado.**

A condição: se essa evolução acontecer DEPOIS de P09 (camada Kotlin) e P05 (upsert no backend) já estarem implementadas, o retrabalho é localizado e pequeno — ambos os pontos já são "provider mapper" no sentido da proposta, então evoluir o formato do dado que eles produzem é uma mudança de contrato aditiva, não uma reescrita. **Não há retrabalho significativo esperado** se a decisão for adiar.

O único risco real de adiar indefinidamente: cada nova capability futura (cor, thermostat, sensores) que for adicionada sob o modelo atual vai precisar do mesmo tipo de tratamento ad-hoc que `set_brightness` já recebeu — e cada uma constrói mais dívida sobre um formato sem unidade/operations/enum-constraint. Isso não bloqueia a v1.6.0, mas cresce o custo de uma migração futura proporcionalmente ao número de capabilities novas adicionadas antes dela.

---

## F. Arquitetura recomendada

A proposta do usuário (`DeviceType` / `Capability{id, operations, constraints}` / `DeviceState` / `Operation parameters` / `Provider mapper`) é **compatível com o que já existe, não concorrente**. Ela formaliza três coisas que hoje são implícitas:
1. Capability como `{operations: [...], constraints: {...}}` em vez de `{constraint_object}` solto por chave.
2. `constraints` com schema tipado (numeric+unit, enum, boolean) em vez de só `{min,max,step}` sem unidade.
3. Um conceito de `DeviceState` canônico — hoje inexistente — para separar "o que o device pode fazer" (capability) de "o que o device está fazendo agora" (state), inclusive para propriedades somente-leitura.

A regra do item 14 (*"nenhum provider define a semântica canônica do Ixora"*) **já é o princípio real por trás de `ProviderAdapter`/`HomeAssistantAdapter` e do `ProviderExtensibilityBoundaryTest`** — só não foi aplicada com rigor ao FORMATO das capabilities em si (que hoje reflete a forma do HA). É consistente estender o princípio já aceito, não introduzir um novo.

## G. Precisa de nova ADR?

**Sim, para a parte estrutural** (operations, constraints tipados, DeviceState) — a ADR-033 seria superseded/emendada, não a proposta do usuário. **Não** para o que já é aditivo (novo capability string, novo campo opcional `unit`) — a própria ADR-033 já autoriza isso sem nova ADR.

## H. Resolver antes ou depois de P01–P14?

**Pode evoluir depois, sem retrabalho significativo**, com uma ressalva: se P09 (Kotlin) for escrita ANTES da decisão, ela vai (corretamente, dentro do escopo atual) replicar a normalização 0-254→0-255 no formato existente — que continua válido sob um schema estendido, só passaria a carregar `unit` opcionalmente depois. Não há necessidade de bloquear P01–P14 por isso.

## I. Módulo / biblioteca / microserviço

**Recomendação: (A) evolução dentro de back_vibes, com o "provider mapper" já formalizado como ele já é hoje** (uma classe por provider implementando o contrato) — não (B) bounded context separado, não (C) biblioteca compartilhada versionada, e certamente não (D) microserviço.

Nenhum dos critérios que justificariam (D) está presente: não há necessidade de deploy independente (o mapper só roda dentro do processo que já detém a credencial, ou no app mobile — não há cenário de "vários serviços" chamando um serviço de mapeamento remotamente); não há scaling independente a justificar (mapeamento é CPU-trivial, não é gargalo); não há isolamento de falha real a ganhar (uma falha de mapeamento já é isolada por estar dentro do adapter/plugin, sem afetar o resto do sistema); não há múltiplos consumidores reais além do próprio back_vibes e do próprio front_vibes, cada um já com seu mapper natural.

(C) biblioteca compartilhada backend/mobile também não se justifica hoje: PHP (back_vibes) e Kotlin (front_vibes) não compartilham runtime, então uma "biblioteca compartilhada" seria na prática um **schema/contrato versionado** (ex.: JSON Schema do formato de capability), não código compartilhado — isso é razoável como artefato de documentação/validação, mas não é uma decisão de infraestrutura nova, é só formalizar o contrato que ADR-033 já é hoje, um nível mais explícito.

---

## Resumo direto

Sua preocupação **não está resolvida pelo modelo atual** — está confirmada, com evidência de código, em três pontos estruturais reais (sem capability somente-leitura, sem `operations` por capability, sem `DeviceState` canônico), mais um gap de validação já existente e não relacionado ao Google Home (`parameters` nunca validado contra `{min,max,step}`, mesmo hoje, só para HA). O valor 0–255 é, de fato, vazamento do Home Assistant, não decisão do domínio — e isso já havia sido flagrado pontualmente pelo próprio GH04, sem ainda virar decisão estrutural. Nada disso bloqueia a v1.6.0 aprovada; é dívida técnica real, não urgente, com escopo de retrabalho pequeno se resolvida depois.
