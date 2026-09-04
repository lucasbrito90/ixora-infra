# Smart Home — Home Assistant coupling map

**Status:** Investigation report (v1.4.0 T02 — read-only audit)  
**Date:** 2026-09-02  
**Feature ID:** `smart-home/multi-provider`  
**Repos scanned:** `back_vibes`, `front_vibes`, `ixora-admin`

---

## 1. Method

From workspace root (`projeto_vibes/`), case-insensitive combined search:

```bash
grep -rniE 'home_assistant|homeassistant|home assistant' \
  back_vibes/app back_vibes/routes back_vibes/config back_vibes/database back_vibes/tests \
  front_vibes/src \
  ixora-admin
```

| Scope | Grep line count |
| --- | ---: |
| `back_vibes/{app,routes,config,database,tests}` | 127 |
| `front_vibes/src` | 23 |
| `ixora-admin` (whole repo) | 0 |
| **Total** | **150** |

Map entries below: **150** (must match grep total).

---

## 2. Backend (`back_vibes`)

### 2.1 Production code (37 occurrences)

| Arquivo:linha | Trecho | Categoria | O que quebraria |
| --- | --- | --- | --- |
| `back_vibes/app/Http/Controllers/Api/VibeSmartHomeDispatchController.php:25` | `Home Assistant` | cosmética | Docblock afirmando que não chama HA — documentação, não acoplamento. |
| `back_vibes/app/Providers/SmartHomeServiceProvider.php:7` | `HomeAssistant` | estrutural | Container registra singleton de `HomeAssistantAdapter` — wiring explícito do único adapter. |
| `back_vibes/app/Providers/SmartHomeServiceProvider.php:21` | `HomeAssistant` | estrutural | Container registra singleton de `HomeAssistantAdapter` — wiring explícito do único adapter. |
| `back_vibes/app/PushNotifications/Providers/FcmPushProvider.php:74` | `HomeAssistant` | cosmética | Docblock/comentário referenciando HA; telemetria não ramifica negócio por provider. |
| `back_vibes/app/SmartHome/Adapters/HomeAssistantAdapter.php:25` | `Home Assistant` | cosmética | Docblock; adapter inteiro é HA-specific mas estas linhas são só documentação. |
| `back_vibes/app/SmartHome/Adapters/HomeAssistantAdapter.php:27` | `Home Assistant` | cosmética | Docblock; adapter inteiro é HA-specific mas estas linhas são só documentação. |
| `back_vibes/app/SmartHome/Adapters/HomeAssistantAdapter.php:32` | `HomeAssistant` | estrutural | Classe adapter HA-only; todo I/O REST assume API Home Assistant. |
| `back_vibes/app/SmartHome/Adapters/HomeAssistantAdapter.php:235` | `home_assistant` | estrutural | Classe adapter HA-only; todo I/O REST assume API Home Assistant. |
| `back_vibes/app/SmartHome/Adapters/HomeAssistantAdapter.php:240` | `HomeAssistant` | estrutural | Classe adapter HA-only; todo I/O REST assume API Home Assistant. |
| `back_vibes/app/SmartHome/ProviderAdapterResolver.php:7` | `HomeAssistant` | estrutural | Resolver injeta e retorna somente `HomeAssistantAdapter` para slug HA; outro slug lança exceção. |
| `back_vibes/app/SmartHome/ProviderAdapterResolver.php:21` | `HomeAssistant` | estrutural | Resolver injeta e retorna somente `HomeAssistantAdapter` para slug HA; outro slug lança exceção. |
| `back_vibes/app/SmartHome/ProviderAdapterResolver.php:34` | `HomeAssistant` | estrutural | Resolver injeta e retorna somente `HomeAssistantAdapter` para slug HA; outro slug lança exceção. |
| `back_vibes/app/SmartHome/ProviderType.php:10` | `home_assistant` | cosmética | Comentário de enum. |
| `back_vibes/app/SmartHome/ProviderType.php:18` | `HomeAssistant` | estrutural | `mvpAllowed()` / `isMvpSupported()` restringem MVP a `home_assistant` apenas. |
| `back_vibes/app/SmartHome/ProviderType.php:35` | `home_assistant` | cosmética | Comentário de enum. |
| `back_vibes/app/SmartHome/ProviderType.php:38` | `HomeAssistant` | estrutural | `mvpAllowed()` / `isMvpSupported()` restringem MVP a `home_assistant` apenas. |
| `back_vibes/app/SmartHome/ProviderType.php:43` | `HomeAssistant` | estrutural | `mvpAllowed()` / `isMvpSupported()` restringem MVP a `home_assistant` apenas. |
| `back_vibes/app/SmartHome/Services/VibeSmartHomeDispatchService.php:23` | `HomeAssistant` | cosmética | Docblock afirmando que não chama HA — documentação, não acoplamento. |
| `back_vibes/app/Telemetry/PushNotifications/PushProviderTelemetry.php:15` | `HomeAssistant` | cosmética | Docblock/comentário referenciando HA; telemetria não ramifica negócio por provider. |
| `back_vibes/app/Telemetry/SmartHome/SmartHomeActionProvider.php:29` | `HomeAssistant` | estrutural | Enum de telemetria com case `home_assistant` (outros slugs normalizam para `future`). |
| `back_vibes/app/Telemetry/SmartHome/SmartHomeActionTelemetry.php:42` | `HomeAssistant` | cosmética | Docblock/comentário referenciando HA; telemetria não ramifica negócio por provider. |
| `back_vibes/app/Telemetry/SmartHome/SmartHomeActionTelemetry.php:70` | `HomeAssistant` | cosmética | Docblock/comentário referenciando HA; telemetria não ramifica negócio por provider. |
| `back_vibes/app/Telemetry/SmartHome/SmartHomeActionTelemetry.php:107` | `home_assistant` | cosmética | Docblock/comentário referenciando HA; telemetria não ramifica negócio por provider. |
| `back_vibes/app/Telemetry/SmartHome/SmartHomeProviderDeviceDomain.php:14` | `HomeAssistant` | cosmética | Docblock/comentário referenciando HA; telemetria não ramifica negócio por provider. |
| `back_vibes/app/Telemetry/SmartHome/SmartHomeProviderDeviceDomain.php:17` | `HomeAssistant` | cosmética | Docblock/comentário referenciando HA; telemetria não ramifica negócio por provider. |
| `back_vibes/app/Telemetry/SmartHome/SmartHomeProviderTelemetry.php:15` | `HomeAssistant` | cosmética | Docblock/comentário referenciando HA; telemetria não ramifica negócio por provider. |
| `back_vibes/app/Telemetry/SmartHome/SmartHomeProviderTelemetry.php:28` | `HomeAssistant` | cosmética | Docblock/comentário referenciando HA; telemetria não ramifica negócio por provider. |
| `back_vibes/app/Telemetry/SmartHome/SmartHomeProviderTelemetry.php:83` | `HomeAssistant` | cosmética | Docblock/comentário referenciando HA; telemetria não ramifica negócio por provider. |
| `back_vibes/config/smart_home.php:19` | `home_assistant` | estrutural | Chave de config `providers.home_assistant`; timeout HA lido pelo adapter. |
| `back_vibes/config/smart_home.php:20` | `Home Assistant` | cosmética | Comentário de config. |
| `back_vibes/config/smart_home.php:23` | `Home Assistant` | cosmética | Comentário de config. |
| `back_vibes/database/factories/ProviderConnectionFactory.php:25` | `Home Assistant` | cosmética | Nome legível padrão de factory para testes/seeds. |
| `back_vibes/database/factories/ProviderConnectionFactory.php:26` | `HomeAssistant` | estrutural | Factory default `provider => home_assistant` — dados sintéticos assumem HA. |
| `back_vibes/database/migrations/2026_05_01_000005_create_devices_table.php:16` | `Home Assistant` | cosmética | Comentário ou backfill histórico one-shot; não executa em runtime pós-migrate. |
| `back_vibes/database/migrations/2026_06_14_000002_harden_devices_table.php:62` | `Home Assistant` | cosmética | Comentário ou backfill histórico one-shot; não executa em runtime pós-migrate. |
| `back_vibes/database/migrations/2026_06_14_000002_harden_devices_table.php:64` | `Home Assistant` | cosmética | Comentário ou backfill histórico one-shot; não executa em runtime pós-migrate. |
| `back_vibes/database/migrations/2026_06_14_000002_harden_devices_table.php:65` | `home_assistant` | cosmética | Comentário ou backfill histórico one-shot; não executa em runtime pós-migrate. |

