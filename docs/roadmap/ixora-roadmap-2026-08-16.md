# Ixora - Roadmap consolidado

**Data de consolidação:** 16 de agosto de 2026  
**Escopo:** evolução mais ampla do produto Ixora + roadmap detalhado de Observability Foundation  
**Objetivo:** registrar, em ordem cronológica, tasks e subtasks já documentadas, com uma descrição breve e o percentual de progresso sustentado pelas fontes disponíveis.

## 1. Critérios usados neste documento

Este documento é uma consolidação do planejamento já existente. Ele **não define uma nova prioridade, não recomenda uma arquitetura diferente e não preenche lacunas com decisões próprias**.

Para evitar conclusões precipitadas:

- quando uma fase possui uma lista explícita de subtasks, o percentual é calculado como `subtasks concluídas / subtasks listadas`;
- quando apenas o status da fase está explicitamente registrado, usa-se esse status sem inventar subtasks;
- quando o roadmap mudou de numeração ao longo do projeto, a versão mais recente é tratada como atual e a numeração antiga é registrada como histórica;
- quando existe conflito entre um cartão pai e suas subtasks, o progresso do cartão pai é marcado como **N/D** em vez de ser estimado;
- `N/D` significa **não determinado com segurança a partir das fontes disponíveis**.

### Fontes consolidadas

- roadmap e checklists de `ixora-infra/docs/specs/observability-foundation/mvp/tasks.md` e `plan.md`;
- especificações de Grafana, alerting, recording rules e SLO;
- runbook de SLO / Error Budget;
- documentos de infraestrutura e integração OTLP no DigitalOcean App Platform;
- relatórios de implementação do `back_vibes` para OpenTelemetry e OTLP logs;
- validações operacionais realizadas em staging durante esta sequência de trabalho;
- roadmap macro de produto anteriormente registrado para as releases v1.1.0 a v1.8.0.

---

# 2. Roadmap macro do produto Ixora

Esta seção preserva o planejamento de releases mais amplo que já havia sido estabelecido para o Ixora.

| Ordem | Release / iniciativa | Status documentado | Progresso | Descrição breve |
| --- | --- | --- | ---: | --- |
| 1 | **v1.1.0 - Push Notifications** | Concluída | **100%** | Fundação de notificações push do produto. |
| 2 | **v1.2.0 - Scheduler + Smart Home Automations** | Concluída | **100%** | Scheduler, execução agendada e automações Smart Home integradas. |
| 3 | **v1.3.0 - Smart Home Scenes** | Planejada | **N/D** | Evolução planejada para cenas Smart Home. Não há percentual confiável registrado nas fontes consolidadas. |
| 4 | **v1.4.0 - Multi-provider Smart Home** | Planejada | **N/D** | Expansão planejada do Smart Home para múltiplos providers. |
| 5 | **v1.5.0 - Analytics** | Planejada | **N/D** | Camada de analytics planejada para o produto. |
| 6 | **v1.6.0 - AI Recommendations** | Planejada | **N/D** | Recomendações baseadas em IA, registradas como etapa futura. |
| 7 | **v1.7.0 - Admin Panel** | Planejada | **N/D** | Painel administrativo previsto no roadmap. |
| 8 | **v1.8.0 - Marketplace** | Planejada | **N/D** | Marketplace cultural de produtos e serviços previsto no roadmap. |

## 2.1 v1.2.0 - Scheduler + Smart Home Automations

O planejamento detalhado recuperado para esta release seguia esta ordem:

1. **Phase 1 - ADRs & Spec** - arquitetura e especificação inicial. No registro histórico recuperado, esta subfase estava explicitamente concluída.
2. **Phase 2 - Schema / Domain Review** - revisão de modelo, domínio e persistência necessários ao Scheduler e Smart Home.
3. **Phase 2.5 - Security Review** - revisão de autorização, exposição de dados e riscos de segurança.
4. **Phase 3 - Dispatch Review** - revisão do fluxo de disparo das automações.
5. **Phase 4A - Validator** - validação das condições necessárias antes da execução.
6. **Phase 4B - Integration** - integração do validator com o fluxo real de execução.
7. **Phase 5A - API Enrichment** - enriquecimento das respostas e contratos da API.
8. **Phase 5B - Mobile UX** - suporte da experiência mobile ao fluxo.
9. **Phase 5C.1 - Badges** - indicadores visuais associados ao estado/funcionalidade.
10. **Phase 5C.2 - UX Polish** - refinamentos de experiência.
11. **Phase 6A - Notification Alignment** - alinhamento dos eventos e notificações.
12. **Phase 6B - Notification UX** - experiência de usuário para notificações.
13. **Phase 7 - Operational Readiness** - preparação operacional.
14. **Phase 8 - E2E QA** - validação ponta a ponta.
15. **Release** - fechamento da entrega.

