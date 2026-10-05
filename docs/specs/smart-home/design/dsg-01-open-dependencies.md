# DSG-01 — Dependências Abertas

**Status:** Registrado em 2026-10-04, como parte do DSG-01.
**Propósito:** Consolidar as decisões arquiteturais e implementações ainda abertas que afetam o design das telas de Smart Home. Onde uma decisão ainda não está fechada, o design representa o estado de forma neutra em vez de inventar um comportamento.

---

## DEV-01 — Device State Pipeline

**Impacto no design:** As telas de lista de dispositivos precisam exibir o estado de conectividade (`Device.connectivity`) e o estado de capabilities (`DeviceState.values`) em tempo real. Enquanto DEV-01 não estiver implementado, o design substitui esses dados por um placeholder neutro.

**Regra de design:**
- `Device.connectivity`: exibir chip `○ —` (cinza, sem ponto colorido) em vez de `● online` ou `● offline`
- Estado de capability (ex.: power `ligado/desligado`, temperatura `24.5 °C`): exibir `—` ou skeleton
- Nunca inventar valores de estado (ex.: hardcodar "24.5 °C" como se fosse dado real)

**Telas afetadas:**
- `dsg-01-screen-lista-dispositivos.md` §2.3, §2.7

**Resolução esperada:** Após DEV-01, substituir placeholder pelo dado real de `DeviceState.values` e `Device.connectivity`.

---

## PRV-02 — Connection Status Lifecycle

**Impacto no design:** A ADR-045 Decisão 5 define 6 estados de `connection.status` (`pending`, `connecting`, `connected`, `unreachable_host`, `unreachable_credentials`, `revoked`). O design especifica o visual e a ação de recuperação para cada estado. Contudo, o backend só retornará esses estados após PRV-02 implementar o lifecycle e a migração dos valores existentes.

**Regra de design:**
- Antes de PRV-02: a tela de Fornecedores exibe apenas os estados disponíveis no backend atual (`connected`, `unreachable`, `unknown`). O mapeamento visual é: `connected → Conectado`, `unreachable → Host inacessível` (sem distinção de causa), `unknown → Aguardando teste`.
- Após PRV-02: usar os 6 estados com as ações de recuperação distintas (spec completa em `dsg-01-screen-gerenciar-conexoes.md` §2.2).

**Telas afetadas:**
- `dsg-01-screen-gerenciar-conexoes.md` §2.2

**Resolução esperada:** PRV-02 implementa o lifecycle; a UI lê os novos valores e exibe a ação de recuperação correta.

---

## CAT-01 — Capability Catalog (binary sensors e câmera)

**Impacto no design:**

*Binary sensors (`contact`, `moisture`):* Devices como "Sensor Porta" e "Vazamento Banheiro" são binary sensors. A ADR-037 §8.3 marca o tipo de constraint `binary` como não ratificado até CAT-01 definir a modelagem CSDM. Enquanto CAT-01 não for concluído:
- Binary sensors aparecem na lista apenas como device (com nome e tipo), sem nenhuma capability renderizada
- Nenhum chip de estado, toggle ou leitura de valor é exibido

*Câmera:* A ADR-045 Decisão 8 defer câmera explicitamente para CAT-01. Nenhuma tela de Smart Home exibe câmera, live preview ou estado "Idle" de câmera enquanto CAT-01 não definir e ratificar a modelagem.

**Telas afetadas:**
- `dsg-01-screen-lista-dispositivos.md` §2.5, §2.6

**Resolução esperada:** CAT-01 define a modelagem CSDM de binary sensors e/ou câmera. Após CAT-01 e implementação, o design é atualizado para renderizar essas capabilities.

---

## UI-PRV-01 — Mobile UI Method-Driven Connection Flow

**Impacto no design:** O formulário de nova conexão especificado em `dsg-01-screen-formulario-conexao.md` pressupõe que o cliente lê `connection_methods` de `GET /provider-types` e adapta dinamicamente os campos. Isso é o que UI-PRV-01 implementa. Enquanto UI-PRV-01 não estiver concluído, o formulário existente (fixo, estilo Home Assistant) permanece em produção em `front_vibes` — que está feature-frozen (ADR-042).

**Telas afetadas:**
- `dsg-01-screen-formulario-conexao.md` (fluxo completo)
- `dsg-01-screen-bottom-sheet-provider.md` §2.4

**Resolução esperada:** UI-PRV-01 implementa em `ixora-app` o formulário orientado por `connection_methods`. O design DSG-01 é a spec que UI-PRV-01 implementa.

---

## PRV-03 — On-Device Secure Storage (local_discovery)

**Impacto no design:** O sub-fluxo `local_discovery` descrito em `dsg-01-screen-formulario-conexao.md` (Sub-fluxo E) pressupõe armazenamento seguro no device para credenciais locais (ex.: `localKey` do Tuya). PRV-03 é a implementação desse storage seguro e está gated — só deve ser implementado quando houver um consumer real de `local_discovery`. Enquanto PRV-03 não existir, o Sub-fluxo E não deve ser implementado mesmo que o design esteja especificado.

**Telas afetadas:**
- `dsg-01-screen-formulario-conexao.md` §2.2 Sub-fluxo E

**Resolução esperada:** PRV-03 implementa o storage seguro no device. Após PRV-03 e um consumer real de `local_discovery`, o Sub-fluxo E pode ser implementado.

---

## Cards 166 / DEV-01 — Confirmação de escopo

**Nota:** O card DSG-01 referencia os cards 166 e 167 como cards relacionados ao DEV-01 (Device State Pipeline). Os detalhes de escopo desses cards não foram encontrados em `ixora-infra/docs/` durante a execução do DSG-01. Registrado aqui como item de verificação: confirmar se cards 166/167 mapeiam para DEV-01 e se há documentação em `ixora-infra/docs/` a ser referenciada. Se necessário, atualizar a referência de DEV-01 neste documento com o link correto.
