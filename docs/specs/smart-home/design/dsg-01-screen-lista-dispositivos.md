# DSG-01 — Tela: Lista de Dispositivos

**Referências visuais:**
- `TELAS_CONEXOES/tela_lista_dispositivos.jpg` (visão geral — aba Dispositivos)
- `TELAS_CONEXOES/lista_dispositivos_home_assistant.jpg` (view por provider, filtrada por HA)

**Contexto de navegação:** Gerenciar Conexões → aba "Dispositivos"

---

## 1. Estado atual observado (auditoria)

### 1.1 `tela_lista_dispositivos.jpg` — aba Dispositivos (visão geral)

- Título: "Gerenciar Conexões", aba "Dispositivos" ativa
- Botão primário: "+ Adicionar Dispositivo"
- Cards de device:
  - "Lâmpada da Sala" — chips: `lâmpada`, `● online`, `ligado`
  - "Plugue da C..." — chips: `lâmpada`, `● onl...`
- Menu de contexto (⋮): **"Testar conexão"**, "Editar", "Excluir"

**Violações:**

| Violação | Gravidade |
|---|---|
| "+ Adicionar Dispositivo" implica cadastro manual de device — devices são descobertos por sync, nunca criados manualmente | Crítica |
| "Testar conexão" no menu de contexto do **device** está semanticamente errado — `testConnection` pertence à ProviderConnection, não ao Device | Crítica |
| Estado "ligado" assume que o estado de power do device é sempre conhecido — viola ADR-037 §9 (fail-open) e CSDM §5 | Alta |
| Type chip "lâmpada" para o device "Plugue da C..." parece incorreto (dado de exemplo inconsistente — a ser corrigido na implementação) | Baixa |

### 1.2 `lista_dispositivos_home_assistant.jpg` — view por provider

- Título: "Dispositivos Suportados", chip filtro "Home Assistant"
- Seções de devices agrupadas por tipo:
  - **Sensores de Temperatura**: "Sensor Ambiente 1" — `entity_id: sensor.ambient_sensor_1`, "24.5 °C"
  - **Tomadas Inteligentes**: "Tomada Cozinha" — `entity_id: switch.plug_kitchen`, toggle `off`
  - **Câmeras de Segurança**: "Câmera Entrada" — `entity_id: camera.entrance_camera`, "Idle", thumbnail de live preview
  - **Outros Dispositivos**: "Sensor Porta", "Vazamento Banheiro", "TV Sala", "Ventilador Quarto"

**Violações:**

| Violação | Gravidade |
|---|---|
| `entity_id` exibido como subtítulo de cada device (ex.: `entity_id: sensor.ambient_sensor_1`) — identificador interno de provider; viola ADR-045 Decisão 7 e ADR-037 §7 | Crítica |
| Seção "Câmeras de Segurança" com live preview — câmera é deferida para CAT-01, viola ADR-045 Decisão 8 | Crítica |
| "Sensor Porta" e "Vazamento Banheiro" como binary sensors renderizados na UI sem capability model definida — aguarda CAT-01 | Alta |
| "24.5 °C" como dado de estado em tempo real — requer DEV-01 que ainda não está implementado; inventar dados funcionais viola o princípio do card | Alta |
| Toggle `off` em "Tomada Cozinha" assume estado conhecido (deve prever `unknown`) | Média |

---

## 2. Especificação corrigida

### 2.1 Aba "Dispositivos" — visão geral

```
Gerenciar Conexões
  [Cenas]                        [+ Adicionar conexão]

  [Fornecedores]    [Dispositivos]

  ┌─────────────────────────────────────────┐
  │ [ícone]  Lâmpada da Sala            ⋮  │
  │          lâmpada  ● online              │
  └─────────────────────────────────────────┘

  ┌─────────────────────────────────────────┐
  │ [ícone]  Plugue da Cozinha          ⋮  │
  │          tomada  ● offline              │
  └─────────────────────────────────────────┘
```

**Mudança do CTA primário:**
- De: `+ Adicionar Dispositivo`
- Para: `+ Adicionar conexão` (navega para o fluxo de nova ProviderConnection)

Devices não são adicionados diretamente — são descobertos via sync de uma ProviderConnection. O botão primário da aba "Dispositivos" é o mesmo ponto de entrada do botão "+ Adicionar fornecedor" da aba "Fornecedores" (ou pode ser ocultado quando há conexões ativas, dando lugar a um link "Sincronizar via fornecedor").

**Menu de contexto do device (⋮):**

```
• Ver detalhes
• Editar nome
• Remover
```

"Testar conexão" é **removido** do menu de contexto do device. Se o usuário precisa testar a conexão, faz isso pelo menu ⋮ da ProviderConnection na aba "Fornecedores".

