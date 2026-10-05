# DSG-01 — Tela: Bottom Sheet de Seleção de Provider

**Referência visual:** `TELAS_CONEXOES/bottom_sheet_ao_clicar_mais_adicionar_dispositivos.jpg`
**Contexto de navegação:** Aba "Dispositivos" → "+ Adicionar Dispositivo" → bottom sheet aparece

---

## 1. Estado atual observado (auditoria)

O bottom sheet é acionado pelo botão "+ Adicionar Dispositivo" (aba Dispositivos) e apresenta:

**Seção "Meus Cadastros" (conexões existentes):**
- Home Assistant — "Cadastrado em 07/08/2021" — badge "MEUS CADASTROS"
- Google Home — "Cadastrado em 17/08/2021" — badge "MEUS CADASTROS"
- Tuya — "Cadastrado em 09/08/2021" — badge "MEUS CADASTROS"
- **GEEVO** — "Cadastrado em 16/08/2021" — badge "MEUS CADASTROS"

**Seção "Novas Integrações Disponíveis":**
- Campo de busca com placeholder "Perache" (erro tipográfico)
- Chips de providers com ícones

**Seção "TODOS OS PROVEDORES":**
- Grid 2 colunas: Tuya, **Gevvo**, Google Home (parcial), Home Assistant (parcial)

**Violações identificadas:**

| Violação | Gravidade |
|---|---|
| Provider escrito "GEEVO" na seção "Meus Cadastros" — deve ser **Govee** | Crítica |
| Provider escrito "Gevvo" na seção "TODOS OS PROVEDORES" — deve ser **Govee** | Crítica |
| Entry point é "+ Adicionar Dispositivo" — a ação do bottom sheet é selecionar um provider (para criar/ampliar uma ProviderConnection), não criar um device manualmente | Crítica |
| Campo de busca com placeholder "Perache" (erro tipográfico — deve ser "Pesquisar") | Média |
| Seção "Novas Integrações Disponíveis" tem aparência de marketplace — deve ser "Catálogo de provedores" | Média |
| Badge "MEUS CADASTROS" na lista de providers ativos cria ambiguidade: o usuário pode querer criar uma segunda conexão ao mesmo provider? O design deve deixar claro o que acontece ao selecionar um provider já conectado | Média |

---

## 2. Especificação corrigida

### 2.1 Entry point e semântica

O bottom sheet representa a ação de **criar uma nova ProviderConnection** ou **selecionar um provider para sincronizar devices**. O entry point deve refletir isso.

**Mudança de CTA:**
- De: `+ Adicionar Dispositivo` (botão primário na aba Dispositivos)
- Para: `+ Adicionar conexão` (aba Dispositivos) ou manter o botão `+ Adicionar fornecedor` (aba Fornecedores) como único ponto de entrada

A abertura deste bottom sheet a partir de "+ Adicionar Dispositivo" é semanticamente errada. Devices não são adicionados — providers são conectados. Se o usuário está na aba Dispositivos e não tem devices, o estado vazio deve guiá-lo para conectar um provider (via link ou card de estado vazio), não um botão "+ Adicionar Dispositivo".

### 2.2 Estrutura do bottom sheet corrigida

```
┌─────────────────────────────────────────────────┐
│ Selecione um provedor                        [×] │
│                                                  │
│  CONEXÕES ATIVAS                                 │
│  ┌───────────────────────────────────────────┐   │
│  │ [ícone] Home Assistant   [Sincronizar]    │   │
│  │         Conectado em 07/08/2021           │   │
│  └───────────────────────────────────────────┘   │
│  ┌───────────────────────────────────────────┐   │
│  │ [ícone] Google Home      [Sincronizar]    │   │
│  │         Conectado em 17/08/2021           │   │
│  └───────────────────────────────────────────┘   │
│  ┌───────────────────────────────────────────┐   │
│  │ [ícone] Tuya             [Sincronizar]    │   │
│  └───────────────────────────────────────────┘   │
│  ┌───────────────────────────────────────────┐   │
│  │ [ícone] Govee            [Sincronizar]    │   │
│  └───────────────────────────────────────────┘   │
│                                                  │
│  NOVA CONEXÃO                                    │
│  ┌─ Pesquisar ──────────────────────────────┐   │
│  │ 🔍 Pesquisar provedores                  │   │
│  └──────────────────────────────────────────┘   │
│                                                  │
│  PROVEDORES DISPONÍVEIS                          │
│  ┌──────────────┐  ┌──────────────┐             │
│  │ [ícone] Tuya │  │ [ícone] GH   │             │
│  └──────────────┘  └──────────────┘             │
│  ┌──────────────┐  ┌──────────────┐             │
│  │ [ícone] HA   │  │[ícone] Govee │             │
│  └──────────────┘  └──────────────┘             │
└─────────────────────────────────────────────────┘
```

### 2.3 Seção "Conexões Ativas"

Providers que já têm uma ProviderConnection ativa para este usuário. A ação inline é **"Sincronizar"** (dispara re-discovery de devices). Clicar no card inteiro pode abrir o detalhe da ProviderConnection (status, devices, editar, testar).

**Não usar badge "MEUS CADASTROS"** — a separação em seção já indica que são conexões existentes.

Se o usuário quiser adicionar uma **segunda conexão** ao mesmo provider (ex.: dois servidores HA distintos), a ação deve estar visível e ser explícita (ex.: link "Adicionar outra conexão" no rodapé do card), não implícita.

### 2.4 Seção "Provedores Disponíveis" (catálogo)

- Título: "PROVEDORES DISPONÍVEIS" (não "Novas Integrações Disponíveis" — o termo "nova integração" tem conotação de marketplace)
- Fonte dos dados: `GET /provider-types` — lista schema-driven, não hardcoded
- Campo de busca: placeholder "Pesquisar provedores" (corrigindo o erro tipográfico "Perache")
- Filtros opcionais por tipo de conexão: busca por nome é suficiente para o catálogo atual
- Não transformar em marketplace/loja de integrações — é um catálogo técnico

**O nome correto dos providers no catálogo:**

| Provider | Nome canônico | Ortografia proibida |
|---|---|---|
| Home Assistant | Home Assistant | — |
| Google Home | Google Home | — |
| Tuya | Tuya | — |
| Govee | **Govee** | GEEVO, Gevvo, GEEVO, Geveo |

O nome de cada provider no catálogo vem de `ProviderDescriptor.label` — nunca de string hardcoded no cliente.

### 2.5 Estado de loading do catálogo

Enquanto `GET /provider-types` não retornar:
- Exibir skeletons nas posições dos cards
- Não exibir lista vazia sem indicação de carregamento

Se a requisição falhar:
- Exibir mensagem "Não foi possível carregar os provedores disponíveis." com botão "Tentar novamente"
- Não esconder a seção silenciosamente

---

## 3. O que não fazer

- Não usar "GEEVO", "Gevvo" ou qualquer variação — sempre **Govee**
- Não nomear o bottom sheet de "Adicionar Dispositivo" ou abri-lo a partir dessa ação
- Não criar uma seção "Novas Integrações Disponíveis" com linguagem de marketplace
- Não hardcodar a lista de providers — sempre `GET /provider-types`
- Não omitir o estado de carregamento do catálogo

---

## 4. Dependências abertas

| Dependência | Impacto |
|---|---|
| **PRV-01** | `GET /provider-types` retorna `connection_methods`. O catálogo está disponível — esta dependência está parcialmente resolvida para os 4 providers verificados. |
| **UI-PRV-01** | Implementação mobile do bottom sheet consumindo `GET /provider-types` de forma dinâmica aguarda UI-PRV-01. |