**Percentual da release:** **100%**, pois a release `v1.2.0 Scheduler + Smart Home Automations` foi posteriormente registrada como concluída.  
**Percentual individual das subfases:** **N/D**, porque o material recuperado não preserva, para cada uma delas, um status individual final. Este documento não infere esses percentuais a partir do status da release.

---

# 3. Observability Foundation - visão cronológica

A Observability Foundation evoluiu de especificações e ADRs para infraestrutura, instrumentação de backend, dashboards, alerting, SLOs e validação operacional em staging.

## 3.1 Resumo das fases

| Fase | Nome | Status atual sustentado | Progresso |
| --- | --- | --- | ---: |
| 1 | ADRs & Observability Foundation Specification | Concluída | **9/9 - 100%** |
| 1.5 | Telemetry Naming Convention | Concluída | **1/1 - 100%** |
| 2 | Infrastructure Review | Concluída | **5/5 - 100%** |
| 2.5 | Security Review | Concluída | **5/5 - 100%** |
| 3 | OpenTelemetry Collector | Concluída | **9/9 - 100%** |
| 3.5 | Collector Validation & Hardening | Concluída no tracking atual | **100% no nível da fase** |
| 3.75 | Metrics Philosophy | Concluída | **1/1 - 100%** |
| 4 | Prometheus Deployment | Concluída | **3/3 - 100%** |
| 5 | Loki Deployment | Concluída | **3/3 - 100%** |
| 5.5 | Logs Philosophy | Concluída | **1/1 - 100%** |
| 6 | Tempo Deployment | Concluída | **3/3 - 100%** |
| 6.5 | Traces Philosophy | Concluída | **1/1 - 100%** |
| 7A | Backend SDK Foundation | Concluída | **9/9 - 100%** |
| 7B.1 | HTTP + Routing Instrumentation | Concluída | **10/10 - 100%** |
| 7B.2 | Queue + Console Instrumentation | Concluída | **5/5 - 100%** |
| 7B.3 | Generic Scheduler Instrumentation | Concluída | **7/7 - 100%** |
| 7B.4.1 | Domain Execution Review | Concluída | **14/14 - 100%** |
| 7B.4.2 | Smart Home Dispatch Boundary | Concluída | **13/13 - 100%** |
| 7B.4.3 | Smart Home Action Execution | Concluída | **13/13 - 100%** |
| 7B.4.4 | Smart Home Provider Boundary | Concluída | **12/12 - 100%** |
| 7B.4.5 | Business Failure Semantics | Concluída | **16/16 - 100%** |
| 7B.4.6 | Business Metrics | Concluída | **14/14 - 100%** |
| 7B.4.7 | Business Logging | Concluída | **8/8 - 100%** |
| 7B.4.8 | Business Telemetry Validation & Architecture Review | Concluída | **7/7 - 100%** |
| 7B.4.9 | Business Telemetry Foundation Baseline | Concluída | **5/5 - 100%** |
| 8.0 | Dashboard Requirements Review | Concluída | **4/4 - 100%** |
| 8.1 | Grafana Foundation & Provisioning | Concluída | **7/7 - 100%** |
| 8.2 | Infrastructure Dashboard D-07 | Concluída | **7/7 - 100%** |
| 8.3 | Application Infrastructure Dashboards | Concluída | **9/9 - 100%** |
| 8.4 | Smart Home Business Dashboard D-02 | Concluída | **7/7 - 100%** |
| 8.5 | Platform Overview & Cross-Signal Navigation | Concluída | **100%** |
| 8.6 | Operational Validation | Concluída | **100%** |
| 8.7 | D-03 Push Notifications Dashboard | Concluída | **8/8 - 100%** |
| 8.8 | Alerting Foundation | Concluída | **8/8 - 100%** |
| 8.8.5 | Observability Infrastructure Provisioning | Concluída | **8/8 - 100%** |
| 8.8.6 | Observability Infrastructure Hardening | Concluída | **9/9 - 100%** |
| 8.8.8 | Backend OTLP Log Export | Concluída e validada em staging | **100%** |
| 8.9 | SLO / Error Budget | Concluída nas fontes mais recentes | **100%** |
| 9 | Alerting Strategy | Nível 1 implementado e testado localmente; ativação em staging real pendente | **104/104 checks — Nível 1 completo** |
| 9.5 | Incident Response & Runbooks | Não iniciada no roadmap atual | **0%** |
| 10 | Performance Validation & Load Testing | Não iniciada | **0%** |
| 11 | Production Readiness Review | Não iniciada | **0%** |
| 11.5 | Final Documentation & Release Review | Não iniciada | **0%** |
| 12 | Observability Foundation Release | Não iniciada | **0%** |

> **Nota sobre a Phase 8 (cartão pai):** em um snapshot do tracking o cartão pai aparecia como "não iniciado", embora suas subtasks 8.1 em diante estivessem majoritariamente ou totalmente concluídas. Por isso este documento **não atribui um percentual artificial ao cartão pai**.

---

# 4. Observability Foundation - tasks e subtasks

