# Ordem de execução da migração KMP e divisão de trabalho (Claude Code, Cursor e Claude Design)

**Status:** registro de organização, sem decisão arquitetural nova. Complementa o [`kmp-migration-plan.md`](kmp-migration-plan.md) (que continua sendo a fonte das decisões: D1 a D7, Fases 0 a 10) e não o substitui.
**Data:** 2026-09-26
**Onde acompanhar:** board "Migração Ionic → KMP" no Trello (https://trello.com/b/fFDwwmqs/migracao-ionic-kmp). O épico é https://trello.com/c/W8qysJCR.

---

## 1. Quem faz o quê

| Quem | Faz | Não faz |
| --- | --- | --- |
| **Cursor** (por prompt) | Backend (`back_vibes`), admin (`ixora-admin`), documentação e ADRs, módulo `shared` (rede, autenticação, repositórios, domínio, dados), player nativo da Fase 4 (Media3, scheduler, fade), testes desses módulos | Telas Compose, tema e componentes de UI |
| **Claude Code** (neste repositório de trabalho) | **Tema, ícones, componentes e telas em Compose** (cards DS-05 a DS-10 e UI-01 a UI-11), lendo o Design System e conferindo claro e escuro e todos os estados | Alterar o desenho por conta própria |
| **Claude Design** | **Qualquer mudança de tela e qualquer tela nova.** Também o Design System (tokens, componentes, textos, strings, ícones) e a aprovação visual, com o PO | Escrever código do app |
| **PO (Lucas)** | Aprova desenhos e versões do Design System; decide o que é produto | |

### Regras que valem para todos

1. **Os cards das telas são criados antes de a necessidade surgir** (UI-01 a UI-11 já existem no Backlog, cada um com a seção "Referência de design (obrigatória)"). Nenhuma tela nasce sem card e sem prancha aprovada.
2. **Se uma tela precisa mudar, ou se falta uma tela, o responsável pelo desenho é o Claude Design.** Quem implementa (Claude Code) registra a lacuna e espera a aprovação do PO; **não improvisa e o código nunca corrige o design por conta própria**. É a regra de `ixora-app/CLAUDE.md`.
3. **Mudança de visual é mudança do Design System:** primeiro no Claude Design (aprovada pelo PO), depois `design-system/` no `ixora-app` (procedimento em `design-system/VERSION.md`) e só então o código.
4. **Comportamento** segue o `front_vibes` (D2, feature freeze); o **visual** segue o Design System (D6). A única exceção funcional à D2 é a D7 (categorias de vibe).
5. O Cursor não lê artefatos; por isso o `ixora-app` carrega a cópia `design-system/` e o `.cursor/rules/design-system.mdc`.

---

## 2. Ordem natural de execução

"Telas" na quarta coluna quer dizer: a etapa exige tela desenhada. O Design System v1.1.2 (versão `1790449121-e047`) está aprovado, e as pranchas existem para todas as rotas do `front_vibes`.

| # | O quê | Card(s) | Quem | Precisa de tela? | Depende de |
| --- | --- | --- | --- | --- | --- |
| 1 | ADR-044, autenticação Firebase em KMP | K13 | Cursor | Não | K12 (feito) |
| 2 | Cliente HTTP (Ktor) no `shared` | K14 | Cursor | Não | K13 |
| 3 | Repositórios de leitura | K15 | Cursor | Não | K14 |
| 4 | Prova de integração contra o staging | K16 | Cursor | Não | K14, K15 |
| 5 | Resultado da Fase 2 e revisão do plano | K17 | Cursor | Não | K16 |
| em paralelo | Spec de categorias, depois `back_vibes` e `ixora-admin` | CAT-01, CAT-02, CAT-03 | Cursor | Não | CAT-01, depois CAT-02 |
| 6 | Fase 3: domínio, dados, ADR-043 | (sem card ainda) | Cursor | Não | K17 |
| 7 | Esqueleto do `androidApp` (primeiro card da Fase 4) | (sem card ainda) | Cursor | Não | Fase 3 |
| 8 a 12 | Tema, ícones e componentes em Compose | DS-05, DS-06, DS-07, DS-08, DS-09 | Claude Code | Não, só o Design System | esqueleto do `androidApp` (e DS-05 antes dos demais) |
| em paralelo | Fase 4: player nativo | (sem card ainda) | Cursor | Não | Fase 3 |
| 13 | Ícone do app no `androidApp` | DS-03 | Claude Code | Não | esqueleto do `androidApp` |
| 14 | **Fase 5: shell instalável** (autenticação, Home, Player) | UI-01, UI-02, UI-03 | Claude Code | **Sim** | Fase 4 e DS-09 |
| 15 | Teste de acessibilidade em aparelho (TalkBack) | DS-10 | Claude Code | Sim, com o APK | DS-09 e Fase 5 |
| 16 | **Fase 6: telas por área** | UI-04 a UI-11 | Claude Code | **Sim** | Fase 5 |
| 17 | Categorias e chips do Home | CAT-04 | Claude Code (UI) e Cursor (dados) | Sim (Home) | CAT-02 no staging, DS-07 e Fase 3 |

**Sem tela nem código, aguardando o PO:** DS-01 (aprovação dos desenhos; a posição do badge "Inativa" segue em aberto), DS-02 (componentes; aprovado), DS-04 (guia de movimento; implementação no DS-05).

### Restrições do plano que esta ordem respeita

- A Fase 4 só começa com a Fase 3 completa; o esqueleto do `androidApp` abre a Fase 4 (é onde moram `MediaSessionService` e foreground service).
- Tema, ícones e componentes rodam em paralelo à Fase 4. **A Fase 5 só começa com tema, ícones e componentes prontos.**
- A Fase 5 é o gate de instalabilidade: o `ixora-app` precisa estar instalável no aparelho a partir da Fase 4/5, demonstrável, e cada fase seguinte termina com algo rodando no celular.
- A Fase 3 não começa antes do K17.

---

## 3. Mapa das telas das Fases 5 e 6

Cada card de tela tem a lista das pranchas (`project/<nome>-claro|escuro.dc.html` no canvas de telas), os componentes e as strings.

| Card | Fase | Telas | Componentes principais | Bloqueio ou dependência específica |
| --- | --- | --- | --- | --- |
| UI-01 https://trello.com/c/aODfQWWs | 5 | Entrada, entrar, criar conta, esqueci a senha, sucesso | AuthForm, TextField, Button, ButtonWithIcon | Login real (ADR-044 no `androidApp`) |
| UI-02 https://trello.com/c/YgSKCO31 | 5 | Home e abas (`Main.dc.html` é o Home claro) | VibeCard, MiniPlayer, TabBar | Sem chips (vêm no CAT-04) |
| UI-03 https://trello.com/c/QbnVHtuE | 5 | Player e menu do player | SoundCard, VolumeSlider, ActionMenu | Fase 4; fase do download offline a confirmar |
| UI-04 https://trello.com/c/5bNV7LQ2 | 6.1 | My Vibes, menu, exclusão | VibeRow, AutomationBadge, ActionMenu, Dialog | Posição do badge "Inativa" (PO) |
| UI-05 https://trello.com/c/kZ5EChcE | 6.1 | Criar e editar vibe, seletor de capa | TextField, Select, Toggle, CoverPicker | Lista de cenas para o Select |
| UI-06 https://trello.com/c/V7Ka3xjB | 6.2 | Sons da vibe, ajustes do som | SoundCard, Chip, ModalSheet | Não há tela de biblioteca de sons separada |
| UI-07 https://trello.com/c/FyFujDMz | 6.3 | Devices, conexões, descoberta | ListRow, AutomationBadge, DetailList, Checkbox | Descoberta Google Home depende da Fase 7 |
| UI-08 https://trello.com/c/YxYU18Mw | 6.3 | Cenas, formulário, ações da cena | SceneCard, ActionMenu, Dialog, StepRow | UI-07 (entrada "Cenas" em Devices) |
| UI-09 https://trello.com/c/uIPCxOeO | 6.4 | Agendamentos, formulário | ScheduleCard, DateTimeField, Checkbox | Recorrência (Fase 3); fase de FCM a confirmar |
| UI-10 https://trello.com/c/tG7o5r0O | 6.5 | Presets, detalhe, importar | PresetCard, StepRow, DetailList | O plano §11.2 não cita Presets |
| UI-11 https://trello.com/c/KeeF74QV | 6.6 | Settings | ListRow, Dialog | ADR-043 (onde guardar o tema) |

---

## 4. Índice de cards

- **Fase 2:** K13 https://trello.com/c/TcrPBSuo · K14 https://trello.com/c/MfzYKOM7 · K15 https://trello.com/c/wv8NvwlC · K16 https://trello.com/c/Oa9MB2eF · K17 https://trello.com/c/Yu5eEgoI
- **Design System:** DS-01 https://trello.com/c/0hmVKtPG · DS-02 https://trello.com/c/GOdwlgd4 · DS-03 https://trello.com/c/xpWWwJdV · DS-04 https://trello.com/c/km7jBjHq · DS-05 https://trello.com/c/wSmAVf7q · DS-06 https://trello.com/c/rU8jfwmF · DS-07 https://trello.com/c/LpS9P4Xy · DS-08 https://trello.com/c/DgyXIJva · DS-09 https://trello.com/c/iK02daOz · DS-10 https://trello.com/c/LTA1KmeD
- **Categorias de vibe (D7):** CAT-01 https://trello.com/c/bruAsQjh · CAT-02 https://trello.com/c/UeBvoRYR · CAT-03 https://trello.com/c/KoUndvAH · CAT-04 https://trello.com/c/fApLzFc1
- **Telas:** UI-01 a UI-11, na tabela da seção 3.

## 5. Pontos em aberto registrados

1. Posição do badge "Inativa" entre os badges do VibeRow (decisão do PO; UI-04).
2. Nome traduzido da categoria de vibe (a spec do CAT-01 pergunta; proposta v1: um nome, no idioma do admin).
3. Descoberta Google Home: entra no UI-07 ou na Fase 7?
4. Em que fase entra o download offline do player e o FCM (UI-03 e UI-09 dependem disso).
5. O plano §11.2 deve ser ajustado (ver a lista abaixo); este documento **não altera o plano**.

### Ajustes sugeridos ao plano (não aplicados)

- Mover a entrega do tema (`Colors.kt` etc.) da Fase 5 para paralelo à Fase 4.
- Deixar explícito que o esqueleto do `androidApp` abre a Fase 4, apesar de "não iniciar antes da Fase 3".
- Incluir Presets na ordem das áreas da Fase 6.
- Trocar a referência ao canvas de telas por um caminho estável, já que o canvas pode ser dividido.