### 2.2 Tests (90 occurrences)

| Arquivo:linha | Trecho | Categoria | O que quebraria |
| --- | --- | --- | --- |
| `back_vibes/tests/Feature/PushNotifications/PushNotificationEventsTest.php:135` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/PushNotifications/PushNotificationEventsTest.php:145` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionApiTest.php:54` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionApiTest.php:130` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionApiTest.php:229` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionApiTest.php:239` | `home assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionModelTest.php:47` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionModelTest.php:56` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionModelTest.php:64` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionModelTest.php:164` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionModelTest.php:169` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionModelTest.php:173` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionModelTest.php:179` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionModelTest.php:184` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionModelTest.php:227` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionModelTest.php:231` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionModelTest.php:232` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionModelTest.php:235` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionModelTest.php:236` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/ProviderConnectionSyncApiTest.php:162` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/SceneActionJobTest.php:87` | `Home Assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/SceneActionJobTest.php:292` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/SmartHomeSchemaHardeningTest.php:55` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/SmartHome/VibeSmartHomeDispatchApiTest.php:246` | `Home Assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionBoundaryIntegrationTest.php:98` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionBoundaryIntegrationTest.php:109` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:91` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:101` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:104` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:121` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:136` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:152` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:184` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:196` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:216` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:217` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:296` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:310` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:333` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:358` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:385` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:406` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:462` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:506` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:521` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:538` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:543` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:555` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:565` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:589` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:613` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:652` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:677` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:698` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:699` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:742` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php:755` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeProviderBoundaryIntegrationTest.php:27` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeProviderBoundaryIntegrationTest.php:29` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeProviderBoundaryIntegrationTest.php:183` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeProviderTelemetryTest.php:15` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Feature/Telemetry/SmartHome/SmartHomeProviderTelemetryTest.php:16` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/PushNotifications/NotificationUxAlignmentTest.php:55` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/PushNotifications/NotificationUxAlignmentTest.php:77` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/PushNotifications/NotificationUxAlignmentTest.php:85` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/PushNotifications/NotificationUxAlignmentTest.php:101` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/PushNotifications/Notifications/SmartHomeProviderUnreachableNotificationTest.php:24` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/PushNotifications/Notifications/SmartHomeProviderUnreachableNotificationTest.php:30` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/PushNotifications/Notifications/SmartHomeProviderUnreachableNotificationTest.php:36` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/PushNotifications/Notifications/SmartHomeProviderUnreachableNotificationTest.php:42` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/PushNotifications/Notifications/SmartHomeProviderUnreachableNotificationTest.php:48` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/PushNotifications/Notifications/SmartHomeProviderUnreachableNotificationTest.php:54` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/PushNotifications/Notifications/SmartHomeProviderUnreachableNotificationTest.php:56` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/PushNotifications/Notifications/SmartHomeProviderUnreachableNotificationTest.php:60` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/PushNotifications/Notifications/SmartHomeProviderUnreachableNotificationTest.php:68` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/SmartHome/HomeAssistantAdapterTest.php:6` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/SmartHome/HomeAssistantAdapterTest.php:34` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/SmartHome/HomeAssistantAdapterTest.php:41` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/SmartHome/HomeAssistantAdapterTest.php:43` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/SmartHome/ProviderAdapterResolverTest.php:5` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/SmartHome/ProviderAdapterResolverTest.php:16` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/SmartHome/ProviderAdapterResolverTest.php:19` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/SmartHome/ProviderAdapterResolverTest.php:20` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/SmartHome/ProviderAdapterResolverTest.php:22` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/SmartHome/ProviderAdapterResolverTest.php:26` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/SmartHome/ProviderAdapterResolverTest.php:27` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/SmartHome/ProviderAdapterResolverTest.php:29` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/SmartHome/ProviderAdapterResolverTest.php:47` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/SmartHome/ProviderAdapterResolverTest.php:50` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `back_vibes/tests/Unit/SmartHome/ProviderAdapterResolverTest.php:51` | `HomeAssistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |

