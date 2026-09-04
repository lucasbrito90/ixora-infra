# ADR-012…016 — Auditoria de conformidade (código × decisão)

**Status:** Relatório de investigação (v1.4.0 T03 — read-only)  
**Date:** 2026-09-02  
**Escopo:** Confrontar regras normativas dos ADR-012 a ADR-016 com o comportamento em `back_vibes/`  
**Regra dura:** Nenhuma correção aplicada — nem código, nem ADRs, nem specs.

---

## Resumo executivo

| ADR | Regras extraídas | Implementada | Divergente | Não implementada | Superada |
| --- | ---: | ---: | ---: | ---: | ---: |
| ADR-012 | 13 | 11 | 0 | 0 | 2 |
| ADR-013 | 13 | 11 | 2 | 0 | 0 |
| ADR-014 | 16 | 14 | 2 | 0 | 0 |
| ADR-015 | 17 | 11 | 1 | 1 | 4 |
| ADR-016 | 16 | 9 | 2 | 1 | 4 |
| **Total** | **75** | **56** | **7** | **2** | **10** |

**Divergência mais grave (impacto v1.4.0):** a **chave de deduplicação de dispositivos** no ADR-014 declara `UNIQUE (user_id, provider, provider_device_id)`, mas a migration e o upsert usam `(provider_connection_id, provider_device_id)`. Isso bloqueia semanticamente a expansão multi-provider descrita no ADR sem uma decisão explícita sobre o novo invariante.

**Incerteza declarada:** não foi possível datar com precisão git a introdução de `SceneActionJob::$tries = 3` vs. os blocos `catch` que engolem exceções — ambos coexistem desde pelo menos a Phase 8 do Smart Home MVP; a ineficácia prática de `tries` é documentada em código (v1.3.0 observability).

**Confirmação:** nenhum arquivo em `back_vibes/` foi modificado; nenhum ADR em `docs/decisions/` foi editado.

---

## ADR-012 — Smart Home provider strategy

**Fonte:** [`ADR-012-smart-home-provider-strategy.md`](../../../decisions/ADR-012-smart-home-provider-strategy.md)