### 2.2 Dados do device card (CSDM only)

Cada card de device exibe **apenas dados do CSDM** — nunca identificadores de provider:

| Campo | Fonte | Exibido como |
|---|---|---|
| Nome | `Device.name` | Label principal |
| Tipo | `Device.type` | Chip de tipo (ex.: "lâmpada", "tomada", "sensor") |
| Conectividade | `Device.connectivity` | Chip de status de rede |

`Device.capabilities`, `Device.state` e `Device.metadata` não aparecem diretamente no card de listagem — apenas no detalhe do device (fora do escopo deste card).

**O que nunca aparece no card:**
- `entity_id`, `provider_device_id`, qualquer identificador nativo de provider
- Credenciais, URL base, API key

### 2.3 Estados de `Device.connectivity` no card

| Valor | Visual | Comportamento |
|---|---|---|
| `online` | `● online` (verde) | Normal |
| `offline` | `● offline` (vermelho/cinza) | Card atenuado; estado de capabilities = indisponível |
| `unknown` | `○ —` (cinza neutro) | Sem indicação de estado — não assumir online nem offline |

**Estado de capability no card (simplificado):**

O card de listagem não exibe estado de capability individual (ex.: `ligado`/`desligado`). Isso vai para a tela de detalhe do device. O card de listagem exibe apenas conectividade.

> **Dependência DEV-01:** O chip `● online` / `● offline` / `○ —` só pode refletir dados reais após DEV-01 implementar o pipeline de estado. Até lá, exibir `○ —` para todos os devices (estado neutro, sem assumir nada).

### 2.4 View filtrada por provider

A view `lista_dispositivos_home_assistant.jpg` corresponde à aba "Dispositivos" filtrada por uma ProviderConnection específica. A spec é a mesma do §2.2 acima, com:

- Header: nome do provider + ícone como chip de filtro ativo
- Devices listados pertencem àquela ProviderConnection

**Agrupamento por `Device.type`:**
O agrupamento em seções por tipo de device (`DeviceType`) pode ser mantido — o `Device.type` vem do CSDM e é válido como critério de organização visual. Não agrupar por provider-specific category.

### 2.5 Remoção de "Câmeras de Segurança"

A seção "Câmeras de Segurança" e qualquer live preview de câmera são **removidos completamente**. Câmera não é uma capability modelada no CSDM atual (ADR-045 Decisão 8 — deferido para CAT-01).

Se um device do tipo câmera estiver presente na ProviderConnection, deve aparecer na seção "Outros Dispositivos" sem preview e sem capability de visualização. Label: o `Device.name` canônico. Nenhum thumbnail, nenhum status "Idle".

### 2.6 Remoção de binary sensors como capabilities

"Sensor Porta" (`contact`) e "Vazamento Banheiro" (`moisture`) são binary sensors. O CSDM não tem modelagem definida para binary sensors até CAT-01 (ADR-037 §8.3 marca `binary` como tipo de constraint não ratificado). Esses devices, se presentes, devem aparecer em "Outros Dispositivos" sem capability renderizada — apenas nome e tipo (`Device.type`), sem toggle, sem estado de capability.

### 2.7 Estado de dado em tempo real

"24.5 °C" (leitura de temperatura) é um dado de estado de capability (`current_temperature`, `access: "read"`). Esse tipo de dado requer DEV-01 para ser lido em tempo real. O design reserva o espaço visual para o dado, mas exibe `—` ou skeleton até DEV-01 estar disponível. **Não inventar valores de exemplo como dado real.**

---

## 3. O que não fazer

- Não exibir `entity_id` ou qualquer identificador de provider como dado visível.
- Não manter "Testar conexão" no menu ⋮ do device.
- Não manter "+ Adicionar Dispositivo" como ação de criação manual.
- Não exibir live preview de câmera.
- Não renderizar binary sensors como capability suportada.
- Não exibir estado de capability assumido como conhecido quando DEV-01 não está implementado.

---

## 4. Dependências abertas

| Dependência | Impacto |
|---|---|
| **DEV-01** | `Device.connectivity` e `Device.state` (capabilities) em tempo real. O chip de conectividade exibe `—` até DEV-01. Nenhum dado de temperatura, estado de power, ou toggle é renderizado com dado real antes de DEV-01. |
| **CAT-01** | Binary sensors (`contact`, `moisture`) não aparecem como capability até CAT-01 definir a modelagem CSDM. Devices desse tipo ficam em "Outros Dispositivos" sem capability. |
| **CAT-01** | Câmera não aparece como capability de visualização. Device de câmera listado como genérico em "Outros Dispositivos". |
