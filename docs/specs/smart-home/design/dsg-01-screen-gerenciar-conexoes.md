# DSG-01 — Tela: Gerenciar Conexões (aba Fornecedores)

**Referência visual:** `TELAS_CONEXOES/gerenciar_conexoes.jpg`
**Contexto de navegação:** `Devices` tab → sub-aba `Fornecedores`

---

## 1. Estado atual observado (auditoria)

A tela exibe uma lista de ProviderConnections com as seguintes características:

- Título: "Gerenciar Conexões"
- Duas sub-abas: "Fornecedores" (ativa) e "Dispositivos"
- Botão primário: "+ Adicionar fornecedor" — semanticamente correto
- Card de conexão: nome do provider ("Home Assistant"), status ("Conectado"), texto truncado "Ao clicar nos ..."
- Menu de contexto (⋮): "Testar conexão", "Editar", "Excluir"

**Violações identificadas:**

| Violação | Gravidade |
|---|---|
| Status "Conectado" usa o vocabulário antigo de 3 estados — não distingue causa de falha nem expõe `last_tested_at` | Média |
| O texto truncado "Ao clicar nos ..." precisa ser revisado — se exibe qualquer identificador interno de provider, é violação da ADR-045 Decisão 7 | Verificar |
| Segundo card (ícone de casa) sem label visível — estado de carregamento não especificado | Baixa |

**O que está correto (não alterar):**
- "Testar conexão" está no menu de contexto da ProviderConnection — semanticamente correto neste nível.
- Ação "+ Adicionar fornecedor" está no nível certo (cria uma nova ProviderConnection).
- Separação em abas Fornecedores / Dispositivos mantém os dois conceitos separados.

---

## 2. Especificação corrigida

### 2.1 Estrutura da tela

```
Gerenciar Conexões
  [Cenas]                          [+ Adicionar fornecedor]

  [Fornecedores]    [Dispositivos]

  ┌──────────────────────────────────────────┐
  │  [ícone]  Home Assistant                 │ ⋮
  │           <status-chip>  <last-tested>   │
  └──────────────────────────────────────────┘

  ┌──────────────────────────────────────────┐
  │  [ícone]  Google Home                    │ ⋮
  │           <status-chip>                  │
  └──────────────────────────────────────────┘
```

### 2.2 Status da conexão (ADR-045 Decisão 5)

O status de cada ProviderConnection deve ser representado por um dos 6 estados abaixo. Cada estado define o chip de status e a ação de recuperação exibida ao usuário:

| `connection.status` | Label do chip | Cor sugerida | Ação de recuperação |
|---|---|---|---|
| `pending` | "Aguardando teste" | Cinza neutro | Botão "Testar" inline ou via menu ⋮ |
| `connecting` | "Conectando…" | Azul / indicador de progresso | Nenhuma — aguardar |
| `connected` | "Conectado" + data/hora do último teste | Verde | Nenhuma |
| `unreachable_host` | "Host inacessível" | Vermelho | "Verifique a URL / rede" + "Testar novamente" |
| `unreachable_credentials` | "Credencial inválida" | Vermelho/laranja | "Atualizar credencial" |
| `revoked` | "Acesso revogado" | Vermelho | "Reautenticar" |

**`last_tested_at`:** Quando status = `connected`, exibir a data/hora do último teste em formato curto (ex.: "Testado 04/10 às 16:31"). Quando ausente, tratar como `pending`.

**Forward-compatibility:** Status não reconhecido pelo cliente exibe "Status desconhecido" e oferece apenas "Testar" como ação. Não exibir mensagem de erro genérica sem ação.

### 2.3 Menu de contexto da ProviderConnection (⋮)

```
• Testar conexão     ← permanece aqui (nível de ProviderConnection) ✓
• Sincronizar dispositivos   ← nova entrada; dispara sync/discovery
• Editar
• Excluir
```

"Testar conexão" verifica a saúde da ProviderConnection. "Sincronizar dispositivos" dispara a re-discovery dos devices vinculados. São ações distintas — não confundir.

### 2.4 Subtítulo do card de conexão

O subtítulo de cada card deve exibir apenas:
- Método de conexão (ex.: "url_token", ou label amigável: "Token de acesso")
- Número de devices vinculados (ex.: "8 dispositivos")

**Nunca exibir:** `base_url`, `access_token`, `entity_id`, `provider_device_id`, qualquer credencial ou identificador interno.

### 2.5 Estado do segundo card (loading/vazio)

Se uma conexão está sendo carregada ou tem status `connecting`, exibir skeleton/placeholder com o nome do provider mas sem dados de estado. Não exibir dados parciais.

---

## 3. Dependências abertas

| Dependência | Impacto |
|---|---|
| **PRV-02** | Os 6 estados de `connection.status` só podem ser lidos do backend após PRV-02 implementar o lifecycle. Até lá, o design usa o vocabulário correto mas a UI renderiza apenas `connected` / `pending` (estados disponíveis). |
| **UI-PRV-01** | A implementação mobile desta tela consumindo o novo `connection.status` aguarda UI-PRV-01. |