---

## 3. Mobile (`front_vibes`) and admin (`ixora-admin`)

### 3.1 Mobile production code (16 occurrences)

| Arquivo:linha | Trecho | Categoria | O que quebraria |
| --- | --- | --- | --- |
| `front_vibes/src/services/device.service.ts:17` | `Home Assistant` | cosmética | Comentário de serviço; mobile não chama provider diretamente — documentação apenas. |
| `front_vibes/src/services/provider-connection.service.ts:14` | `Home Assistant` | cosmética | Comentário de serviço; mobile não chama provider diretamente — documentação apenas. |
| `front_vibes/src/services/provider-connection.service.ts:16` | `Home Assistant` | cosmética | Comentário de serviço; mobile não chama provider diretamente — documentação apenas. |
| `front_vibes/src/services/provider-connection.service.ts:20` | `Home Assistant` | cosmética | Comentário de serviço; mobile não chama provider diretamente — documentação apenas. |
| `front_vibes/src/services/provider-connection.service.ts:21` | `home_assistant` | estrutural | Union literal TS só admite `home_assistant`; outro slug falha em type-check onde `ProviderSlug` é usado. |
| `front_vibes/src/services/scene-device-action.service.ts:17` | `Home Assistant` | cosmética | Comentário de serviço; mobile não chama provider diretamente — documentação apenas. |
| `front_vibes/src/services/smart-home-dispatch.service.ts:17` | `Home Assistant` | cosmética | Comentário de serviço; mobile não chama provider diretamente — documentação apenas. |
| `front_vibes/src/utils/device-status.ts:46` | `Home Assistant` | cosmética | Comentário JSDoc. |
| `front_vibes/src/utils/device-status.ts:49` | `home_assistant` | estrutural | Switch só mapeia `home_assistant`; outro slug cai no `default` e exibe o slug cru. |
| `front_vibes/src/utils/device-status.ts:50` | `Home Assistant` | estrutural | Switch só mapeia `home_assistant`; outro slug cai no `default` e exibe o slug cru. |
| `front_vibes/src/views/DevicesPage.vue:70` | `Home Assistant` | cosmética | String de UI/copy; não impede backend de outro provider, só texto desatualizado. |
| `front_vibes/src/views/DevicesPage.vue:71` | `Home Assistant` | cosmética | String de UI/copy; não impede backend de outro provider, só texto desatualizado. |
| `front_vibes/src/views/DevicesPage.vue:259` | `Home Assistant` | cosmética | String de UI/copy; não impede backend de outro provider, só texto desatualizado. |
| `front_vibes/src/views/ProviderConnectionFormPage.vue:23` | `Home Assistant` | cosmética | String de UI/copy; não impede backend de outro provider, só texto desatualizado. |
| `front_vibes/src/views/ProviderConnectionFormPage.vue:34` | `home_assistant` | estrutural | UI só permite/seleciona HA; usuário não cadastra outro provider pelo formulário. |
| `front_vibes/src/views/ProviderConnectionFormPage.vue:142` | `home_assistant` | estrutural | UI só permite/seleciona HA; usuário não cadastra outro provider pelo formulário. |