| # | Regra normativa | Veredicto | Evidência |
| --- | --- | --- | --- |
| 012-01 | IXORA usa arquitetura de **provider adapter** para todas as integrações Smart Home | **Implementada** | `back_vibes/app/SmartHome/Contracts/ProviderAdapter.php:30-64`; `back_vibes/app/SmartHome/ProviderAdapterResolver.php:18-38` |
| 012-02 | **Sem integrações diretas** com marcas individuais | **Implementada** | Único adapter concreto: `back_vibes/app/SmartHome/Adapters/HomeAssistantAdapter.php:32`; `ProviderType::mvpAllowed()` retorna só `home_assistant` em `back_vibes/app/SmartHome/ProviderType.php:36-38` |
| 012-03 | Cada integração suportada é um adapter que implementa interface compartilhada | **Implementada** | `HomeAssistantAdapter implements ProviderAdapter` em `back_vibes/app/SmartHome/Adapters/HomeAssistantAdapter.php:32` |
| 012-04 | **Backend é autoritativo** — registro de dispositivos, credenciais e status vivem em `back_vibes` (PostgreSQL) | **Implementada** | Modelos `Device`, `ProviderConnection`; sync em `back_vibes/app/SmartHome/Services/ProviderDeviceSyncService.php:44-79`; mobile lê `/api/devices` (`front_vibes/src/services/device.service.ts:75-80`) |
| 012-05 | **Mobile nunca armazena secrets** de provider — tokens/keys/URLs ficam criptografados server-side; mobile chama só a API Laravel | **Implementada** | `ProviderConnection::$hidden = ['encrypted_credentials']` em `back_vibes/app/Models/ProviderConnection.php:38`; `ProviderConnectionResource` omite credenciais em `back_vibes/app/Http/Resources/ProviderConnectionResource.php:20-29`; mobile envia token no POST mas não persiste (`front_vibes/src/views/ProviderConnectionFormPage.vue:22-25`, `front_vibes/src/services/provider-connection.service.ts:45-51`) |
| 012-06 | Interface **normalizada** — adapter normaliza operações independente do provider | **Implementada** | Contrato em `ProviderAdapter.php:30-64`; DTOs normalizados em `back_vibes/app/SmartHome/DTOs/` |
| 012-07 | Adapter deve implementar **`listDevices(connection)`** | **Implementada** | `ProviderAdapter.php:39`; `HomeAssistantAdapter.php:54-96` |
| 012-08 | Adapter deve implementar **`readStatus(connection, deviceId)`** | **Implementada** | `ProviderAdapter.php:44`; `HomeAssistantAdapter.php:98-125` *(não invocado no fluxo de sync produtivo — ver 012-09 incerteza)* |
| 012-09 | Adapter deve implementar **`executeAction(connection, deviceId, action, parameters)`** | **Implementada** | `ProviderAdapter.php:53-58`; `HomeAssistantAdapter.php:127-171`; invocado por `SceneActionJob` em `back_vibes/app/Jobs/SmartHome/SceneActionJob.php:111-116` |
| 012-10 | Adapter deve implementar **`testConnection(connection)`** | **Implementada** | `ProviderAdapter.php:63`; `HomeAssistantAdapter.php:173-208` |
| 012-11 | **Home Assistant** é o primeiro provider no MVP | **Implementada** | `ProviderAdapterResolver.php:34`; `ProviderType::HomeAssistant` único MVP em `ProviderType.php:18,36-38` |
| 012-12 | Outros providers (Tuya, Hue, Alexa, Matter, …) **não** no MVP | **Implementada** | Casos reservados sem adapter em `ProviderType.php:21-33`; resolver lança exceção para desconhecidos em `ProviderAdapterResolver.php:35-37` |
| 012-13 | MVP Phase 1 (este ADR) estabelece **apenas abstração** — sem execução real de dispositivos | **Superada** | Execução real via `SceneActionJob` + HA adapter desde Phase 8 / releases posteriores; job ativo em `SceneActionJob.php:38-53`. **Origem:** Smart Home Foundation Phase 8 (~v1.1.0), consolidado v1.2.0–v1.3.0 |

**Incerteza (012-08):** `readStatus()` existe no contrato e no adapter HA, mas nenhum serviço produtivo o chama fora de testes (`grep readStatus` limita-se a adapter, contrato e `HomeAssistantAdapterTest.php`). O ADR-012 exige o método na interface, não seu uso em runtime — veredicto **Implementada** para o contrato; uso em refresh de status individual é **Não implementada** fora de sync via `listDevices`.

---

## ADR-013 — Home Assistant as first provider

**Fonte:** [`ADR-013-home-assistant-first-provider.md`](../../../decisions/ADR-013-home-assistant-first-provider.md)

