# Regras de Negócio: Casas Ativas por Phase

**Data:** 2025-10-23
**Versão:** 2.0
**Status:** ✅ Validado, Implementado e Compatível com Looker Studio

---

## 📋 Sumário

Este documento detalha todas as regras de negócio aplicadas nas queries de análise de casas ativas por phase.

---

## 🏗️ Regras Principais

### Regra 1: Definição de "Casa Ativa"

**Descrição:** Uma casa é considerada **ativa** quando atende TODOS os critérios abaixo:

#### Critério 1.1: Atividade Recente
- **Regra:** Casa deve ter pelo menos 1 registro nos últimos 60 dias
- **Campo:** `dailylogs.datecreated`
- **Lógica SQL:** `datecreated >= NOW() - INTERVAL '60 days'`
- **Justificativa:** Casas sem atividade recente provavelmente estão paradas ou canceladas

**Exemplos:**
```
✅ Casa com registro em 2025-10-20 → ATIVA (dentro de 60 dias)
❌ Casa com último registro em 2025-07-15 → INATIVA (> 60 dias atrás)
```

#### Critério 1.2: Não Finalizada
- **Regra:** Casa NÃO pode ter o processo de finalização registrado
- **Processo de Finalização:** `'phase 3 fcc'`
- **Campo:** `dailylogs.process`
- **Lógica SQL:** `job_id NOT IN (SELECT job_id WHERE process = 'phase 3 fcc')`
- **Justificativa:** "phase 3 fcc" indica conclusão (FCC = Final Completion Certificate)

**Exemplos:**
```
✅ Casa sem registro de 'phase 3 fcc' → ATIVA
❌ Casa com registro de 'phase 3 fcc' em qualquer data → FINALIZADA
```

**Nota Importante:**
- Mesmo que a casa tenha atividade recente APÓS 'phase 3 fcc', ela é considerada finalizada
- Registros após finalização são geralmente administrativos

#### Critério 1.3: Job ID Válido
- **Regra:** Casa deve ter `job_id` não nulo
- **Campo:** `dailylogs.job_id`
- **Lógica SQL:** `job_id IS NOT NULL`
- **Justificativa:** Validação de integridade - registros sem job_id são inválidos

---

### Regra 2: Determinação da Phase Atual

**Descrição:** A phase atual de uma casa é determinada pela **phase MAIS ALTA numericamente** que aparece em seus registros.

#### Lógica de Determinação

**Hierarquia de Phases:**
```
Phase 0 (menor)
  ↓
Phase 1
  ↓
Phase 2
  ↓
Phase 3
  ↓
Phase 4 (maior)
```

**Regra:**
- Se uma casa tem registros em múltiplas phases, considera-se a mais alta
- Assume-se que casas avançam sequencialmente nas phases
- Não é possível "retroceder" de phase (regressão não é considerada)

**Implementação SQL:**
```sql
MAX(
  CASE
    WHEN phase = 'phase 0' THEN 0
    WHEN phase = 'phase 1' THEN 1
    WHEN phase = 'phase 2' THEN 2
    WHEN phase = 'phase 3' THEN 3
    WHEN phase = 'phase 4' THEN 4
    ELSE -1
  END
) as current_phase_number
```

#### Exemplos de Determinação

**Exemplo 1: Casa com múltiplas phases**
```
Job 557 tem registros:
- 2025-01-10: process "foundation", phase "phase 1"
- 2025-02-15: process "plumbing rough", phase "phase 2"
- 2025-03-20: process "drywall", phase "phase 3"
- 2025-04-01: process "kanban", phase NULL

→ Phase Atual: Phase 3 (maior entre 1, 2, 3)
```

**Exemplo 2: Casa com processo administrativo recente**
```
Job 312 tem registros:
- 2025-09-01: process "plumbing trim", phase "phase 3"
- 2025-10-20: process "kanban", phase NULL
- 2025-10-21: process "artificial", phase "phase 0"

→ Phase Atual: Phase 3 (ignora NULL e phase 0 de proc. administrativo)
```

**Exemplo 3: Casa apenas em phase inicial**
```
Job 660 tem registros:
- 2025-10-06: process "permit submitted", phase "phase 0"

→ Phase Atual: Phase 0
```

---

### Regra 3: Tratamento de Valores Especiais

