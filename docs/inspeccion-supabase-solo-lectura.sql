-- ALERTA VECINAL PRO
-- INSPECCIÓN DE SOLO LECTURA — ejecutar en Supabase SQL Editor.
-- Este archivo NO crea, modifica ni elimina objetos ni datos.
-- Copiar los resultados de cada consulta para revisar la migración aditiva.

-- 1) Columnas, tipos, nulabilidad, defaults e identidad de tablas públicas.
SELECT
  c.table_name, c.ordinal_position, c.column_name,
  c.data_type, c.udt_name, c.is_nullable,
  c.column_default, c.is_identity
FROM information_schema.columns c
WHERE c.table_schema = 'public'
  AND c.table_name IN ('manzanas','vecinos','operadores','alertas','vendedores')
ORDER BY c.table_name, c.ordinal_position;

-- 2) Claves primarias, foráneas, UNIQUE y CHECK de esas tablas.
SELECT
  tc.table_name, tc.constraint_name, tc.constraint_type,
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
  AND tc.table_name IN ('manzanas','vecinos','operadores','alertas','vendedores')
ORDER BY tc.table_name, tc.constraint_type, tc.constraint_name;

-- 3) Índices existentes.
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('manzanas','vecinos','operadores','alertas','vendedores')
ORDER BY tablename, indexname;

-- 4) RLS habilitado y políticas vigentes.
SELECT
  n.nspname AS schema_name, c.relname AS table_name,
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY c.relname;

SELECT
  schemaname, tablename, policyname, permissive,
  roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- 5) Definición completa, argumentos, propietario y SECURITY DEFINER
-- de funciones públicas relacionadas con acceso y alertas.
SELECT
  p.oid::regprocedure AS firma,
  r.rolname AS propietario,
  p.prosecdef AS security_definer,
  p.proconfig AS configuracion,
  pg_get_functiondef(p.oid) AS definicion
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_roles r ON r.oid = p.proowner
WHERE n.nspname = 'public'
  AND p.proname IN ('validar_acceso','crear_alerta')
ORDER BY p.proname, p.oid::regprocedure::text;

-- 6) Permisos EXECUTE de esas funciones.
SELECT
  p.oid::regprocedure AS firma,
  CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE gr.rolname END AS otorgado_a,
  x.privilege_type, x.is_grantable
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) x
LEFT JOIN pg_roles gr ON gr.oid = x.grantee
WHERE n.nspname = 'public'
  AND p.proname IN ('validar_acceso','crear_alerta')
ORDER BY firma::text, otorgado_a;

-- 7) Tablas publicadas para Supabase Realtime.
SELECT
  pub.pubname AS publication_name,
  n.nspname AS schema_name,
  c.relname AS table_name
FROM pg_publication_tables pub
JOIN pg_class c ON c.relname = pub.tablename
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE pub.schemaname = 'public'
ORDER BY pub.pubname, c.relname;

-- 8) Cantidad de registros actuales (sin mostrar datos personales).
SELECT 'manzanas' AS tabla, count(*) AS registros FROM public.manzanas
UNION ALL SELECT 'vecinos', count(*) FROM public.vecinos
UNION ALL SELECT 'operadores', count(*) FROM public.operadores
UNION ALL SELECT 'alertas', count(*) FROM public.alertas
UNION ALL SELECT 'vendedores', count(*) FROM public.vendedores;