| # | Regra normativa | Veredicto | Evidência |
| --- | --- | --- | --- |
| 013-01 | **Home Assistant** é o primeiro provider Smart Home | **Implementada** | Mesma evidência 012-11 |
| 013-02 | Conexão configurada **manualmente** (base URL + long-lived access token) | **Implementada** | Payload em `StoreProviderConnectionRequest.php:26-29`; form mobile em `ProviderConnectionFormPage.vue:49-67` |
| 013-03 | Credenciais **criptografadas no backend** | **Implementada** | `ProviderConnection::setEncryptedCredentials()` usa `Crypt::encryptString` em `back_vibes/app/Models/ProviderConnection.php:70-73` |
| 013-04 | **Sem** local network discovery (mDNS/Zeroconf) no MVP | **Implementada** | Nenhum código de discovery; URL manual obrigatória no form/API |
| 013-05 | **Sem** Matter/Thread/Zigbee direto da IXORA no MVP | **Implementada** | Sem adapters/protocolos RF; apenas HA REST |
| 013-06 | **Sem** HA WebSocket / long-polling / event bus no MVP — REST only | **Implementada** | `HomeAssistantAdapter` usa só `Http::get/post` REST em `HomeAssistantAdapter.php:63,105,151-152,182` |
| 013-07 | **Sem** automatic token refresh no MVP | **Implementada** | Nenhum fluxo de refresh de token no codebase |
| 013-08 | MVP: **uma** conexão de provider por usuário por tipo de provider | **Implementada** | `UNIQUE (user_id, provider)` em `back_vibes/database/migrations/2026_06_14_000001_create_provider_connections_table.php:24`; teste em `ProviderConnectionModelTest.php:159` |
| 013-09 | **Encrypt access token at rest** via Laravel `encrypt()` / `Crypt::encryptString()` | **Implementada** | `ProviderConnection.php:72` |
| 013-10 | **Nunca expor token ao mobile** — `ProviderConnectionResource` omite token | **Implementada** | `ProviderConnectionResource.php:20-29`; `$hidden` no model `ProviderConnection.php:38` |
| 013-11 | **Validar base URL** — rejeitar URLs non-HTTPS no MVP (override opcional para dev local) | **Divergente** | Validação sempre `url:https` em `StoreProviderConnectionRequest.php:27` e `UpdateProviderConnectionRequest.php:27`; config `allow_http` existe mas **não é consultada** em validação (`back_vibes/config/smart_home.php:25` sem uso em FormRequests). **Pré-existente v1.1.0** |
| 013-12 | **Test connection on create** — `POST /api/provider-connections` chama `testConnection()` antes de persistir; retorna 422 se unreachable | **Divergente** | `ProviderConnectionController::store()` persiste sem chamar adapter: `back_vibes/app/Http/Controllers/Api/ProviderConnectionController.php:40-50`; testes de store não fake HA (`ProviderConnectionApiTest.php:121-132`). **Pré-existente v1.1.0** |
| 013-13 | HA REST surface MVP: `GET /api/states`, `GET /api/states/<id>`, `POST /api/services/...`, `GET /api/` | **Implementada** | `HomeAssistantAdapter.php:63,105,151-152,182` |

### Mapeamento HA REST (013-13)

| Endpoint HA (ADR) | Uso no adapter | Evidência |
| --- | --- | --- |
| `GET /api/states` | `listDevices()` | `HomeAssistantAdapter.php:63` |
| `GET /api/states/<entity_id>` | `readStatus()` | `HomeAssistantAdapter.php:105` |
| `POST /api/services/<domain>/<service>` | `executeAction()` | `HomeAssistantAdapter.php:151-152` |
| `GET /api/` | `testConnection()` | `HomeAssistantAdapter.php:182` |

---

## ADR-014 — Device abstraction and deduplication

**Fonte:** [`ADR-014-device-abstraction-and-deduplication.md`](../../../decisions/ADR-014-device-abstraction-and-deduplication.md)