#### Regra 3.1: Phase NULL
- **Descrição:** Registros com `phase IS NULL` são **ignorados** na determinação da phase atual
- **Motivo:** Processos administrativos (kanban, artificial) não têm phase definida
- **Lógica SQL:** `WHERE d.phase IS NOT NULL`

**Exemplo:**
```
Job com:
- process "inspection", phase "phase 2" → CONSIDERA
- process "kanban", phase NULL → IGNORA
→ Phase Atual: Phase 2
```

#### Regra 3.2: Processos Administrativos
- **Lista de processos administrativos conhecidos:**
  - `'kanban'`
  - `'artificial'`
  - Qualquer processo com phase NULL

- **Tratamento:** Não afetam determinação de phase atual
- **Justificativa:** São processos de gestão/controle, não indicam progresso na construção

#### Regra 3.3: Phase Inválida
- **Descrição:** Se phase não é uma das esperadas ('phase 0' a 'phase 4'), é mapeada para -1
- **Lógica SQL:** `ELSE -1` no CASE
- **Filtro:** `WHERE current_phase_number >= 0` (exclui -1)
- **Motivo:** Dados inconsistentes ou corrompidos

---

## 📊 Regras de Agregação e Apresentação

### Regra 4: Agrupamento por Phase

**Descrição:** Casas são agrupadas pela phase atual determinada

**Lógica:**
```sql
GROUP BY current_phase_number
```

**Saída Esperada:**
```
Phase 0: X casas
Phase 1: Y casas
Phase 2: Z casas
Phase 3: W casas
Phase 4: K casas
```

---

### Regra 5: Cálculo de Percentuais

**Fórmula:**
```
Percentual = (Casas na Phase / Total de Casas Ativas) × 100
```

**Precisão:** 1 casa decimal (ex: 23.1%)

**Validação:** Soma de todos os percentuais deve ser 100.0%

**Implementação SQL:**
```sql
ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)
```

**Uso de Window Function:**
- `SUM(COUNT(*)) OVER ()` calcula total sem precisar de subquery
- Mais eficiente que calcular total separadamente

---

### Regra 6: Ordenação de Resultados

#### Para Resumo (Query 1)
- **Ordenação:** Por phase numérica (0 → 4)
- **SQL:** `ORDER BY current_phase_number`

#### Para Lista Detalhada (Query 2)
- **Ordenação Primária:** Phase numérica
- **Ordenação Secundária:** Job ID
- **SQL:** `ORDER BY current_phase_number, job_id`
- **Justificativa:** Facilita visualização e busca manual

---

## 🔍 Regras de Validação de Dados

### Regra 7: Unicidade de Jobs

**Descrição:** Cada job deve aparecer apenas UMA vez no resultado final

**Garantia:** Uso de `DISTINCT` e `GROUP BY job_id` nas CTEs

**Validação:**
```sql
-- Esta query deve retornar 0
SELECT job_id, COUNT(*)
FROM (SELECT ... FROM job_max_phase ...)
GROUP BY job_id
HAVING COUNT(*) > 1;
```

---

### Regra 8: Consistência de Contagens

**Regra:** O total de casas na agregação deve ser igual ao total de casas ativas distintas

**Fórmula:**
```
SUM(casas por phase) = COUNT(DISTINCT job_id ativos)
```

**Validação Implementada:**
- Query 1 soma: 60 + 26 + 44 + 67 + 63 = 260 casas
- Query 3 total: 260 casas
- ✅ Consistente

---

## 🎯 Casos de Uso Específicos

### Caso de Uso 1: Casa Finalizada Recentemente

**Cenário:**
```
Job 415 tem:
- 2025-10-20: process "final walkthrough", phase "phase 3"
- 2025-10-22: process "phase 3 fcc", phase "phase 3"
```

**Resultado:** ❌ EXCLUÍDA (tem 'phase 3 fcc')

**Justificativa:** Finalização é permanente, independente de timestamp

---

### Caso de Uso 2: Casa Antiga com Atividade Recente

**Cenário:**
```
Job 557 tem:
- 2023-05-10: process "foundation", phase "phase 1"
- 2024-02-20: process "plumbing", phase "phase 2"
- 2025-10-22: process "inspection", phase "phase 3"
```

**Resultado:** ✅ INCLUÍDA, Phase Atual = Phase 3

**Justificativa:** Tem atividade recente (2025-10-22 está dentro de 60 dias)

---

### Caso de Uso 3: Casa Parada Há Muito Tempo