## Phase 1 - ADRs & Observability Foundation Specification

**Status:** Concluída  
**Progresso:** **9/9 - 100%**

Subtasks:

1. ADR-028 - plataforma de observabilidade.
2. ADR-029 - modelo de dados de telemetria.
3. ADR-030 - segurança e privacidade da observabilidade.
4. ADR-031 - retenção, armazenamento e controle de custos.
5. Publicação de `spec.md`.
6. Publicação de `plan.md`.
7. Publicação de `tasks.md`.
8. Atualização do índice de documentação.
9. Confirmação de que a fase era apenas arquitetural, sem runtime code.

**Descrição:** definiu a base arquitetural para Collector, métricas, logs, traces, segurança e retenção.

## Phase 1.5 - Telemetry Naming Convention

**Status:** Concluída  
**Progresso:** **1/1 - 100%**

Subtask:

1. Publicação da convenção de nomes para serviços, métricas, spans, logs, eventos, labels, dashboards e alerts.

## Phase 2 - Infrastructure Review

**Status:** Concluída  
**Progresso:** **5/5 - 100%**

Subtasks:

1. Dimensionamento da VM DigitalOcean em relação aos budgets definidos.
2. Definição de firewall e ingresso OTLP.
3. Estratégia de DNS/TLS para o Collector.
4. Revisão do egress do App Platform para a VM de observabilidade.
5. Publicação da revisão de infraestrutura.

## Phase 2.5 - Security Review

**Status:** Concluída  
**Progresso:** **5/5 - 100%**

Subtasks:

1. Threat model, autenticação, TLS, PII e redaction.
2. Política de disponibilidade da telemetria: falhas de observabilidade não podem interromper a lógica de negócio.
3. Limites operacionais arquiteturais.
4. Checklist de hardening do Collector.
5. Atualização de specs e referências cruzadas.

## Phase 3 - OpenTelemetry Collector

**Status:** Concluída  
**Progresso:** **9/9 - 100%**

Subtasks:

1. `collector/config.yaml` com receivers, processors, extensions e pipelines.
2. Receivers OTLP gRPC/HTTP e endpoint destinado a mobile.
3. Processors de memória, batch, resource, redaction, cardinalidade e sampling.
4. Extensions de health, profiling, zpages e Bearer auth.
5. Docker Compose do Collector.
6. `.env.example` sem secrets reais.
7. README operacional do Collector.
8. Especificação de deployment.
9. Validação do Collector e health endpoint.

## Phase 3.5 - Collector Validation & Hardening

**Status atual no tracking:** Concluída  
**Progresso da fase:** **100% no nível da fase**

Checklist histórico conhecido:

1. Validação da sintaxe da configuração.
2. Startup, restart e health endpoint.
3. Matriz de autenticação 401/200.
4. Validação dos processors.
5. Testes de falha com payload malformado, oversized e configuração ausente.
6. Revisão de segurança.
7. Baseline de CPU, memória e latência.
8. Correção de defeitos encontrados.
9. Publicação do relatório de validação.
10. Firewall + TLS da VM apareciam como pendentes em um snapshot antigo.
11. Flood test na VM aparecia como pendente no mesmo snapshot.

**Estado consolidado:** o ambiente de staging posteriormente passou a operar com HTTPS via Caddy, firewall e Collector funcional. O material disponível não fornece uma confirmação independente do flood test; por isso o documento não o marca isoladamente como concluído, embora a **fase** esteja registrada como concluída no tracking atual.

## Phase 3.75 - Metrics Philosophy

**Status:** Concluída  
**Progresso:** **1/1 - 100%**

Subtask:

1. Publicação da filosofia de métricas, orientando quando e como criar métricas sem transformar o documento em um manual de Prometheus.

## Phase 4 - Prometheus Deployment

**Status:** Concluída  
**Progresso:** **3/3 - 100%**

Subtasks:

1. Deploy do Prometheus com retenção definida.
2. Integração Collector -> Prometheus.
3. Validação da métrica `up` e da política de retenção.

## Phase 5 - Loki Deployment

**Status:** Concluída  
**Progresso:** **3/3 - 100%**

Subtasks:

1. Deploy do Loki com retenção definida.
2. Integração Collector -> Loki.
3. Validação de ingestão e consulta de logs.

## Phase 5.5 - Logs Philosophy

**Status:** Concluída  
**Progresso:** **1/1 - 100%**

Subtask:

1. Publicação da filosofia de logs da plataforma.

## Phase 6 - Tempo Deployment

**Status:** Concluída  
**Progresso:** **3/3 - 100%**

Subtasks:

1. Deploy do Tempo com retenção definida.
2. Integração Collector -> Tempo e remoção do debug exporter restante.
3. Validação de ingestão e busca por `trace_id`.

## Phase 6.5 - Traces Philosophy

**Status:** Concluída  
**Progresso:** **1/1 - 100%**

Subtask:

1. Publicação da filosofia de traces da plataforma.