| # | Regra normativa | Veredicto | Evidência |
| --- | --- | --- | --- |
| 014-01 | IXORA **possui** o registro de dispositivo — provider é fonte de dados, não o registry | **Implementada** | `Device` model; sync upsert em `ProviderDeviceSyncService.php:95-124` |
| 014-02 | **Dedupe key:** `(user_id, provider, provider_device_id)` | **Divergente** | Upsert usa `(provider_connection_id, provider_device_id)` em `ProviderDeviceSyncService.php:101-105`; comentário interno confirma em `ProviderDeviceSyncService.php:89` |
| 014-03 | Sync deve **atualizar** registros existentes, não inserir duplicatas | **Implementada** | `Device::updateOrCreate(...)` em `ProviderDeviceSyncService.php:101-115`; teste dedup em `ProviderConnectionSyncApiTest.php:418+` |
| 014-04 | HA `entity_id` mapeia diretamente para `provider_device_id` | **Implementada** | `HomeAssistantAdapter::mapDevice()` em `HomeAssistantAdapter.php:273-274` |
| 014-05 | Cross-provider dedupe **não** exigido no MVP | **Implementada** | Sem lógica de merge cross-provider |
| 014-06 | Constraint MVP: `UNIQUE (user_id, provider, provider_device_id)` | **Divergente** | Migration aplica `UNIQUE (provider_connection_id, provider_device_id)` em `back_vibes/database/migrations/2026_06_14_000002_harden_devices_table.php:98-101`. **Pré-existente v1.1.0** (Phase 4A schema hardening) |
| 014-07 | Modelo de device MVP inclui campos `status`, `last_seen_at`, `updated_at`, rename `provider_device_id` | **Implementada** | Migration `2026_06_14_000002_harden_devices_table.php:44-46,57-58,92-94`; model `Device.php:33-43` |
| 014-08 | Status normalizado: `online \| offline \| unknown` | **Implementada** | `DeviceStatus` enum em `back_vibes/app/SmartHome/DeviceStatus.php:16-20`; mapping HA em `HomeAssistantAdapter.php:290-296` |
| 014-09 | Status refrescado do provider quando conexão online e sync roda | **Implementada** | Upsert grava `$dto->status` em `ProviderDeviceSyncService.php:111`; sync bem-sucedido em `ProviderDeviceSyncService.php:64-78` |
| 014-10 | Provider inacessível → status do dispositivo vira **`unknown`**; **não** permanece `online` do sync anterior | **Implementada** | Ver comparação lado a lado abaixo |
| 014-11 | Mobile Devices tab deve mostrar status por dispositivo com indicador visual | **Implementada** | `front_vibes/src/views/DevicesPage.vue:105-106`; util `device-status.ts:16` |
| 014-12 | MVP pode tratar provider indisponível como todos os devices → `unknown` | **Implementada** | `markConnectionUnreachable()` em `ProviderDeviceSyncService.php:155-162` |
| 014-13 | Dispositivos **ausentes** da resposta do provider → `offline` (ou `unknown`) | **Implementada** | `markAbsentDevicesOffline()` marca `offline` em `ProviderDeviceSyncService.php:135-145` — ADR permite `offline` ou `unknown` |
| 014-14 | Mobile: sem entradas duplicadas por identidade de provider | **Implementada** | Unique constraint + upsert; teste `ProviderConnectionSyncApiTest.php:418` |
| 014-15 | Mobile **não** armazena status de device localmente no MVP — sempre busca da API | **Implementada** | `device.service.ts` busca `/api/devices` sem cache persistente de status; composable `useDevices.ts` mantém estado reativo de sessão apenas |
| 014-16 | Rename `external_id` → `provider_device_id` | **Implementada** | `2026_06_14_000002_harden_devices_table.php:57-58` |

### Política de status — provider inacessível (atenção específica T03)

**Trecho ADR-014 (normativo):**

> If the provider connection is **unavailable** (timeout, auth failure, unreachable), device status becomes **`unknown`**. It does **not** remain `online` from the prior sync.  
> — `ADR-014-device-abstraction-and-deduplication.md:98-99`

**Trecho código (comportamento real no sync failure):**

```155:162:back_vibes/app/SmartHome/Services/ProviderDeviceSyncService.php
    private function markConnectionUnreachable(ProviderConnection $connection): void
    {
        $connection->status = ConnectionStatus::Unreachable->value;
        $connection->save();

        Device::where('provider_connection_id', $connection->id)
            ->update(['status' => DeviceStatus::Unknown->value]);
    }
```

**Veredicto explícito:** **Implementada**. O sync, ao falhar `listDevices()`, marca a conexão como `unreachable` **e** todos os dispositivos da conexão como `unknown`. Teste de regressão: `ProviderConnectionSyncApiTest.php:394-411`. A suspeita de que apenas a conexão mudaria de status **não se confirma** no código atual — o docblock da classe (`ProviderDeviceSyncService.php:27`) menciona só status da conexão, mas a implementação cumpre o ADR.

### Chave de deduplicação — comparação lado a lado

| Fonte | Chave declarada | Evidência |
| --- | --- | --- |
| **ADR-014** | `(user_id, provider, provider_device_id)` | `ADR-014-device-abstraction-and-deduplication.md:58,67` |
| **Migration** | `(provider_connection_id, provider_device_id)` | `2026_06_14_000002_harden_devices_table.php:98-101` |
| **Upsert runtime** | `(provider_connection_id, provider_device_id)` | `ProviderDeviceSyncService.php:101-105` |

**Veredicto:** **Divergente**. Semanticamente equivalente enquanto existir no máximo uma conexão por `(user_id, provider)` (ADR-013-08), mas **incompatível** com multi-instância HA por usuário previsto na v1.4.0 sem alterar ADR ou código. **Pré-existente v1.1.0.**

