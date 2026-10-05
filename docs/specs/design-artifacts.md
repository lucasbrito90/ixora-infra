# Design Artifacts — Tabela de Roteamento

O canvas original de 412 telas foi dividido em **8 artifacts independentes por área**. Cada artifact contém seu próprio conjunto de telas e uma cópia independente do Design System Ixora (tokens claro/escuro, componentes, `bundle.css`).

**Design System é conceitualmente único.** Os 8 artifacts são cópias independentes do mesmo DS — não há 8 versões divergentes. A fonte canônica é `ixora-app/design-system/` (cópia vendorizada, com sha256 rastreado em `VERSION.md`).

> **Atenção:** não use o `ds/ixora/tokens.json` embutido em nenhum dos artifacts de tela — é uma cópia mais antiga (sem `duration` e `easing`). Use sempre `ixora-app/design-system/tokens.json`.

---

## Artifacts atuais (current)

| Área | Telas | URL |
|---|---|---|
| Smart Home — Conexões & Dispositivos | 132 | https://claude.ai/artifact/AqNLjnRW3tK3aK4mjZRdmD |
| Smart Home — Cenas & Ações | 48 | https://claude.ai/artifact/5axdL4bv4MRd56LrFfFSrF |
| Agenda | 30 | https://claude.ai/artifact/3Vq8J1BLdzQ4BNnQyd6rW8 |
| Autenticação | 22 | https://claude.ai/artifact/Bb7UkuUw3Y15tyKCKYgQ5f |
| Vibes | 74 | https://claude.ai/artifact/47FNZvzXZG4RcjG5fdu5Yk |
| Biblioteca Sonora | 54 | https://claude.ai/artifact/8UseU1XqTCH1ubQjc8719A |
| Presets | 20 | https://claude.ai/artifact/JEYdL6skyjPJEUT3osNX42 |
| Core — Home, Player, Settings, My Vibes | 32 | https://claude.ai/artifact/3wSQCVqbgs84JFqr4BsQVf |

**Total:** 132 + 48 + 30 + 22 + 74 + 54 + 20 + 32 = **412 telas** (nenhuma perdida).

---

## Canvas combinado (legacy reference)

O canvas original de 412 telas permanece disponível como referência histórica/combinada. **Não é a forma preferencial** para localizar telas de uma área específica — carregue somente o artifact da área que está implementando.

https://claude.ai/artifact/4a7Jm6CmNjWXU1STEUhH61

---

## Como navegar dentro de um artifact

Cada artifact tem:
- `project/canvas.json` — índice das telas da área (nomes de arquivo, estados, tema)
- `project/<nome>.dc.html` — tela individual (claro, escuro, estados)

**Confira sempre o `canvas.json` do artifact antes de citar um caminho.** Exemplos:
- "Home, claro" → artifact Core → `project/Main.dc.html`
- "Gerenciar Conexões" → artifact Smart Home — Conexões & Dispositivos

---

## Mapeamento por card de implementação (ixora-app)

| Card | Área | Artifact |
|---|---|---|
| UI-01 — Autenticação | Entrada, Entrar, Criar conta, Redefinir senha | **Autenticação** |
| UI-02 — Home | Home e abas | **Core — Home, Player, Settings, My Vibes** |
| UI-03 — Player | Player, menu do player | **Core — Home, Player, Settings, My Vibes** |
| UI-04 — My Vibes | My Vibes, menu, exclusão | **Core — Home, Player, Settings, My Vibes** |
| UI-05 — Vibes | Criar/editar vibe, seletor de capa | **Vibes** |
| UI-06 — Sons | Sons da vibe, ajustes de som | **Vibes** ou **Biblioteca Sonora** (verificar `canvas.json`) |
| UI-07 — Devices & Conexões | Dispositivos, conexões, providers, descoberta | **Smart Home — Conexões & Dispositivos** |
| UI-08 — Cenas | Cenas, formulário, ações da cena | **Smart Home — Cenas & Ações** |
| UI-09 — Agenda | Agendamentos, formulário de agenda | **Agenda** |
| UI-10 — Presets | Presets, detalhe, importar | **Presets** |
| UI-11 — Settings | Configurações | **Core — Home, Player, Settings, My Vibes** |