## Phase 7A - Backend SDK Foundation

**Status:** Concluída  
**Progresso:** **9/9 - 100%**

Subtasks:

1. Avaliação do ecossistema OpenTelemetry PHP.
2. Instalação dos pacotes oficiais de API/SDK/exporter e auto-instrumentation.
3. Criação da Telemetry Abstraction Layer em `back_vibes`.
4. Registro do `TelemetryServiceProvider` e implementação No-op quando desabilitado.
5. Habilitação de auto-instrumentation genérica.
6. Correlação `trace_id` / `span_id` em logs.
7. Configuração por environment variables e resource attributes.
8. Validação fail-open: indisponibilidade do Collector não quebra requests/jobs.
9. Testes de bootstrap, configuração, contratos, correlação e isolamento de falhas.

## Phase 7B.1 - HTTP + Routing Instrumentation

**Status:** Concluída  
**Progresso:** **10/10 - 100%**

Subtasks:

1. Revisão do hook HTTP do `opentelemetry-auto-laravel`.
2. Criação do módulo de telemetry HTTP.
3. Suporte a `activeSpan()` para enriquecer o span já existente.
4. Middleware global de telemetria HTTP.
5. Métricas de total e duração de requests.
6. Enriquecimento do span HTTP existente.
7. Contexto de erro HTTP em logs.
8. Documentação da limitação de canais `Log::build()`.
9. Testes de sucesso, erros, auth, validation, Collector unavailable, cardinalidade e duplicação.
10. Verificação de ausência de campos proibidos.

## Phase 7B.2 - Queue + Console Instrumentation

**Status:** Concluída  
**Progresso:** **5/5 - 100%**

Subtasks:

1. Revisão dos hooks de Queue/Console.
2. Telemetria de queue reutilizando o span existente e métricas `ixora.queue.job.*`.
3. Telemetria de comandos de console.
4. Métricas customizadas de Queue e Console.
5. Auditoria de campos proibidos.

## Phase 7B.3 - Generic Scheduler Instrumentation

**Status:** Concluída  
**Progresso:** **7/7 - 100%**

Subtasks consolidadas:

1. Revisão do lifecycle do Laravel Scheduler e da ausência de span automático para o boundary de scheduled events.
2. Criação de um boundary span específico para scheduler.
3. Normalização de nomes/tipos de eventos para cardinalidade limitada.
4. Métricas `ixora.scheduler.event.*`.
5. Separação entre execuções efetivas e eventos impedidos/ignorados.
6. Correlação e tratamento de falhas sem alterar a lógica de negócio.
7. Testes e validação do comportamento do scheduler instrumentado.

## Phase 7B.4.1 - Domain Execution Review

**Status:** Concluída  
**Progresso:** **14/14 - 100%**

Subtasks abrangeram:

1. Mapeamento das entradas reais de execução Smart Home.
2. Revisão da cadeia Controller/Console -> Dispatch Service -> Job -> Provider.
3. Identificação dos boundaries naturais para business telemetry.
4. Revisão de contexto de trace existente.
5. Análise de correlação entre trigger e jobs.
6. Revisão de persistência de execution outcomes.
7. Identificação de eventos/DTOs já existentes.
8. Revisão de retries e queue lifecycle.
9. Revisão de provider resolution e adapter execution.
10. Auditoria de atributos seguros e de cardinalidade.
11. Revisão de responsabilidades entre telemetria genérica e de negócio.
12. Revisão de riscos de duplicação com HTTP/Queue/Console/Scheduler/Push.
13. Revisão de cobertura de testes existente.
14. Publicação do `domain-execution-review.md` com gaps e decisões a serem usadas na fase seguinte.

**Importante:** foi uma fase de discovery; não alterou runtime code.

## Phase 7B.4.2 - Smart Home Dispatch Boundary

**Status:** Concluída  
**Progresso:** **13/13 - 100%**

Subtasks incluíram:

1. Revisão de auto-instrumentation e propagação de TraceContext pela queue.
2. Gate de implementação confirmando que não era necessário criar um correlation ID customizado.
3. Definição do boundary `smart_home.dispatch`.
4. Classificação de entry point `manual` / `scheduled`.
5. Atributos bounded de ações dispatched/skipped.
6. Implementação fail-open da telemetria.
7. Instrumentação do call site manual.
8. Instrumentação do call site scheduled.
9. Auditoria de duplicação e dados proibidos.
10. Testes unitários do span e atributos.
11. Testes de integração dos entry points reais.
12. Execução da suíte completa e lint.
13. Documentação e atualização do roadmap.

## Phase 7B.4.3 - Smart Home Action Execution

**Status:** Concluída  
**Progresso:** **13/13 - 100%**

Subtasks consolidadas:

1. Revisão de `SmartHomeActionJob::handle()` e retry behavior.
2. Descoberta do boundary real de execução da ação.
3. Definição do span `smart_home.action`.
4. Atributos bounded de provider/outcome/retry conforme ownership definido.
5. Tratamento de unsupported/unknown/failure sem vazar dados de negócio sensíveis.
6. Propagação natural do contexto recebido da queue.
7. Integração no job sem duplicar o queue span.
8. Fail-open da camada de telemetria.
9. Auditoria de cardinalidade e segurança.
10. Testes do telemetry wrapper.
11. Testes de integração do job.
12. Suíte completa e lint.
13. Documentação e roadmap.

## Phase 7B.4.4 - Smart Home Provider Boundary

**Status:** Concluída  
**Progresso:** **12/12 - 100%**

Subtasks abrangeram:

1. Revisão obrigatória do adapter/resolver/job e da auto-instrumentation Guzzle.
2. Descoberta de um provider boundary mais estreito que `executeAction()`.
3. Análise de duplicação com o span HTTP client automático.
4. Reavaliação de ownership dos atributos da Action Boundary.
5. Enum bounded de device domain.
6. `SmartHomeProviderTelemetry` e span `smart_home.provider`.
7. Integração no `HomeAssistantAdapter` no boundary real.
8. Tratamento fail-open e exception behavior.
9. Auditoria de segurança/cardinalidade.
10. Testes do provider telemetry.
11. Testes de integração/hierarquia dos spans.
12. Suíte completa e lint.

## Phase 7B.4.5 - Business Failure Semantics

**Status:** Concluída  
**Progresso:** **16/16 - 100%**

**Descrição das subtasks:** revisão e padronização da taxonomia de falhas de negócio, ownership de outcomes, política de Span Status, semântica de retries/unsupported/unknown-provider, alinhamento entre dispatch/action/provider boundaries, auditoria de duplicação, segurança, documentação e validação por testes. A fase foi predominantemente de semântica/arquitetura, com apenas correção estritamente necessária registrada no material de implementação.

## Phase 7B.4.6 - Business Metrics

**Status:** Concluída  
**Progresso:** **14/14 - 100%**

**Descrição das subtasks:** design review das métricas de negócio e implementação das métricas Smart Home já aprovadas, incluindo:

- `ixora.smart_home.dispatch.total`;
- `ixora.smart_home.action.total`;
- `ixora.smart_home.action.duration`;
- labels bounded de entry point, outcome e provider;
- rejeição/deferimento explícito de métricas que duplicariam sinais existentes;
- testes, cardinalidade, segurança e documentação.

## Phase 7B.4.7 - Business Logging

**Status:** Concluída  
**Progresso:** **8/8 - 100%**

**Descrição das subtasks:** revisão do logging de negócio existente, resolução da estratégia de logs para Smart Home, sanitização e correlação com trace/span, evitando criar logs redundantes apenas para satisfazer observabilidade.

## Phase 7B.4.8 - Business Telemetry Validation & Architecture Review

**Status:** Concluída  
**Progresso:** **7/7 - 100%**

Subtasks:

1. Revisão integrada dos boundaries Dispatch/Action/Provider.
2. Verificação de ausência de double spans/double metrics.
3. Revisão de correlação e lifecycle.
4. Auditoria de segurança/cardinalidade.
5. Validação dos testes e comportamento fail-open.
6. Registro de technical debt conhecido.
7. Relatório final de consistência arquitetural.

## Phase 7B.4.9 - Business Telemetry Foundation Baseline

**Status:** Concluída  
**Progresso:** **5/5 - 100%**

**Descrição:** transformou as decisões validadas no domínio Smart Home em um baseline de plataforma para futuras instrumentações de negócio, sem introduzir nova lógica de runtime.

## Phase 8.0 - Dashboard Requirements Review

**Status:** Concluída  
**Progresso:** **4/4 - 100%**

**Descrição:** definiu o conjunto de dashboards, requisitos de navegação/investigação e critérios que a implementação do Grafana deveria obedecer.

## Phase 8.1 - Grafana Foundation & Provisioning

**Status:** Concluída  
**Progresso:** **7/7 - 100%**

Subtasks:

1. Revisão arquitetural e requisitos.
2. Ativação do Grafana no Docker Compose.
3. Provisionamento das datasources Prometheus, Loki e Tempo com UIDs estáveis.
4. Provisionamento das pastas de dashboards.
5. Validação automatizada do provisioning.
6. Atualização da documentação/roadmap.
7. Git flow da feature.

**Resultado registrado:** Grafana provisionado como código e validação idempotente.

## Phase 8.2 - Infrastructure Dashboard D-07

**Status:** Concluída  
**Progresso:** **7/7 - 100%**

Subtasks:

1. Architecture review.
2. Correção de três blockers pré-existentes do stack.
3. Implementação do dashboard D-07 Infrastructure.
4. Extensão de `validate.sh`.
5. Documentação do dashboard.
6. Atualização de roadmap/docs.
7. Git flow da feature.

## Phase 8.3 - Application Infrastructure Dashboards