---

## ADR-015 — Vibe device action architecture

**Fonte:** [`ADR-015-vibe-device-action-architecture.md`](../../../decisions/ADR-015-vibe-device-action-architecture.md)

| # | Regra normativa | Veredicto | Evidência |
| --- | --- | --- | --- |
| 015-01 | Device actions **anexadas a vibes**, não a schedules | **Superada** | v1.3.0: actions em `scene_actions`; vibe referencia scene via `scene_id`. Release: `ixora-infra/docs/releases/v1.3.0-vibe-scene-unification.md:13-17`. Migration drop: `2026_09_02_232728_drop_vibe_device_actions_table.php:11-15` |
| 015-02 | `vibe_device_actions` é coleção **no vibe** | **Superada** | Tabela `vibe_device_actions` removida; actions em `Scene` → `scene_actions`. **Origem: v1.3.0** |
| 015-03 | **Scheduler não invoca** device actions (MVP ou futuro sem nova spec) | **Superada** | v1.2.0 integra dispatch pós-schedule via `DispatchDueSchedulesCommand.php:80-85,190-218`; governado por ADR-022/023, não por ADR-015. **Origem: v1.2.0** |
| 015-04 | **Play path:** mobile inicia execução via API ao tocar play | **Implementada** | `POST /api/vibes/{vibe}/smart-home/dispatch` em `routes/api.php:105`; client `front_vibes/src/services/smart-home-dispatch.service.ts:35-77` |
| 015-05 | Actions são **opcionais** — vibe sem actions comporta-se como hoje | **Implementada** | `VibeSmartHomeDispatchService.php:31-37` retorna vazio se `scene_id === null` |
| 015-06 | MVP action types: **`turn_on`, `turn_off`, `toggle`** | **Implementada** | `HomeAssistantAdapter::ACTION_SERVICE_MAP` em `HomeAssistantAdapter.php:48-52`; validação scene actions |
| 015-07 | Future actions (`set_brightness`, etc.) **não** no MVP | **Implementada** | `set_brightness` rejeitado em runtime (`SceneActionJobTest.php:291-301`) |
| 015-08 | Campo **`parameters` JSON** — MVP actions aceitam `null` | **Implementada** | `scene_actions.parameters` nullable; `SceneAction.php:30`; teste null params `SceneActionJobTest.php:117-128` |
| 015-09 | **`sort_order`** — execução ascendente | **Implementada** | `VibeSmartHomeDispatchService.php:86-87`; `SceneDispatchService.php:31` |
| 015-10 | **`delay_seconds`** — delay opcional antes da action disparar | **Não implementada** | Coluna existe (`2026_08_30_192810_create_scene_actions_table.php:19`); **nenhum** dispatch/job aplica delay (`SceneActionJob.php`, `VibeSmartHomeDispatchService.php`, `SceneDispatchService.php` — grep sem uso de `delay_seconds` em `app/`). **Origem provável: v1.3.0** (schema herdado de `vibe_device_actions`) |
| 015-11 | Falha de device action **não bloqueia** audio playback | **Implementada** | Dispatch fire-and-forget: `smart-home-dispatch.service.ts:13-14,72-75`; job async |
| 015-12 | Falha é **logada** | **Implementada** | `SceneActionJob.php:127-145,165-175` |
| 015-13 | **Sucesso parcial** aceitável | **Implementada** | Um job por action; falhas isoladas (`SceneActionJob.php:38` docblock ADR-023) |
| 015-14 | **Sem retry** no MVP — falhas logadas apenas | **Divergente** | Job declara `$tries = 3` (`SceneActionJob.php:47`) mas exceções são engolidas (`SceneActionJob.php:131-145`) — ver ADR-016. Comportamento efetivo = sem retry; config = retry declarado. **Pré-existente Phase 8** |
| 015-15 | Registro `vibe_device_actions` com campos MVP (`sort_order`, `updated_at`, …) | **Superada** | Substituído por `scene_actions` v1.3.0 (`2026_08_30_192810_create_scene_actions_table.php`) |
| 015-16 | **Sem** execução client-side de actions | **Implementada** | Mobile chama API; HA só via backend (`device.service.ts:17-18`, `SceneActionJob` → adapter) |
| 015-17 | Sem automações complexas / condições no model MVP | **Implementada** | Schema flat action_type + parameters; sem engine condicional |