### 3.2 Mobile tests (7 occurrences)

| Arquivo:linha | Trecho | Categoria | O que quebraria |
| --- | --- | --- | --- |
| `front_vibes/src/composables/__tests__/useProviderConnections.test.ts:55` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `front_vibes/src/composables/__tests__/useProviderConnections.test.ts:84` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `front_vibes/src/composables/__tests__/useProviderConnections.test.ts:113` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `front_vibes/src/services/__tests__/provider-connection.service.test.ts:35` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `front_vibes/src/services/__tests__/provider-connection.service.test.ts:97` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `front_vibes/src/services/__tests__/provider-connection.service.test.ts:108` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |
| `front_vibes/src/utils/__tests__/device-status.test.ts:32` | `home_assistant` | teste/fixture | N/A — fixture ou assertion de teste; segundo provider exigiria novos casos. |

### 3.3 Admin (`ixora-admin`)

**0 occurrences.** Grep over the entire repo returned no matches.

---

## 4. Provider conditional verification (directed search)

Independent of the textual scan, searched for runtime branches on provider slug:

```bash
grep -rniE 'if\s*\(\s*\$.*provider|switch\s*\(\s*\$.*provider|match\s*\(\s*\$.*provider|\$provider\s*===|ProviderType::' \
  back_vibes/app/Http/Controllers \
  back_vibes/app/Jobs \
  back_vibes/app/Services/Scheduling \
  back_vibes/app/Http/Controllers/Api/SceneController.php \
  back_vibes/app/Http/Controllers/Api/SceneActionController.php \
  back_vibes/app/Http/Controllers/Api/SceneDispatchController.php \
  back_vibes/app/Http/Controllers/Api/VibeSmartHomeDispatchController.php \
  back_vibes/app/SmartHome \
  back_vibes/app/Models/Scene.php \
  back_vibes/app/Models/SceneAction.php \
  back_vibes/app/Models/Vibe.php \
  back_vibes/app/Console/Commands/DispatchDueSchedulesCommand.php
```