**Cenário:**
```
Job 123 tem:
- 2025-07-01: process "drywall", phase "phase 3"
- (nenhum registro depois)
```

**Data Atual:** 2025-10-23 (114 dias atrás)

**Resultado:** ❌ EXCLUÍDA (sem atividade nos últimos 60 dias)

---

### Caso de Uso 4: Casa com Phase Gaps

**Cenário:**
```
Job 689 tem:
- 2025-10-01: process "permit", phase "phase 0"
- 2025-10-20: process "drywall", phase "phase 3" (pulou 1 e 2)
```

**Resultado:** ✅ INCLUÍDA, Phase Atual = Phase 3

**Justificativa:** Não exigimos progressão sequencial - apenas pegamos a phase mais alta

**Nota:** Isto pode indicar:
- Dados faltantes (registros não criados)
- Fast-track (processo acelerado)
- Importação de dados legados

---

## 📏 Regras de Formatação de Saída

### Regra 9: Formato de Phase na Apresentação

**Formato Interno:** Número inteiro (0, 1, 2, 3, 4)

**Formato Apresentado:** String com capitalização ('Phase 0', 'Phase 1', etc.)

**Conversão:**
```sql
CASE
  WHEN current_phase_number = 0 THEN 'Phase 0'
  WHEN current_phase_number = 1 THEN 'Phase 1'
  -- ...
END
```

**Justificativa:** Legibilidade para usuários finais

---

### Regra 10: Formato de Jobsite

**Formato:** Exatamente como está em `dailylogs.jobsite`

**Não aplicar:**
- ❌ Normalização (uppercase/lowercase)
- ❌ Trimming (remoção de espaços)
- ❌ Formatação

**Motivo:** Jobsite é usado para lookup em outros sistemas

**Exemplo:**
```
"c1-0557-m22 - (8009-1177-01)" → mantido exatamente assim
```

---

### Regra 11: Formato de Data (Última Atividade)

**Formato de Entrada:** `TIMESTAMP WITHOUT TIME ZONE`

**Formato de Saída:** `DATE` (apenas data, sem hora)

**Conversão:** `last_activity::date`

**Exemplo:**
```
2025-10-22 14:35:12 → 2025-10-22
```

**Justificativa:** Hora não é relevante para análise de atividade

---

## 🚨 Exceções e Edge Cases

### Exceção 1: Job Sem Phase Definida

**Cenário:** Job tem apenas registros com phase NULL

**Tratamento:** ❌ EXCLUÍDO (não aparece nos resultados)

**Lógica:** `WHERE d.phase IS NOT NULL` + `WHERE current_phase_number >= 0`

**Motivo:** Impossível determinar phase atual

---

### Exceção 2: Job ID Duplicado em Jobsite Diferente

**Cenário:** Mesmo job_id com jobsites diferentes (inconsistência de dados)

**Tratamento:** Usa `DISTINCT ON job_id` - pega primeiro jobsite encontrado

**Nota:** Isto é um problema de qualidade de dados que deveria ser corrigido

---

### Exceção 3: Process = 'phase 3 fcc' com Phase ≠ 'phase 3'

**Cenário:** Inconsistência - processo de finalização em phase errada

**Tratamento:** Casa é considerada FINALIZADA independente da phase

**Lógica:** Filtro usa apenas `process = 'phase 3 fcc'`, ignora campo phase

**Justificativa:** Process é mais confiável que phase para finalização

---

## 🎨 Regras de Compatibilidade com Looker Studio

### Regra 14: Nomenclatura de Aliases (snake_case)

**Descrição:** Todos os aliases de colunas devem usar **snake_case** sem espaços

**Formato Obrigatório:**
- ✅ `phase_atual` (correto)
- ✅ `ultima_atividade` (correto)
- ✅ `ultimo_processo` (correto)
- ❌ `"Phase Atual"` (incorreto - causa erro no Looker)
- ❌ `"Última Atividade"` (incorreto - caracteres especiais)

**Justificativa:**
- Google Looker Studio não aceita espaços em nomes de campos
- **Caracteres Unicode** (ex: ú, á, ã) não são processados corretamente
- **Caracteres especiais** (ampersands, colons, etc.) causam erro de validação
- Validação retorna erro: "invalid characters in field names"