### Modelo de ação — superada vs. contrariada (atenção específica T03)

| Aspecto | ADR-015 | Código v1.3.0+ | Classificação |
| --- | --- | --- | --- |
| Entidade de actions | `vibe_device_actions` FK → `vibes` | `scene_actions` FK → `scenes`; `vibes.scene_id` nullable | **Superada deliberadamente** |
| Registro de decisão | ADR-015 (2026-06-14) | `v1.3.0-vibe-scene-unification.md` + drop migration | Documentado em release note, **não** em ADR-015 |
| Justificativa produto | Vibe como unidade de composição | Scene reutilizável; VibeDeviceAction era “variante estreita” | Release note linha 13 |

**Veredicto:** **Superada (v1.3.0)** — mudança deliberada com release note explícita, não contradição silenciosa. ADR-015 permanece normativo para o período v1.1.0–v1.2.x; a partir de v1.3.0 o modelo canônico é Scene + `scene_id`.

---

## ADR-016 — Smart Home async execution

**Fonte:** [`ADR-016-smart-home-async-execution.md`](../../../decisions/ADR-016-smart-home-async-execution.md)

| # | Regra normativa | Veredicto | Evidência |
| --- | --- | --- | --- |
| 016-01 | Execução de device actions é **sempre assíncrona** | **Implementada** | `SceneActionJob implements ShouldQueue` em `SceneActionJob.php:38`; dispatch via `SceneActionJob::dispatch()` |
| 016-02 | **Sem** chamadas HTTP inline a provider em Controller / FormRequest / Artisan síncrono | **Implementada** | Grep em `Http/Controllers/**` sem `Http::` ou `executeAction`; sync chama só `listDevices` (I/O provider permitido para sync, fora de action execution) |
| 016-03 | Execução **queue-backed** via Laravel queue | **Implementada** | `SceneActionJob.php:52` `onQueue('smart-home')`; worker config em `config/smart_home.php:52-56` |
| 016-04 | API registra pedido e despacha job — resposta **não espera** provider | **Implementada** | `VibeSmartHomeDispatchController.php:48-61` retorna summary imediato |
| 016-05 | Falhas de provider **não** viram erro IXORA API para mobile | **Implementada** | Job engole exceções; API dispatch sempre 200 com counts |
| 016-06 | **`schedules:dispatch-loop` não invoca** device actions | **Superada** | `DispatchDueSchedulesCommand` chama `VibeSmartHomeDispatchService` pós-commit (`DispatchDueSchedulesCommand.php:80-85`); ADR-023 v1.2.0 redefine integração — enqueue **assíncrono**, loop não bloqueia |
| 016-07 | Phase 1: trigger endpoint play **não implementado** | **Superada** | `POST /api/vibes/{id}/smart-home/dispatch` existe (`routes/api.php:105`) |
| 016-08 | Phase 1: **`SmartHomeActionJob` não implementado** | **Superada** | Job atual: `SceneActionJob` (v1.3.0 renomeou/substituiu `SmartHomeActionJob`) |
| 016-09 | Phase 1: sem queue jobs / sem `ActionExecutionLog` / sem play endpoint | **Superada** | Jobs e endpoint existem desde Phase 8+ |
| 016-10 | **`ActionExecutionLog`** (futuro) — não implementado Phase 1 | **Não implementada** | Nenhuma tabela/model `action_execution_logs` no codebase (`grep` vazio) |
| 016-11 | User offline ao play → **sem job** dispatched, sem retry offline | **Implementada** | `smart-home-dispatch.service.ts:38-40` skip silencioso |
| 016-12 | Provider offline quando job roda → worker captura, loga falha | **Implementada** | `SceneActionJob.php:137-145`; `HomeAssistantAdapter` retorna `ActionResult` failed em `ConnectionException` (`HomeAssistantAdapter.php:153-159`) |
| 016-13 | Provider lento → timeout é falha, **não retried** no MVP | **Divergente** | Timeout 30s (`SceneActionJob.php:45`); `$tries = 3` declarado mas **ineficaz** — ver abaixo. Comportamento efetivo = single attempt. **Pré-existente Phase 8** |
| 016-14 | **Sem** guaranteed execution — best-effort | **Implementada** | Fire-and-forget mobile + job swallow |
| 016-15 | **Sem** guaranteed retry/backoff no MVP | **Divergente** | Config `job_tries => 3` em `config/smart_home.php:55` espelha `$tries = 3`; exceções nunca relançadas |
| 016-16 | Reutiliza queue worker existente — **sem** worker dedicado Smart Home | **Implementada** | Comentário ADR-016 em `config/smart_home.php:39-41`; fila nomeada `smart-home` no worker compartilhado |