**Status:** Concluída  
**Progresso:** **9/9 - 100%**

**Descrição:** criou e validou os dashboards de aplicação para HTTP, Queue e Scheduler, padronizou convenções, labels, variáveis, links e workflows de investigação.

Principais dashboards:

- **D-04 Queue Workers**;
- **D-05 HTTP API**;
- **D-06 Scheduler**.

## Phase 8.4 - Smart Home Business Dashboard D-02

**Status:** Concluída  
**Progresso:** **7/7 - 100%**

Subtasks:

1. Revisão de ADRs, philosophy docs e business telemetry.
2. Verificação direta das métricas implementadas.
3. Implementação do D-02 Smart Home Business.
4. Extensão da validação automatizada.
5. Documentação do dashboard.
6. Atualização do roadmap.
7. Git flow.

## Phase 8.5 - Platform Overview & Cross-Signal Navigation

**Status:** Concluída  
**Progresso:** **100%**

**Descrição:** implementação do D-01 Platform Overview, integração das métricas já existentes e estabelecimento da navegação entre dashboards usando UIDs estáveis. O material registra o D-01 com 32 panels e validação automatizada correspondente.

## Phase 8.6 - Operational Validation

**Status:** Concluída  
**Progresso:** **100%**

**Descrição:** integrou os dashboards em uma malha de navegação, validou links e workflows operacionais e ampliou o script de validação. O registro mais recente desta etapa informa **48/48 checks** e workflows para investigação de HTTP server error, scheduler failure, queue backlog e Smart Home failure.

## Phase 8.7 - D-03 Push Notifications Dashboard

**Status:** Concluída  
**Progresso:** **8/8 - 100%**

Subtasks:

1. Revisão obrigatória de conventions, requirements e push spec.
2. Architecture review da telemetria push disponível.
3. Implementação do D-03 com 23 panels.
4. Atualização da navegação dos seis dashboards existentes.
5. Ampliação de `validate.sh` para 57 checks.
6. Atualização das dashboard conventions.
7. Documentação D-03.
8. Atualização de tasks/plan/README.

**Observação documentada:** o dashboard foi construído sobre a camada de Queue telemetry porque a métrica push específica ainda não existia naquele momento.

## Phase 8.8 - Alerting Foundation

**Status:** Concluída  
**Progresso:** **8/8 - 100%**

Subtasks:

1. Revisão obrigatória dos documentos arquiteturais.
2. Architecture review da integração com o ecossistema existente.
3. `alerting-philosophy.md`.
4. `alerting-foundation.md`.
5. Scaffold de provisioning para contact points, notification policies, mute timings e templates.
6. `validate.sh` ampliado para 67 checks.
7. Correção de referência de fase no Grafana Foundation.
8. Atualização de roadmap/docs.

**Limite da fase:** ela criou a foundation de alerting; não criou runtime alert rules nessa etapa.

## Phase 8.8.5 - Observability Infrastructure Provisioning

**Status:** Concluída  
**Progresso:** **8/8 - 100%**

Subtasks:

1. Revisão do stack, OpenTofu e ADRs.
2. `observability.tf`: Droplet, firewall e volume opcional.
3. Cloud-init com Docker, Compose, Caddy e systemd, sem secrets.
4. Variables e outputs do OpenTofu.
5. Scripts `bootstrap-collector-env.sh` e `deploy-observability.sh`.
6. Documento de provisioning e runbook do host.
7. Atualização da documentação geral.
8. Validações estáticas de OpenTofu, Compose e shell scripts.

**Evolução posterior:** o host de staging foi efetivamente provisionado e a stack passou a operar no Droplet dedicado.

## Phase 8.8.6 - Observability Infrastructure Hardening

**Status:** Concluída  
**Progresso:** **9/9 - 100%**

Subtasks:

1. Revisão do material da 8.8.5.
2. Estratégia de deployments por release/ref imutável.
3. Arquitetura de backup - design, não implementação.
4. Estratégia de storage e Reserved IP.
5. Design de CI/CD futuro e integração App Platform OTEL.
6. Revisão de cloud-init e índice de hardening.
7. Reserved IP opcional em OpenTofu.
8. Suporte a `IXORA_GIT_REF` no deploy script + validações 79-90.
9. Atualização dos documentos relacionados.

**Importante:** CI/CD automático e backups estavam documentados como design futuro, não implementados nesta fase.

## Phase 8.8.8 - Backend OTLP Log Export

**Status:** Concluída e validada em staging  
**Progresso:** **100%**

Entregas verificadas:

1. Pacote Monolog para OpenTelemetry adicionado ao `back_vibes`.
2. Canal `otel` criado no logging do Laravel.
3. `LoggerProvider` reutilizado a partir de `OpenTelemetry\API\Globals`, sem criar provider paralelo.
4. Fail-safe handler para impedir que falhas OTLP afetem a aplicação.
5. `stderr` mantido como fallback.
6. Correlação `trace_id` / `span_id` preservada.
7. Flush do LoggerProvider integrado ao lifecycle.
8. `ixora:telemetry-validate` ampliado para validar o exporter de logs.
9. Runbook de OTLP logs criado.
10. Testes do pipeline de logs e auditoria de secrets executados.
11. Variáveis de runtime configuradas no App Platform.
12. Logs recebidos no Loki e visualizados no Grafana em staging.

