# DSG-01 — Smart Home Design Alignment: UX State Audit

**Status:** Concluído (2026-10-04)
**Tipo:** Design/UX — não contém alterações de código, backend ou schema.
**Branch:** `feature/dsg-01` em `ixora-infra`
**Referências:** ADR-037 (CSDM), ADR-045 (Canonical Provider Model), CSDM Spec

---

## Objetivo

Aplicar nas especificações de design as correções identificadas na auditoria visual das cinco telas de Smart Home, alinhando o design ao modelo semântico Provider → Connection → Device antes que qualquer implementação de UI comece. Este card não antecipa decisões arquiteturais abertas: onde uma decisão ainda não foi tomada (DEV-01, CAT-01, PRV-02), o design representa o estado de forma neutra e documenta a dependência.

---

## Telas auditadas

| Arquivo de referência | Tela | Spec |
|---|---|---|
| `gerenciar_conexoes.jpg` | Aba Fornecedores — listagem de conexões | [dsg-01-screen-gerenciar-conexoes.md](dsg-01-screen-gerenciar-conexoes.md) |
| `formulario_adicionar_provider.jpg` | Formulário de nova conexão | [dsg-01-screen-formulario-conexao.md](dsg-01-screen-formulario-conexao.md) |
| `tela_lista_dispositivos.jpg` | Aba Dispositivos — visão geral | [dsg-01-screen-lista-dispositivos.md](dsg-01-screen-lista-dispositivos.md) |
| `lista_dispositivos_home_assistant.jpg` | Lista de dispositivos por provider (HA) | [dsg-01-screen-lista-dispositivos.md](dsg-01-screen-lista-dispositivos.md) (§3) |
| `bottom_sheet_ao_clicar_mais_adicionar_dispositivos.jpg` | Bottom sheet de seleção de provider | [dsg-01-screen-bottom-sheet-provider.md](dsg-01-screen-bottom-sheet-provider.md) |

---

## Correções aplicadas (resumo)

| # | Correção | Tela(s) afetada(s) |
|---|---|---|
| 1 | Remoção de `entity_id` e identificadores internos de provider da UI | `lista_dispositivos_home_assistant.jpg` |
| 2 | Remoção da seção "Câmeras de Segurança" e live preview | `lista_dispositivos_home_assistant.jpg` |
| 3 | Nome do provider corrigido: `GEEVO` / `Gevvo` → **Govee** | `bottom_sheet_ao_clicar_mais_adicionar_dispositivos.jpg` |
| 4 | "Testar conexão" removido do menu de device; permanece apenas na ProviderConnection | `tela_lista_dispositivos.jpg` |
| 5 | Device state prevê `loading` / `unknown` / `stale` / `error` além de `online` / `offline` | `tela_lista_dispositivos.jpg`, `lista_dispositivos_home_assistant.jpg` |
| 6 | Formulário de conexão orientado por `connection_methods` do provider, não fixo | `formulario_adicionar_provider.jpg` |
| 7 | Google Home não recebe formulário de credencial; recebe fluxo nativo de SDK | `formulario_adicionar_provider.jpg` |
| 8 | Catálogo de providers referenciado como `GET /provider-types` (schema-driven) | `bottom_sheet_ao_clicar_mais_adicionar_dispositivos.jpg` |
| 9 | "+Adicionar Dispositivo" renomeado e ressignificado como "+Adicionar Conexão" | `tela_lista_dispositivos.jpg`, `bottom_sheet_...` |
| 10 | Binary sensors (Sensor Porta, Vazamento) removidos da lista de capabilities visíveis | `lista_dispositivos_home_assistant.jpg` |

---

## Dependências abertas

Veja o documento completo em [dsg-01-open-dependencies.md](dsg-01-open-dependencies.md).

| Dependência | Impacto no design |
|---|---|
| **DEV-01** — Device State Pipeline | Estado em tempo real de devices (connectivity, capability state) não pode ser renderizado com dados reais até DEV-01. O design usa placeholder neutro. |
| **PRV-02** — Connection Status Lifecycle | Os 6 estados de `connection.status` (ADR-045 Decisão 5) existem na spec de design; a implementação aguarda PRV-02. |
| **CAT-01** — Capability catalog (binary sensors) | Binary sensors (`contact`, `moisture`) não aparecem na UI até CAT-01 definir a modelagem CSDM. |
| **UI-PRV-01** — Mobile UI method-driven | A implementação do formulário orientado por `connection_methods` aguarda UI-PRV-01. |
