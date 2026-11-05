-- VIGIARED — Inspección de compatibilidad territorial
-- SOLO LECTURA. No crea, modifica ni elimina tablas, datos, funciones o permisos.
-- Ejecutar en Supabase SQL Editor y compartir los resultados de metadatos.
-- No devuelve nombres, teléfonos, direcciones ni registros personales.

-- 1) Columnas de las tablas relevantes existentes.
SELECT
  table_name,
  ordinal_position,
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('organizaciones', 'unidades', 'manzanas', 'manzanas_vigiared')
ORDER BY table_name, ordinal_position;

-- 2) Constraints: PK, FK, UNIQUE y CHECK.
SELECT
  tc.table_name,
  tc.constraint_name,
  tc.constraint_type,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name,
  chk.check_clause
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu
  ON tc.constraint_schema = kcu.constraint_schema
 AND tc.constraint_name = kcu.constraint_name
 AND tc.table_name = kcu.table_name
LEFT JOIN information_schema.constraint_column_usage ccu
  ON tc.constraint_schema = ccu.constraint_schema
 AND tc.constraint_name = ccu.constraint_name
LEFT JOIN information_schema.check_constraints chk
  ON tc.constraint_schema = chk.constraint_schema
 AND tc.constraint_name = chk.constraint_name
WHERE tc.constraint_schema = 'public'
  AND tc.table_name IN ('organizaciones', 'unidades', 'manzanas', 'manzanas_vigiared')
ORDER BY tc.table_name, tc.constraint_type, tc.constraint_name, kcu.ordinal_position;

-- 3) Índices existentes.
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('organizaciones', 'unidades', 'manzanas', 'manzanas_vigiared')
ORDER BY tablename, indexname;

-- 4) RLS habilitado/forzado y políticas existentes.
SELECT
  c.relname AS table_name,
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')
  AND c.relname IN ('organizaciones', 'unidades', 'manzanas', 'manzanas_vigiared')
ORDER BY c.relname;

SELECT
  schemaname, tablename, policyname, permissive,
  roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('organizaciones', 'unidades', 'manzanas', 'manzanas_vigiared')
ORDER BY tablename, policyname;

-- 5) Triggers no internos.
SELECT
  c.relname AS table_name,
  t.tgname AS trigger_name,
  pg_get_triggerdef(t.oid, true) AS definition
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE NOT t.tgisinternal
  AND n.nspname = 'public'
  AND c.relname IN ('organizaciones', 'unidades', 'manzanas', 'manzanas_vigiared')
ORDER BY c.relname, t.tgname;

-- 6) Tipos de columnas críticas y existencia de created_by / manzana_id.
SELECT
  table_name,
  bool_or(column_name = 'created_by') AS tiene_created_by,
  bool_or(column_name = 'manzana_id') AS tiene_manzana_id,
  bool_or(column_name = 'manzana_vigiared_id') AS tiene_manzana_vigiared_id
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('unidades', 'manzanas', 'manzanas_vigiared')
GROUP BY table_name
ORDER BY table_name;

-- Fin: todas las sentencias son SELECT sobre catálogos de PostgreSQL.