### Retry / `tries` em `SceneActionJob` (atenção específica T03)

**Política ADR-016 (normativo):**

> **Provider intermittently slow** \| Job has a configurable timeout. Timeout is a failure — logged, not retried in MVP.  
> — `ADR-016-smart-home-async-execution.md:87`

> **Guaranteed retry with backoff in MVP** \| Deferred — retry policy is a future spec  
> — `ADR-016-smart-home-async-execution.md:132`

**Código — configuração de retry:**

```45:47:back_vibes/app/Jobs/SmartHome/SceneActionJob.php
    public int $timeout = 30;

    public int $tries = 3;
```

**Código — exceções engolidas (sem rethrow):**

```131:145:back_vibes/app/Jobs/SmartHome/SceneActionJob.php
        } catch (UnsupportedSmartHomeActionException $e) {
            Log::warning('SceneActionJob: unsupported action type — skipping.', [
                ...$context,
                'outcome' => SmartHomeActionOutcome::Unsupported->value,
                'exception_class' => $e::class,
            ]);
        } catch (Throwable $e) {
            Log::error('SceneActionJob: unexpected error executing action.', [
                ...$context,
                'outcome' => SmartHomeActionOutcome::Failure->value,
                'exception_class' => $e::class,
            ]);

            $this->notifyActionFailed($action, $pushEvents);
        }
```

**Documentação interna confirma ineficácia:**

```73:82:back_vibes/app/Telemetry/SmartHome/SmartHomeActionTelemetry.php
 * - SceneActionJob::handle() never lets any exception escape it — both
 *   its own UnsupportedSmartHomeActionException catch block and its
 *   generic Throwable catch-all log and swallow, unconditionally. ...
 *   Laravel's queue retry mechanism (`tries = 3`) is
 *   therefore never actually triggered by this job in practice, a
 *   pre-existing architectural fact this phase does not change
```

**Teste que fixa contrato “no throw”:**

```144:150:back_vibes/tests/Feature/SmartHome/SceneActionJobTest.php
it('logs a warning on a failed ActionResult but does not throw', function () {
    Http::fake([SCENE_JOB_HA_BASE.'/api/services/*' => Http::response([], 500)]);
    ...
    expect(fn () => runSceneJob($action))->not->toThrow(Throwable::class);
```

**Veredicto explícito sobre `tries`:** **Divergente**. `$tries = 3` **não surte efeito** para falhas de provider — o job completa com sucesso do ponto de vista do queue worker porque nenhuma exceção escapa `handle()`. Falhas de transporte retornam `ActionResult(success: false)` dentro do `try`, também sem throw. O comportamento **efetivo** alinha-se ao ADR (“sem retry MVP”); a **configuração declarada** contradiz o ADR e induz falsa expectativa operacional. **Pré-existente à v1.4.0** (Phase 8 Smart Home MVP).

---

## Divergências consolidadas

Ordenadas por gravidade (impacto potencial na v1.4.0 multi-provider e operação).

