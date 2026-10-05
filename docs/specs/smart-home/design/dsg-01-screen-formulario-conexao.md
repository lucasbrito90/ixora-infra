# DSG-01 — Tela: Formulário de Nova Conexão

**Referência visual:** `TELAS_CONEXOES/formulario_adicionar_provider.jpg`
**Contexto de navegação:** Gerenciar Conexões → "+ Adicionar fornecedor" → [seleção de provider] → formulário por método

---

## 1. Estado atual observado (auditoria)

A tela exibe um formulário fixo chamado "Nova Integração" com quatro campos:

- "Nome do Fornecedor" (ex: MQTT Broker)
- "Endereço (Host/URL)" (ex: http://192.168.x.x)
- "Porta" (ex: 8123)
- "Token de Acesso"

Com dois CTAs: "Testar Conexão" (link) e "Conectar" (botão primário).

**Violações identificadas:**

| Violação | Gravidade |
|---|---|
| Formulário genérico fixo aplicado a todos os providers — viola ADR-045 Decisão 2. Google Home receberia este mesmo formulário, mas `device_sdk` não tem credencial alguma a inserir. Tuya e Govee exigem API key, não URL+Port+Token. | Crítica |
| O campo "Nome do Fornecedor" editável pelo usuário implica que o provider é livre — deve ser selecionado do catálogo `GET /provider-types`, não digitado manualmente. | Crítica |
| Nenhuma etapa de seleção de provider visível — o formulário foi aberto sem que o usuário escolhesse o provider. | Alta |
| "Porta" é campo HA-específico (8123) exposto como campo universal — campos devem ser derivados do schema do método, não hardcoded. | Alta |

**O que está correto:**
- "Testar Conexão" está no contexto do formulário de ProviderConnection — correto semanticamente.
- "Conectar" como CTA principal — correto.

---

## 2. Especificação corrigida

O fluxo de adição de provider passa agora por **duas etapas**:

```
Etapa 1: Seleção de provider  →  Etapa 2: Formulário por connection_method
```

### 2.1 Etapa 1 — Seleção de provider

Pode ser implementada como bottom sheet ou tela dedicada (ver [dsg-01-screen-bottom-sheet-provider.md](dsg-01-screen-bottom-sheet-provider.md) para o design deste step). O resultado da seleção determina qual `connection_method` usar e quais campos exibir na Etapa 2.

### 2.2 Etapa 2 — Formulário orientado por `connection_method`

O formulário da Etapa 2 é **completamente definido pelo `connection_method`** do provider selecionado. Nenhum campo é hardcoded no cliente.

A lógica é: leia `connection_methods` de `GET /provider-types` para o provider selecionado. Cada método define os campos a renderizar. O cliente nunca faz `if (provider === "home_assistant")` para escolher campos.

---

#### Sub-fluxo A — `url_token` (Home Assistant primário)

```
Conectar Home Assistant
─────────────────────────────
Endereço (URL)
[ http://192.168.1.10:8123   ]

Token de acesso
[ ••••••••••••••••••••••••  ]

                [Testar Conexão]
────────────────────────────────
            [  Conectar  ]
```

Campos: URL base + token. "Porta" não é um campo independente — faz parte da URL (o usuário insere `http://host:porta` no campo único de URL). Não há campo "Nome do Fornecedor" editável — o nome é o label canônico do provider (`ProviderDescriptor.label`).

**Estados de "Testar Conexão":**
- Idle: link/botão secundário
- Em progresso: indicador de loading, CTA "Conectar" desabilitado
- Sucesso: badge verde "Conexão verificada" — habilita "Conectar"
- Falha `unreachable_host`: mensagem "Host inacessível. Verifique a URL e a rede."
- Falha `unreachable_credentials`: mensagem "Token inválido ou sem permissão."

---

#### Sub-fluxo B — `api_key` (Tuya, Govee)

```
Conectar Govee
─────────────────────────────
Chave de API (API Key)
[ ••••••••••••••••••••••••  ]

                [Testar Conexão]
────────────────────────────────
            [  Conectar  ]
```

Campos: apenas API key. Para Tuya (que também aceita `oauth2` para conta de usuário): exibir escolha de método antes dos campos ("Chave de API" ou "Conta Tuya"). Sem campo de URL — a chave acessa a API cloud do provider diretamente.

**Nota Govee:** a API key do Govee controla todos os devices da conta do usuário (sem granularidade por device). O design deve incluir um texto informativo breve: "Esta chave controla todos os seus dispositivos Govee vinculados a esta conta."

---

#### Sub-fluxo C — `oauth2` (HA Cloud, Tuya conta, Google Home)

Para `oauth2` de lado do servidor (HA Cloud, Tuya conta):

```
Conectar Home Assistant (HA Cloud)
─────────────────────────────────────────
Você será redirecionado para o Home Assistant
Cloud para autorizar o acesso.

            [ Autorizar com HA Cloud ]
```

Nenhum campo de credencial é inserido manualmente. O fluxo segue o padrão OAuth2 (redirect / WebView / deep link de retorno). Ao retornar com sucesso, a conexão é criada com status `connected`.

---

#### Sub-fluxo D — `device_sdk` (Google Home)

```
Conectar Google Home
──────────────────────────────────────────────
[ícone Google Home]

O Google Home usa o SDK nativo do dispositivo.
Você precisará autorizar o acesso à sua casa no
próximo passo.

Não são armazenadas credenciais no servidor.

            [ Continuar com Google Home ]
```

**Nenhum campo de credencial.** A tela é explicativa. O CTA "Continuar com Google Home" inicia o fluxo nativo do SDK no dispositivo. `encrypted_credentials` permanece nulo no servidor para conexões `device_sdk` — não há dado a inserir.

---

#### Sub-fluxo E — `local_discovery` (HA local, Tuya LAN, Govee LAN)

```
Conectar [Provider] na rede local
──────────────────────────────────────────────
O app irá descobrir dispositivos na sua rede
Wi-Fi local.

[indicador de varredura / loading]

Dispositivos encontrados:
• 192.168.1.10  (Home Assistant)

            [ Selecionar e conectar ]
```

Nenhum campo manual de URL para o caso de discovery automático. Se o discovery falhar, oferecer fallback para inserção manual de endereço. Credenciais locais (ex.: `localKey` do Tuya) são gerenciadas no storage seguro do dispositivo — nunca enviadas ao servidor (aguarda PRV-03).

---

### 2.3 Etapa de confirmação pós-conexão

Após "Conectar" com sucesso:
- Exibir tela de sucesso com nome do provider e número de devices encontrados
- CTA: "Ver dispositivos"
- Não redirecionar silenciosamente — confirmar o resultado

---

## 3. O que não fazer

- Não criar um formulário com campo "Nome do Fornecedor" editável — o nome vem de `ProviderDescriptor.label`.
- Não exibir campo "Porta" como campo independente.
- Não mostrar um formulário vazio para Google Home (`device_sdk`).
- Não hardcodar campos por provider — sempre derivar do schema.
- Não criar uma seção "MQTT Broker" ou qualquer provider não listado em `GET /provider-types`.

---

## 4. Dependências abertas

| Dependência | Impacto |
|---|---|
| **PRV-01** | `GET /provider-types` deve retornar `connection_methods` por provider. Parcialmente implementado: `connection_methods` existe, mas `execution_capabilities` por método ainda é flat. O formulário usa `connection_methods` — OK para Etapa 2. |
| **PRV-03** | Fluxo `local_discovery` que requer `localKey` no device aguarda PRV-03 (secure storage no device). O sub-fluxo E acima descreve o design; a implementação é bloqueada por PRV-03. |
| **UI-PRV-01** | A implementação mobile do formulário orientado por método aguarda UI-PRV-01. |
