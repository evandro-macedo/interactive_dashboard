-- ============================================================================
-- ÍNDICES DE OTIMIZAÇÃO PARA QUERIES 7-12
-- ============================================================================
-- Data: 2025-10-23
-- Objetivo: Reduzir tempo de execução das queries de pendências
-- Performance Alvo: Reduzir de ~88s para ~15-25s por query
-- ============================================================================

-- IMPORTANTE: Execute estes índices FORA DO HORÁRIO DE PICO
-- Criação de índices bloqueia a tabela temporariamente (usa CONCURRENT quando possível)

-- ============================================================================
-- VERIFICAR ÍNDICES EXISTENTES
-- ============================================================================
-- Execute antes de criar novos índices para evitar duplicação:
--
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE tablename = 'dailylogs'
-- ORDER BY indexname;

-- ============================================================================
-- ÍNDICE 1: Para filtros de STATUS
-- ============================================================================
-- Usado em: Queries 7-12 (todos os filtros de status específicos)
-- Impacto: Queries 7-8 (inspection disapproved/approved), 9-10 (report/checklist done), 11-12 (scheduled/checklist done)
-- Tempo de criação estimado: ~2-3 minutos

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dailylogs_status
ON dailylogs(status);

-- ============================================================================
-- ÍNDICE 2: Para filtros de PROCESS (pattern matching)
-- ============================================================================
-- Usado em: Queries 7-8 (LIKE '%inspection%')
-- Tipo: text_pattern_ops permite LIKE funcionar eficientemente
-- Tempo de criação estimado: ~3-4 minutos

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dailylogs_process_pattern
ON dailylogs(process text_pattern_ops);

-- ============================================================================
-- ÍNDICE 3: Para filtros de PHASE
-- ============================================================================
-- Usado em: Todas as queries (job_max_phase CTE)
-- Impacto: Acelera determinação da phase atual
-- Tempo de criação estimado: ~2 minutos

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dailylogs_phase
ON dailylogs(phase);

-- ============================================================================
-- ÍNDICE 4: Composto JOB_ID + PROCESS + DATECREATED
-- ============================================================================
-- Usado em: Queries 7-12 (todos os JOINs por job_id e process)
-- Tipo: Índice composto para otimizar buscas complexas
-- Mais importante para: Queries 8, 10, 12 (listas detalhadas com DISTINCT ON)
-- Tempo de criação estimado: ~4-5 minutos

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dailylogs_job_process_date
ON dailylogs(job_id, process, datecreated DESC);

-- ============================================================================
-- ÍNDICE 5: Composto JOB_ID + STATUS + DATECREATED
-- ============================================================================
-- Usado em: Queries que buscam último status de cada tipo
-- Otimiza: Buscas por último status específico (ex: último "report", último "scheduled")
-- Tempo de criação estimado: ~4 minutos

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dailylogs_job_status_date
ON dailylogs(job_id, status, datecreated DESC);

-- ============================================================================
-- ÍNDICE 6: Para PROCESS + STATUS (inspeções)
-- ============================================================================
-- Usado em: Queries 7-8 especificamente
-- Otimiza: Filtro combinado "process LIKE '%inspection%' AND status = 'approved/disapproved'"
-- Tempo de criação estimado: ~3 minutos

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dailylogs_process_status
ON dailylogs(process, status);

-- ============================================================================
-- VERIFICAÇÃO PÓS-CRIAÇÃO
-- ============================================================================
-- Execute após criar todos os índices para confirmar:

SELECT
  indexname,
  pg_size_pretty(pg_relation_size(indexname::regclass)) as index_size,
  idx_scan as times_used,
  idx_tup_read as tuples_read,
  idx_tup_fetch as tuples_fetched
FROM pg_indexes i
JOIN pg_stat_user_indexes s ON i.indexname = s.indexname
WHERE i.tablename = 'dailylogs'
  AND i.indexname LIKE 'idx_dailylogs_%'
ORDER BY i.indexname;

-- ============================================================================
-- ANALYZE APÓS ÍNDICES
-- ============================================================================
-- IMPORTANTE: Executar ANALYZE para atualizar estatísticas do planner
ANALYZE dailylogs;

-- ============================================================================
-- MONITORING E MANUTENÇÃO
-- ============================================================================
--
-- 1. VERIFICAR USO DOS ÍNDICES:
--    Execute periodicamente (semanal) para ver quais índices estão sendo usados:
--
--    SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
--    FROM pg_stat_user_indexes
--    WHERE tablename = 'dailylogs'
--    ORDER BY idx_scan DESC;
--
-- 2. VACUUM E REINDEX (se necessário):
--    Se índices ficarem fragmentados (após muitos UPDATEs/DELETEs):
--
--    VACUUM ANALYZE dailylogs;
--    -- ou (mais agressivo, requer mais tempo):
--    REINDEX TABLE CONCURRENTLY dailylogs;
--
-- 3. VERIFICAR BLOAT DE ÍNDICES:
--    Índices podem crescer mais que o necessário. Monitorar tamanho:
--
--    SELECT indexname, pg_size_pretty(pg_relation_size(indexname::regclass))
--    FROM pg_indexes
--    WHERE tablename = 'dailylogs'
--    ORDER BY pg_relation_size(indexname::regclass) DESC;
--
-- ============================================================================
-- NOTAS TÉCNICAS
-- ============================================================================
--
-- 1. CONCURRENT vs Normal:
--    - CONCURRENT: Não bloqueia escrita, mas leva mais tempo
--    - Normal: Bloqueia escrita, mais rápido
--    - Para produção: SEMPRE use CONCURRENT
--
-- 2. IF NOT EXISTS:
--    - Evita erro se índice já existe
--    - Safe para re-executar script
--
-- 3. text_pattern_ops:
--    - Necessário para LIKE funcionar com índices
--    - Sem isso, LIKE %pattern% faz full table scan
--
-- 4. Tamanho Esperado dos Índices:
--    - idx_dailylogs_status: ~3-5 MB
--    - idx_dailylogs_process_pattern: ~5-8 MB
--    - idx_dailylogs_phase: ~2-3 MB
--    - idx_dailylogs_job_process_date: ~10-15 MB
--    - idx_dailylogs_job_status_date: ~10-12 MB
--    - idx_dailylogs_process_status: ~5-7 MB
--    Total adicional: ~35-50 MB
--
-- 5. Tempo Total de Criação:
--    - Com CONCURRENT: ~18-23 minutos
--    - Pode executar todos de uma vez (rodam em paralelo)
--    - Zero downtime, aplicação continua funcionando
--
-- ============================================================================
-- IMPACTO ESPERADO
-- ============================================================================
--
-- Query 7 (Inspeções Resumo):
--   Antes: 88 segundos
--   Depois: ~20-30 segundos (65-75% redução)
--
-- Query 8 (Inspeções Detalhe):
--   Estimado: ~15-25 segundos
--
-- Queries 9-12:
--   Estimado: ~15-30 segundos cada
--
-- NOTA: Performance final depende de:
--   - RAM disponível (upgrade para 2GB recomendado)
--   - Carga atual do RDS
--   - Quantidade de dados filtrados
--
-- ============================================================================
-- CHANGELOG
-- ============================================================================
-- v1.0 (2025-10-23): Script inicial
--   - 6 índices criados para otimizar Queries 7-12
--   - Todos com CONCURRENT para zero downtime
-- ============================================================================