**Validação operacional:** foram observados logs reais do `back_vibes` no Grafana/Loki com `trace_id` e `span_id`.

## Operational item - Staging Trace Sampling / Correlation

**Status:** Concluído operacionalmente  
**Progresso:** **100% da alteração validada**

Esta atividade não fazia parte da numeração original de fases, mas foi executada como hardening/validação de staging:

1. SDK do backend configurado com `OTEL_TRACES_SAMPLER=always_on`.
2. Sampling do Collector parametrizado por `OTEL_TRACE_SAMPLE_RATE_SUCCESS`.
3. Staging configurado com `OTEL_TRACE_SAMPLE_RATE_SUCCESS=100` durante a validação.
4. Collector recriado com a nova configuração.
5. Diversas requisições reais foram geradas.
6. Os `trace_id` encontrados nos logs do Loki foram localizados no Tempo.

**Resultado:** correlação log -> trace validada no ambiente de staging.

## Phase 8.9 - SLO / Error Budget

**Status:** Concluída nas fontes mais recentes  
**Progresso:** **100%**

O checklist de foundation possuía 8 itens, todos concluídos. Fontes posteriores mostram que a fase evoluiu além do scaffold e chegou a uma implementação ativa.

Entregas documentadas:

1. Revisão de metrics/logs/traces/alerting e ADRs.
2. Análise de PromQL duplicado e candidatos a SLI.
3. Recording Rules Philosophy.
4. SLO Philosophy.
5. Recording Rules & SLO Foundation spec.
6. Arquivos de recording rules.
7. Ampliação das validações automatizadas.
8. Atualização de roadmap/docs.
9. **71 recording rules** ativas na especificação mais recente.
10. **12 burn-rate alerts** multi-window com low-traffic guards.
11. Dashboard **D-08 SLO & Error Budget** (`ixora-slo`).
12. Runbook de SLO / Error Budget.
13. Testes matemáticos de SLO.

SLOs iniciais documentados para staging:

- HTTP availability: target **99,5%** em 30 dias;
- HTTP latency: **95%** das requests <= 500 ms em 30 dias;
- Queue success: **99%**;
- Scheduler success: **99%**;
- Smart Home actions: **95%**;
- Observability pipeline: **99%**.

Itens explicitamente deferred nessa documentação incluem SLO dedicado de Push, SLO por provider Smart Home, mobile/regional SLOs, migração de dashboards antigos para recording rules, Node Exporter/VM resource SLOs e remote deploy da fase quando ainda não autorizado.

---

# 5. Fases futuras do roadmap atual de Observability

## Phase 9 - Alerting Strategy

**Status:** Nível 1 (alerting-philosophy.md §15) implementado e validado localmente ponta a ponta; ativação em staging real pendente de um passo manual do operador  
**Progresso:** **104/104 checks de validate.sh — escopo do Nível 1 completo**

Evolução da foundation de alerting (Phase 8.8) para a estratégia operacional real: contact points reais (email via SMTP), árvore de roteamento por severidade, mute timing semanal, e as 7 primeiras regras de alerta de threshold (Collector Down, HTTP error rate/latência, Queue failure rate, Scheduler missed, Push failure, Smart Home failure), cada uma com runbook.

Cinco bugs reais foram encontrados e corrigidos durante a validação (não apenas lint de YAML, mas testes contra um Grafana + Collector + Prometheus reais rodando localmente): arquivos de contact points/políticas/mute-timings precisam viver em `provisioning/alerting/`, não nos diretórios-irmãos que a documentação da Phase 8.8 descrevia (o Grafana nunca os lê); um `ALERT_EMAIL_ADDRESS` vazio derruba o Grafana inteiro; uma função de template não suportada (`first`) quebra o `templates.yaml` inteiro; três regras referenciavam nomes de métrica/label que não existem na instrumentação real do `back_vibes`; e os labels/annotations `environment`/`dashboard`/`runbook` eram templados contra um conjunto de labels vazio, sempre renderizando em branco mesmo em alertas genuinamente disparados.

A validação final empurrou dados OTLP reais pelo pipeline real do Collector (via HTTP/JSON na porta 4318, sem precisar de ferramentas de protobuf) e confirmou a regra `ixora-alert-smart-home-failure` transicionando de `NoData` para `Pending` para `Alerting` exatamente no `for: 5m` configurado, com o e-mail real de disparo confirmado via API do Mailtrap.