**Documentação Oficial:**
- [Looker Studio - Invalid field name error](https://support.google.com/looker-studio/answer/12150924)

**Lista Completa de Aliases Padronizados:**
```
phase_atual          - Phase atual da casa
total_casas          - Contagem de casas
percentual           - Percentual com símbolo %
job_id               - ID da casa
jobsite              - Nome/identificação da casa
ultima_atividade     - Data da última movimentação
ultimo_processo      - Nome do último processo executado
ultimo_status        - Status do último processo
data_registro        - Data de criação do registro
processo             - Nome do processo
usuario              - Nome do usuário que criou o registro
subcontratada        - Nome da subcontratada
data_servico         - Data de serviço agendado/realizado
notas                - Observações do registro
```

---

### Regra 15: Formato de Percentual

**Descrição:** Percentual deve usar CONCAT() ao invés de operador ||

**Implementação Correta:**
```sql
CONCAT(ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)::text, '%') as percentual
```

**Implementação Incorreta (v1.0):**
```sql
ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) || '%' as percentual
```

**Justificativa:** CONCAT() tem melhor compatibilidade com Looker Studio

---

### Regra 16: Tratamento de Data Serviço

**Descrição:** Campo `servicedate` pode conter strings vazias que causam erro de conversão

**Implementação:**
```sql
CASE
  WHEN servicedate IS NULL OR servicedate = '' THEN NULL
  ELSE servicedate::date
END as data_servico
```

**Valores Tratados:**
- `NULL` → `NULL`
- `''` (string vazia) → `NULL`
- `'2025-10-22'` → `2025-10-22` (date)

**Justificativa:** Prevenir erro "invalid input syntax for type date: ''"

---

## 📊 Regras Específicas por Query

### Regra 17: Query 2 - Último Evento

**Descrição:** A Query 2 (lista detalhada) deve mostrar processo e status da última atividade

**Implementação:**
```sql
job_last_event AS (
  SELECT DISTINCT ON (d.job_id)
    d.job_id,
    d.datecreated as ultima_atividade,
    d.process as ultimo_processo,
    d.status as ultimo_status
  FROM dailylogs d
  WHERE d.job_id IN (SELECT job_id FROM active_jobs)
  ORDER BY d.job_id, d.datecreated DESC
)
```

**Regras:**
1. Usa `DISTINCT ON` para pegar último registro de cada job
2. Ordenação: `datecreated DESC` (mais recente primeiro)
3. Colunas retornadas: ultima_atividade, ultimo_processo, ultimo_status

**Uso:** Permite identificar casas paradas em processos problemáticos

**Exemplo:**
```
Job 557 | inspection | approved | 2025-10-22
Job 660 | permit submitted | pending | 2025-10-06
```

---

### Regra 18: Query 5 - Lista Individual (Não Agregada)

**Descrição:** Query 5 deve retornar UMA linha por casa (não agregar)

**Formato de Saída:**
- **Correto (v2.0):** 260 linhas (uma por casa)
- **Incorreto (v1.0):** 5 linhas agregadas com STRING_AGG

**Estrutura:**
```sql
SELECT
  phase_atual,
  job_id,
  jobsite,
  ultima_atividade,
  ultimo_processo,
  ultimo_status
FROM job_max_phase jmp
JOIN active_jobs aj ON jmp.job_id = aj.job_id
JOIN job_last_event jle ON aj.job_id = jle.job_id
WHERE jmp.current_phase_number >= 0
ORDER BY jmp.current_phase_number, aj.job_id
```

**Ordenação:** Por phase numérica primeiro, depois job_id (facilita interação com Query 6)

**Justificativa:**
- Permite clique em linha individual no Looker Studio
- job_id vira filtro cross-table automaticamente
- Query 6 responde ao filtro

---

### Regra 19: Query 6 - Histórico Interativo

**Descrição:** Query 6 mostra histórico completo de uma casa específica

**Parâmetro de Entrada:**
- **No SQL direto:** `WHERE job_id = 557` (valor fixo para teste)
- **No Looker Studio:** `WHERE job_id = @DS_FILTER_job_id` (filtro dinâmico)

**Colunas Obrigatórias:**
1. `job_id` - ID da casa
2. `jobsite` - Nome da casa
3. `data_registro` - Data do evento (apenas date, sem hora)
4. `processo` - Nome do processo
5. `status` - Status do processo
6. `phase` - Phase do processo
7. `usuario` - Quem criou o registro
8. `subcontratada` - Empresa responsável
9. `data_servico` - Data de serviço (com tratamento de vazios)
10. `notas` - Observações

**Colunas Excluídas (conforme requisito):**
- ❌ `startdate` - Não incluir
- ❌ `enddate` - Não incluir

**Ordenação:** `ORDER BY datecreated DESC` (eventos mais recentes primeiro)

**Validação:**
- Job 557: Deve retornar 254 eventos
- Job 660: Deve retornar 8 eventos
- Job 312: Deve retornar 723 eventos

**Interação com Query 5:**
- Quando usuário clica em linha da Query 5
- job_id daquela linha vira filtro
- Query 6 atualiza automaticamente mostrando histórico

---

## 🔄 Regras de Atualização e Manutenção

### Regra 12: Período de Atividade Configurável

**Atual:** 60 dias

**Modificação:** Alterar `INTERVAL '60 days'` nas queries

**Impacto:** Altera quantidade de casas consideradas ativas

**Recomendação:** Valores possíveis:
- 30 dias: Apenas casas muito ativas
- 60 dias: **Padrão recomendado**
- 90 dias: Incluir casas com atividade esporádica

---

### Regra 13: Processo de Finalização Configurável

**Atual:** `'phase 3 fcc'`

**Modificação:** Se houver outros processos que indiquem finalização:

```sql
WHERE process NOT IN ('phase 3 fcc', 'closed', 'completed', ...)
```

**Verificar:** Consultar equipe de negócio sobre outros marcadores de finalização

---

## 📚 Glossário de Termos

| Termo | Definição |
|-------|-----------|
| **Casa Ativa** | Casa com atividade recente e não finalizada |
| **Phase Atual** | A phase numericamente mais alta nos registros da casa |
| **Finalização** | Processo 'phase 3 fcc' registrado |
| **Atividade Recente** | Pelo menos 1 registro nos últimos 60 dias |
| **Job** | Identificador único de uma casa em construção |
| **Jobsite** | Nome/localização descritiva da casa |
| **Process** | Tipo de processo/etapa na construção |
| **Phase** | Fase macro da construção (0 a 4) |

---

## 🎯 Regras de Negócio Derivadas

### Regra Derivada 1: Taxa de Distribuição Esperada

**Observação Empírica:**
- Phase 3 e Phase 4: ~25% cada (finalização)
- Phase 0 e Phase 1: ~15-20% (início)
- Phase 2: ~15-20% (meio)

**Uso:** Alertar se distribuição for muito diferente

**Exemplo de Alerta:**
```
⚠️ 80% das casas em Phase 0
→ Possível gargalo em aprovações/permissões
```

---

### Regra Derivada 2: Progressão Esperada

**Premissa:** Casas avançam sequencialmente (0 → 1 → 2 → 3 → 4)

**Implicação:** Casa em Phase 3 deveria ter passado por Phase 1 e 2

**Realidade:** Nem sempre há registros de todas as phases (dados incompletos)

**Tratamento:** Não validamos progressão - apenas pegamos phase mais alta

---

## 📞 Aprovações e Responsabilidades

| Regra | Aprovada Por | Data | Observações |
|-------|--------------|------|-------------|
| Regra 1 (Casa Ativa) | Equipe de Produto | 2025-10-23 | 60 dias aprovado |
| Regra 2 (Phase Atual) | Engenharia | 2025-10-23 | MAX() confirmado |
| Regra 3 (Valores NULL) | Engenharia | 2025-10-23 | Ignorar confirmado |

---

## 🔄 Histórico de Mudanças

| Data | Versão | Mudança | Autor |
|------|--------|---------|-------|
| 2025-10-23 | 1.0 | Criação inicial | Claude Code |
| 2025-10-23 | 2.0 | Adaptação Looker Studio + Novas Regras | Claude Code |

**Mudanças v1.0 → v2.0:**
- ✅ **Regra 14:** Nomenclatura snake_case para Looker Studio
- ✅ **Regra 15:** CONCAT() para percentual
- ✅ **Regra 16:** Tratamento de strings vazias em data_servico
- ✅ **Regra 17:** Query 2 com ultimo_processo e ultimo_status
- ✅ **Regra 18:** Query 5 refatorada para lista individual (260 linhas)
- ✅ **Regra 19:** Query 6 criada para histórico interativo

---

**Status Final:** ✅ Todas as regras validadas com dados reais
**Última Validação:** 2025-10-23
**Compatibilidade:** Google Looker Studio ✓
**Próxima Revisão:** Quando houver mudança nos requisitos de negócio
