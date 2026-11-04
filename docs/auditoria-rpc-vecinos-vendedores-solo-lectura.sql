-- ALERTA VECINAL PRO
-- AUDITORIA DE RPC / FUNCIONES / DEPENDENCIAS — SOLO LECTURA
-- Rama: integracion-segura-2026-11-04
--
-- OBJETIVO:
-- Identificar funciones que leen o modifican vecinos/vendedores y revisar
-- sus propietarios, SECURITY DEFINER, search_path y permisos EXECUTE.
--
-- SEGURIDAD:
-- * Este archivo contiene exclusivamente SELECT.
-- * No consulta filas personales de vecinos ni vendedores.
-- * No cambia permisos, funciones, tablas, políticas ni datos.
-- * Copiar y ejecutar el archivo completo en Supabase SQL Editor.
-- * Compartir los resultados; no pegar claves, tokens ni credenciales.

-- 1) Funciones SECURITY DEFINER o que mencionan las tablas protegidas.
SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid) AS result_type,
  pg_get_userbyid(p.proowner) AS owner,
  p.prosecdef AS security_definer,
  p.proconfig AS function_settings,
  p.proacl AS execute_acl,
  pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('public', 'auth', 'extensions')
  AND p.prokind IN ('f', 'p')
  AND (
    p.prosecdef
    OR pg_get_functiondef(p.oid) ILIKE '%public.vecinos%'
    OR pg_get_functiondef(p.oid) ILIKE '%public.vendedores%'
    OR pg_get_functiondef(p.oid) ILIKE '% vecinos%'
    OR pg_get_functiondef(p.oid) ILIKE '% vendedores%'
  )
ORDER BY n.nspname, p.proname, arguments;

-- 2) Permisos EXECUTE efectivos declarados para funciones relacionadas
-- con vecinos/vendedores o SECURITY DEFINER en public.
SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE r.rolname END AS grantee,
  x.privilege_type,
  x.is_grantable
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL aclexplode(
  COALESCE(p.proacl, acldefault('f', p.proowner))
) AS x
LEFT JOIN pg_roles r ON r.oid = x.grantee
WHERE n.nspname = 'public'
  AND p.prokind IN ('f', 'p')
  AND (
    p.prosecdef
    OR pg_get_functiondef(p.oid) ILIKE '%vecinos%'
    OR pg_get_functiondef(p.oid) ILIKE '%vendedores%'
  )
ORDER BY n.nspname, p.proname, arguments, r.rolname;

-- 3) Triggers asociados a vecinos o vendedores.
SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  t.tgname AS trigger_name,
  pg_get_triggerdef(t.oid, true) AS trigger_definition,
  p.proname AS trigger_function,
  pn.nspname AS function_schema
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p ON p.oid = t.tgfoid
JOIN pg_namespace pn ON pn.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('vecinos', 'vendedores')
  AND NOT t.tgisinternal
ORDER BY c.relname, t.tgname;

-- 4) Vistas que dependen de vecinos o vendedores.
SELECT DISTINCT
  schemaname,
  viewname,
  definition
FROM pg_views
WHERE schemaname = 'public'
  AND (
    definition ILIKE '%vecinos%'
    OR definition ILIKE '%vendedores%'
  )
ORDER BY viewname;

-- 5) Privilegios directos actuales sobre ambas tablas.
SELECT
  grantee,
  table_name,
  privilege_type,
  is_grantable
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('vecinos', 'vendedores')
ORDER BY table_name, grantee, privilege_type;

-- 6) Estado RLS y propietario de ambas tablas.
SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS rls_forced,
  pg_get_userbyid(c.relowner) AS owner
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('vecinos', 'vendedores')
ORDER BY c.relname;