**Result:** No `if ($provider === …)` / `switch ($device->provider)` in Controllers, Jobs, Scheduler, Scene/Vibe models, or dispatch command.

Matches found only in the adapter boundary:

- `app/SmartHome/ProviderAdapterResolver.php:34` — `match` arm `ProviderType::HomeAssistant => $this->homeAssistant`
- `app/SmartHome/Adapters/HomeAssistantAdapter.php:240` — returns `ProviderType::HomeAssistant->value`

`SceneActionJob` reads `$connection->provider` only to pass it to `ProviderAdapterResolver::forProvider()` — no slug branch in the job itself (`SceneActionJob.php:100`, `109`).

**Mobile (`front_vibes/src/services/**`, `composables/**`, excluding tests):**

```bash
grep -rniE 'if\s*\(.*provider|switch\s*\(.*provider|provider\s*===|case\s+.home_assistant' \
  front_vibes/src/services front_vibes/src/composables | grep -v __tests__
```

**Result:** No matches (exit code 1). Provider-specific UI mapping exists only in `utils/device-status.ts` (`providerLabel` switch) — outside the services/composables search path but documented in §3.1.

**Additional structural gate (no grep literal match):** `StoreProviderConnectionRequest` / `UpdateProviderConnectionRequest` validate `provider` with `ProviderType::mvpAllowed()` — effectively HTTP rejects any slug other than `home_assistant` (`StoreProviderConnectionRequest.php:22-25`).

---

## 5. Quantitative summary

| Categoria | Count |
| --- | ---: |
| estrutural | 19 |
| cosmética | 34 |
| teste/fixture | 97 |
| **Total (map = grep)** | **150** |

**Grep total:** 150 · **Map rows:** 150

### Files concentrating structural coupling (production only)

| Repo | File | Structural lines |
| --- | --- | ---: |
| `back_vibes` | `back_vibes/app/SmartHome/Adapters/HomeAssistantAdapter.php` | 3 |
| `back_vibes` | `back_vibes/app/SmartHome/ProviderAdapterResolver.php` | 3 |
| `back_vibes` | `back_vibes/app/SmartHome/ProviderType.php` | 3 |
| `back_vibes` | `back_vibes/app/Providers/SmartHomeServiceProvider.php` | 2 |
| `front_vibes` | `front_vibes/src/utils/device-status.ts` | 2 |
| `front_vibes` | `front_vibes/src/views/ProviderConnectionFormPage.vue` | 2 |
| `back_vibes` | `back_vibes/app/Telemetry/SmartHome/SmartHomeActionProvider.php` | 1 |
| `back_vibes` | `back_vibes/config/smart_home.php` | 1 |
| `back_vibes` | `back_vibes/database/factories/ProviderConnectionFactory.php` | 1 |
| `front_vibes` | `front_vibes/src/services/provider-connection.service.ts` | 1 |

---

## 6. Conclusion

Home Assistant coupling is **concentrated at the provider boundary**, not in the business core. Controllers, vibe/scene dispatch services, scheduler command, and `SceneActionJob` are provider-agnostic and delegate through `ProviderAdapterResolver`. Structural blockers for a second provider are: the HA-only adapter + resolver registration, `ProviderType::mvpAllowed()` / HTTP validation, config key `smart_home.providers.home_assistant`, and on mobile the `ProviderSlug` union plus single-option connection form. The majority of grep hits (97/150) are **test fixtures**; cosmetic docblocks and UI copy account for most of the remainder.

**Nucleus vs edge:** **Edge** — multi-provider work is localized to adapter/resolver, enum allow-lists, config, and mobile connection UX; scenes, vibes, scheduler, and dispatch pipelines do not branch on HA.

---

## Verification

Final grep recount: **150** lines. Map rows: **150**. Match confirmed.

No production code, config, or test files were modified during this audit.