Itens deferidos por desenho (não por lacuna): contact points Slack/PagerDuty (sem canal de equipe ainda), alerta de disco de VM (precisa de Node Exporter), alertas de Security, regras de inibição nativas do Alertmanager (não expressáveis no schema de provisioning do Grafana OSS), alertas de Business/Push Notifications (bloqueados pela Phase 7B.5), e escalonamento automatizado além de e-mail. Detalhe completo em `ixora-infra/docs/specs/observability-foundation/mvp/alerting-strategy.md`.

**Pendente antes de produção:** configurar SMTP real (não o sandbox Mailtrap usado na validação) e um `ALERT_EMAIL_ADDRESS` real no `collector/.env` do host de staging real — hoje `GF_SMTP_ENABLED=false` por padrão, o que mantém tudo inerte (sem crash, sem falha silenciosa) até esse passo manual do operador.

## Phase 9.5 - Incident Response & Runbooks

**Status:** Não iniciada  
**Progresso:** **0%**

Descrição: formalização de incident response e runbooks de operação para investigação e recuperação.

> **Numeração histórica:** uma versão antiga do roadmap usava "Phase 9.5" para Telemetry Decision Guide + Observability Playbook, que já foi concluída. O roadmap atual reutiliza `9.5` para **Incident Response & Runbooks**. Este documento preserva o nome atual e registra o conflito em vez de misturar as duas iniciativas.

## Phase 10 - Performance Validation & Load Testing

**Status:** Não iniciada  
**Progresso:** **0%**

Descrição: etapa futura de validação de performance e testes de carga.

## Phase 11 - Production Readiness Review

**Status:** Não iniciada  
**Progresso:** **0%**

Descrição: revisão formal da prontidão para produção.

## Phase 11.5 - Final Documentation & Release Review

**Status:** Não iniciada  
**Progresso:** **0%**

Descrição: revisão final da documentação e da entrega antes do fechamento da foundation.

## Phase 12 - Observability Foundation Release

**Status:** Não iniciada  
**Progresso:** **0%**

Descrição: fechamento/release da Observability Foundation após as validações anteriores.

---

# 6. Itens observability de roadmap antigo que continuam registrados separadamente

Alguns documentos mais antigos possuem uma numeração anterior à reorganização das Phases 8.x/9.x. Estes itens são mantidos aqui sem tentar encaixá-los artificialmente no roadmap atual.

| Item histórico | Status no documento antigo | Progresso documentado | Observação |
| --- | --- | ---: | --- |
| Phase 7B.5 - Push Notifications instrumentation | Pending | **0/3 - 0%** | Spans/metrics específicos de Push e auditoria de dados proibidos. O dashboard D-03 foi implementado usando métricas da Queue, não esta instrumentação específica. |
| Phase 7B.6 - External Providers instrumentation | Pending | **0/3 - 0%** | Spans/métricas para provider calls não cobertas pela auto-instrumentation genérica. |
| Old Phase 8 - Frontend SDK (`front_vibes`) | Pending | **0/5 - 0%** | OTel no Capacitor/mobile, erros/navigation, sampling, staging export, privacy. A numeração `8` foi depois reutilizada pelo bloco de Grafana no tracking atual. |
| Old Phase 9.5 - Telemetry Decision Guide + Observability Playbook | Done | **2/2 - 100%** | Documentação já concluída; não confundir com o atual 9.5 Incident Response & Runbooks. |
| Old QA/Appium observability items | Pending no snapshot antigo | **0%** | O roadmap atual reorganizou essas etapas como performance/readiness/release. |

---

# 7. Estado operacional de staging já confirmado

Os pontos abaixo foram validados durante o trabalho recente e ajudam a separar "planejado" de "já funcionando":

- host dedicado de observabilidade no DigitalOcean está operacional;
- Caddy fornece HTTPS para Grafana e OTLP;
- OpenTelemetry Collector recebe telemetria autenticada;
- Prometheus recebe métricas;
- Loki recebe logs;
- Tempo recebe traces;
- Grafana consulta Prometheus, Loki e Tempo;
- `back_vibes` exporta traces e metrics via OTLP;
- `back_vibes` exporta logs via OTLP;
- logs reais aparecem no Grafana/Loki;
- `trace_id` dos logs foi usado com sucesso para localizar os traces correspondentes no Tempo;
- sampling de staging foi parametrizado e validado em 100% durante os testes descritos.

Este bloco registra apenas fatos operacionais já observados; não altera o roadmap nem define o que deve vir em seguida.

---

# 8. Leitura dos percentuais

Os percentuais deste documento devem ser interpretados da seguinte forma:

- **100%:** fase ou checklist explicitamente concluído nas fontes atuais;
- **0%:** fase explicitamente marcada como não iniciada/pending no roadmap atual;
- **N/D:** não há informação suficiente para calcular o percentual sem inferência;
- percentuais de fases antigas e fases atuais não são somados em um único "percentual geral do Ixora", porque o roadmap contém trilhas paralelas e houve renumeração ao longo do projeto.

Por essa razão, **não é apresentado um percentual global artificial do projeto Ixora**.