| Gravidade | Regra violada | Comportamento atual | Versão de origem | Impacto v1.4.0 |
| --- | --- | --- | --- | --- |
| **Alta** | ADR-014-02/06: dedupe `(user_id, provider, provider_device_id)` | Unique + upsert em `(provider_connection_id, provider_device_id)` | **v1.1.0** (migration `2026_06_14_000002`) | Multi-instância HA por usuário exige decidir se ADR ou schema prevalece antes de remover constraint `uq_provider_connections_user_provider` |
| **Alta** | ADR-015-01/02: actions no vibe (`vibe_device_actions`) | Actions em `scene_actions`; vibe via `scene_id` | **v1.3.0** (superada documentada) | v1.4.0 deve tratar Scene como modelo canônico; ADR-015 normativo está desatualizado (fora de escopo desta task corrigir) |
| **Média** | ADR-013-12: test connection on create → 422 | Store persiste conexão sem `testConnection()` | **v1.1.0** | Conexões inválidas entram no DB; primeiro sync falha (502 + devices unknown) em vez de rejeição na criação |
| **Média** | ADR-016-13/15 + ADR-015-14: sem retry MVP | `$tries=3` declarado; zero retries efetivos | **Phase 8 / ~v1.1.0** | Operadores podem assumir 3 tentativas vendo config/worker `--tries=3`; observabilidade de falha única |
| **Média** | ADR-015-10: `delay_seconds` dispara delay antes da action | Campo persistido; dispatch imediato de todos os jobs | **v1.3.0** (schema Scene) | Sequences temporizadas de cena não funcionam; UX pode mostrar delay configurado sem efeito |
| **Baixa** | ADR-013-11: override HTTP dev via config | `allow_http` em config não ligado à validação; sempre `url:https` | **v1.1.0** | Dev local HTTP requer contornar validação ou usar HTTPS |
| **Baixa** | ADR-016-10: `ActionExecutionLog` futuro | Tabela/model inexistentes | **Pré-existente** (nunca implementado) | Auditoria de execução continua só via logs/métricas |
| **Informativa** | ADR-015-03 / ADR-016-06: scheduler não invoca actions | Scheduler enfileira dispatch pós-commit (async) | **v1.2.0** (superada por ADR-023) | Comportamento intencional v1.2.0; ADR-015/016 textos originais obsoletos neste ponto |

**Nota sobre status unknown (T03):** a divergência suspeitada **não se materializa** — código atual conforme ADR-014-10/12. Nenhuma entrada na tabela acima.

---

## Regras superadas (referência rápida)

| ADR | Regra | Substituída por | Versão |
| --- | --- | --- | --- |
| 012-13 | MVP Phase 1 sem execução real | Phase 8 jobs + HA adapter | v1.1.0+ |
| 013-08 | Uma conexão/user/provider *(ainda implementada; ver divergência multi-provider futura)* | — | — |
| 014-06 | *(parcialmente superada por schema-review §4.1)* | `(provider_connection_id, provider_device_id)` | v1.1.0 |
| 015-01/02/15 | `vibe_device_actions` no vibe | Scene + `scene_id` | v1.3.0 |
| 015-03 | Scheduler não invoca actions | ADR-023 enqueue pós-schedule | v1.2.0 |
| 016-06 | dispatch-loop não invoca actions | `DispatchDueSchedulesCommand` enqueue async | v1.2.0 |
| 016-07/08/09 | Phase 1 documentation-only | Endpoint + jobs shipped | v1.1.0 Phase 8 |

---

## Verificação final

| Check | Resultado |
| --- | --- |
| `cd back_vibes && git status --short` | ✅ vazio (nenhuma modificação) |
| `cd ixora-infra && git status --short` | ✅ apenas `?? docs/specs/smart-home/multi-provider/` (este arquivo) |
| Nenhum arquivo em `docs/decisions/` modificado | ✅ confirmado |
| Nenhuma correção aplicada | ✅ confirmado |

---

## Metodologia

1. Leitura integral dos cinco ADRs em `ixora-infra/docs/decisions/`.
2. Extração de afirmações normativas (deve/must/nunca, tabelas de decisão, constraints).
3. Verificação exclusivamente no código `back_vibes/` e clientes mobile quando a regra exige comportamento client-side.
4. Evidência obrigatória `arquivo:linha` por veredicto.
5. Classificação temporal: toda divergência marcada **pré-existente à v1.4.0** com versão de origem quando determinável (v1.1.0 Smart Home Foundation, v1.2.0 scheduler automations, v1.3.0 scenes/unification).
