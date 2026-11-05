-- Entorno efímero de PostgreSQL para validar la migración VIGIARED.
-- No conecta con Supabase ni con datos reales.
\set ON_ERROR_STOP on

do $roles$
begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end
$roles$;

create schema auth;
create table auth.users (
  id uuid primary key,
  phone text,
  phone_confirmed_at timestamptz
);
create or replace function auth.uid()
returns uuid language sql stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create table public.organizaciones (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  tipo text not null,
  slug text unique,
  estado text not null default 'activa',
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.propietarios_plataforma (
  user_id uuid primary key references auth.users(id),
  activo boolean not null default true
);
create table public.membresias_organizacion (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rol text not null,
  estado text not null,
  unique (organizacion_id,user_id)
);
create table public.unidades (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  nombre text not null,
  tipo text not null,
  direccion text,
  localidad text,
  provincia text,
  codigo_postal text,
  estado text not null default 'activa',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organizacion_id,id)
);
create table public.membresias_unidad (
  id uuid primary key default gen_random_uuid(),
  unidad_id uuid not null references public.unidades(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rol text not null default 'miembro',
  estado text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (unidad_id,user_id)
);
create table public.solicitudes_ingreso (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  unidad_id uuid,
  user_id uuid not null references auth.users(id) on delete cascade,
  estado text not null,
  mensaje text,
  revisada_por uuid references auth.users(id),
  revisada_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (organizacion_id,unidad_id)
    references public.unidades(organizacion_id,id) on delete cascade
);
create table public.perfiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nombre_completo text not null
);
create table public.auditoria (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid references public.organizaciones(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  accion text not null,
  entidad text,
  entidad_id text,
  detalles jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

\ir ../../supabase/migrations/20261105110000_vigiared_manzanas_domicilios_pin.sql

do $assert$
declare
  f record;
begin
  if not exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='manzanas'
      and c.relrowsecurity and c.relforcerowsecurity
  ) then raise exception 'RLS/ FORCE RLS faltante en manzanas'; end if;

  if not exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='credenciales_domicilio'
      and c.relrowsecurity and c.relforcerowsecurity
  ) then raise exception 'RLS/ FORCE RLS faltante en credenciales_domicilio'; end if;

  if has_function_privilege('authenticated',
    'public.crear_domicilio_con_responsable(uuid,uuid,text,text,text,text,text,text,uuid,text,uuid)',
    'EXECUTE') then raise exception 'authenticated no debe ejecutar alta de domicilio'; end if;
  if has_function_privilege('authenticated',
    'public.rotar_pin_domicilio(uuid,text,uuid)','EXECUTE')
    then raise exception 'authenticated no debe rotar PIN directamente'; end if;
  if not has_function_privilege('service_role',
    'public.crear_domicilio_con_responsable(uuid,uuid,text,text,text,text,text,text,uuid,text,uuid)',
    'EXECUTE') then raise exception 'service_role debe ejecutar alta de domicilio'; end if;
  if not has_function_privilege('service_role',
    'public.rotar_pin_domicilio(uuid,text,uuid)','EXECUTE')
    then raise exception 'service_role debe rotar PIN'; end if;
  if not has_function_privilege('authenticated',
    'public.listar_solicitudes_ingreso_pendientes(uuid)','EXECUTE')
    then raise exception 'authenticated debe consultar solicitudes vía RPC'; end if;
  if has_function_privilege('anon',
    'public.listar_solicitudes_ingreso_pendientes(uuid)','EXECUTE')
    then raise exception 'anon no debe consultar solicitudes'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='resolver_solicitud_ingreso'
  ) then raise exception 'Falta RPC de resolución'; end if;
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='listar_solicitudes_ingreso_pendientes'
      and p.prosecdef
  ) then raise exception 'La RPC de solicitudes debe ser SECURITY DEFINER'; end if;
end
$assert$;

select 'OK: migración aplicada y verificaciones de permisos/RLS superadas' as resultado;
