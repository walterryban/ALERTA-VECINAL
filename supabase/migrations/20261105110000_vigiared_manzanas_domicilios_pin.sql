-- VIGIARED v0.2 — manzanas, domicilios, PIN y solicitudes
-- SOLO PROPUESTA: no ejecutar en producción sin revisión y pruebas.
-- Requiere las tablas y funciones base de VIGIARED v0.1.

begin;

create table if not exists public.manzanas (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  nombre text not null check (length(btrim(nombre)) between 2 and 120),
  public_id uuid not null default gen_random_uuid() unique,
  estado text not null default 'activa'
    check (estado in ('activa','inactiva','suspendida')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organizacion_id, id)
);

create index if not exists manzanas_org_estado_idx
  on public.manzanas (organizacion_id, estado);

alter table public.unidades
  add column if not exists manzana_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.unidades'::regclass
      and conname = 'unidades_organizacion_manzana_fkey'
  ) then
    alter table public.unidades
      add constraint unidades_organizacion_manzana_fkey
      foreign key (organizacion_id, manzana_id)
      references public.manzanas (organizacion_id, id)
      on delete restrict;
  end if;
end $$;

create index if not exists unidades_manzana_estado_idx
  on public.unidades (manzana_id, estado);

create table if not exists public.credenciales_domicilio (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  unidad_id uuid not null,
  pin_hmac text not null unique
    check (pin_hmac ~ '^[0-9a-f]{64}$'),
  estado text not null default 'activa'
    check (estado in ('activa','revocada')),
  emitido_por uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  revocado_at timestamptz,
  foreign key (organizacion_id, unidad_id)
    references public.unidades (organizacion_id, id) on delete cascade,
  check ((estado = 'activa' and revocado_at is null)
      or (estado = 'revocada' and revocado_at is not null))
);

create unique index if not exists credenciales_unidad_pin_activo_uidx
  on public.credenciales_domicilio (unidad_id) where estado = 'activa';

create table if not exists public.intentos_pin (
  user_id uuid not null references auth.users(id) on delete cascade,
  manzana_id uuid not null references public.manzanas(id) on delete cascade,
  intentos integer not null default 0 check (intentos between 0 and 5),
  ventana_desde timestamptz not null default now(),
  bloqueado_hasta timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, manzana_id)
);

-- Sin acceso directo desde clientes: todas las operaciones pasan por RPC.
alter table public.manzanas enable row level security;
alter table public.manzanas force row level security;
alter table public.credenciales_domicilio enable row level security;
alter table public.credenciales_domicilio force row level security;
alter table public.intentos_pin enable row level security;
alter table public.intentos_pin force row level security;

revoke all on public.manzanas from public, anon, authenticated, service_role;
revoke all on public.credenciales_domicilio from public, anon, authenticated, service_role;
revoke all on public.intentos_pin from public, anon, authenticated, service_role;

create or replace function public._vigiared_puede_administrar_org(p_organizacion_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and (
    public.es_propietario_plataforma()
    or exists (
      select 1
      from public.membresias_organizacion mo
      where mo.organizacion_id = p_organizacion_id
        and mo.user_id = auth.uid()
        and mo.rol = 'administrador_organizacion'
        and mo.estado = 'activa'
    )
  );
$$;

revoke all on function public._vigiared_puede_administrar_org(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.crear_manzana(
  p_organizacion_id uuid,
  p_nombre text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_public_id uuid;
  v_nombre text := btrim(coalesce(p_nombre, ''));
begin
  if auth.uid() is null then
    raise exception 'Autenticación requerida';
  end if;
  if not public._vigiared_puede_administrar_org(p_organizacion_id) then
    raise exception 'No autorizado para administrar esta organización';
  end if;
  if length(v_nombre) < 2 or length(v_nombre) > 120 then
    raise exception 'Nombre de manzana inválido';
  end if;

  insert into public.manzanas (organizacion_id, nombre, created_by)
  values (p_organizacion_id, v_nombre, auth.uid())
  returning id, public_id into v_id, v_public_id;

  insert into public.auditoria
    (organizacion_id, actor_user_id, accion, entidad, entidad_id, detalles)
  values
    (p_organizacion_id, auth.uid(), 'manzana.creada', 'manzanas',
     v_id::text, jsonb_build_object('nombre', v_nombre));

  return jsonb_build_object(
    'ok', true, 'manzana_id', v_id, 'qr_public_id', v_public_id,
    'nombre', v_nombre
  );
end;
$$;

create or replace function public.crear_domicilio_con_responsable(
  p_organizacion_id uuid,
  p_manzana_id uuid,
  p_nombre text,
  p_tipo text,
  p_direccion text,
  p_localidad text,
  p_provincia text,
  p_codigo_postal text,
  p_responsable_user_id uuid,
  p_pin_hmac text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_unidad_id uuid;
  v_nombre text := btrim(coalesce(p_nombre, ''));
begin
  if auth.uid() is null then raise exception 'Autenticación requerida'; end if;
  if not public._vigiared_puede_administrar_org(p_organizacion_id) then
    raise exception 'No autorizado para administrar esta organización';
  end if;
  if length(v_nombre) < 1 or length(v_nombre) > 150 then
    raise exception 'Identificación del domicilio inválida';
  end if;
  if p_tipo not in ('vivienda','departamento','habitacion','comercio','establecimiento','otra') then
    raise exception 'Tipo de unidad inválido';
  end if;
  if p_pin_hmac !~ '^[0-9a-f]{64}$' then
    raise exception 'Credencial inválida';
  end if;
  if not exists (
    select 1
    from auth.users u
    where u.id = p_responsable_user_id
      and nullif(u.phone, '') is not null
      and u.phone_confirmed_at is not null
  ) then
    raise exception 'La cuenta responsable debe tener un teléfono verificado';
  end if;
  if not exists (
    select 1 from public.manzanas m
    where m.id = p_manzana_id
      and m.organizacion_id = p_organizacion_id
      and m.estado = 'activa'
  ) then
    raise exception 'Manzana no disponible';
  end if;

  insert into public.unidades
    (organizacion_id, manzana_id, nombre, tipo, direccion, localidad,
     provincia, codigo_postal, estado, created_by)
  values
    (p_organizacion_id, p_manzana_id, v_nombre, p_tipo,
     nullif(btrim(coalesce(p_direccion,'')), ''),
     nullif(btrim(coalesce(p_localidad,'')), ''),
     nullif(btrim(coalesce(p_provincia,'')), ''),
     nullif(btrim(coalesce(p_codigo_postal,'')), ''),
     'activa', auth.uid())
  returning id into v_unidad_id;

  insert into public.membresias_unidad
    (unidad_id, user_id, rol, estado)
  values (v_unidad_id, p_responsable_user_id, 'responsable', 'activa');

  insert into public.credenciales_domicilio
    (organizacion_id, unidad_id, pin_hmac, emitido_por)
  values (p_organizacion_id, v_unidad_id, p_pin_hmac, auth.uid());

  insert into public.auditoria
    (organizacion_id, actor_user_id, accion, entidad, entidad_id, detalles)
  values
    (p_organizacion_id, auth.uid(), 'domicilio.creado',
     'unidades', v_unidad_id::text,
     jsonb_build_object('manzana_id', p_manzana_id,
                        'responsable_user_id', p_responsable_user_id,
                        'tipo', p_tipo));

  return jsonb_build_object('ok', true, 'unidad_id', v_unidad_id);
end;
$$;

create or replace function public.rotar_pin_domicilio(
  p_unidad_id uuid,
  p_pin_hmac_nuevo text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_autorizado boolean;
begin
  if auth.uid() is null then raise exception 'Autenticación requerida'; end if;
  if p_pin_hmac_nuevo !~ '^[0-9a-f]{64}$' then
    raise exception 'Credencial inválida';
  end if;

  select u.organizacion_id into v_org
  from public.unidades u where u.id = p_unidad_id and u.estado = 'activa';

  if v_org is null then raise exception 'Domicilio no disponible'; end if;

  v_autorizado := public._vigiared_puede_administrar_org(v_org)
    or exists (
      select 1 from public.membresias_unidad mu
      where mu.unidad_id = p_unidad_id
        and mu.user_id = auth.uid()
        and mu.rol = 'responsable'
        and mu.estado = 'activa'
    );

  if not v_autorizado then raise exception 'No autorizado'; end if;

  update public.credenciales_domicilio
  set estado = 'revocada', revocado_at = now()
  where unidad_id = p_unidad_id and estado = 'activa';

  insert into public.credenciales_domicilio
    (organizacion_id, unidad_id, pin_hmac, emitido_por)
  values (v_org, p_unidad_id, p_pin_hmac_nuevo, auth.uid());

  insert into public.auditoria
    (organizacion_id, actor_user_id, accion, entidad, entidad_id, detalles)
  values (v_org, auth.uid(), 'domicilio.pin_rotado',
          'unidades', p_unidad_id::text, '{}'::jsonb);

  return jsonb_build_object('ok', true);
end;
$$;

create unique index if not exists solicitudes_ingreso_pendiente_uidx
  on public.solicitudes_ingreso (unidad_id, user_id)
  where estado = 'pendiente';

create or replace function public.solicitar_ingreso_con_pin(
  p_manzana_public_id uuid,
  p_pin_hmac text,
  p_mensaje text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_manzana_id uuid;
  v_org uuid;
  v_unidad_id uuid;
  v_intentos integer;
  v_solicitud_id uuid;
begin
  if v_user is null then raise exception 'Autenticación requerida'; end if;
  if p_pin_hmac !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false, 'mensaje', 'No se pudo validar el ingreso');
  end if;

  select m.id, m.organizacion_id into v_manzana_id, v_org
  from public.manzanas m
  where m.public_id = p_manzana_public_id and m.estado = 'activa';

  if v_manzana_id is null then
    return jsonb_build_object('ok', false, 'mensaje', 'No se pudo validar el ingreso');
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_user::text || ':' || v_manzana_id::text, 0)
  );

  select i.intentos into v_intentos
  from public.intentos_pin i
  where i.user_id = v_user and i.manzana_id = v_manzana_id
    and i.bloqueado_hasta > now();

  if found then
    return jsonb_build_object('ok', false, 'mensaje', 'Demasiados intentos. Probá más tarde');
  end if;

  select c.unidad_id into v_unidad_id
  from public.credenciales_domicilio c
  join public.unidades u on u.id = c.unidad_id
  where u.manzana_id = v_manzana_id
    and u.estado = 'activa'
    and c.estado = 'activa'
    and c.pin_hmac = p_pin_hmac
  limit 1;

  if v_unidad_id is null then
    insert into public.intentos_pin
      (user_id, manzana_id, intentos, ventana_desde, bloqueado_hasta, updated_at)
    values (v_user, v_manzana_id, 1, now(), null, now())
    on conflict (user_id, manzana_id) do update
    set intentos = case
          when public.intentos_pin.ventana_desde < now() - interval '15 minutes' then 1
          else least(public.intentos_pin.intentos + 1, 5)
        end,
        ventana_desde = case
          when public.intentos_pin.ventana_desde < now() - interval '15 minutes' then now()
          else public.intentos_pin.ventana_desde
        end,
        bloqueado_hasta = case
          when public.intentos_pin.ventana_desde < now() - interval '15 minutes' then null
          when public.intentos_pin.intentos + 1 >= 5 then now() + interval '15 minutes'
          else null
        end,
        updated_at = now();

    return jsonb_build_object('ok', false, 'mensaje', 'No se pudo validar el ingreso');
  end if;

  if exists (
    select 1 from public.membresias_unidad mu
    where mu.unidad_id = v_unidad_id and mu.user_id = v_user
      and mu.estado = 'activa'
  ) then
    return jsonb_build_object('ok', false, 'mensaje', 'No se pudo validar el ingreso');
  end if;

  insert into public.solicitudes_ingreso
    (organizacion_id, unidad_id, user_id, estado, mensaje)
  values (v_org, v_unidad_id, v_user, 'pendiente',
          case when p_mensaje is null then null else left(p_mensaje, 1000) end)
  on conflict (unidad_id, user_id) where estado = 'pendiente' do nothing;

  select s.id into v_solicitud_id
  from public.solicitudes_ingreso s
  where s.unidad_id = v_unidad_id and s.user_id = v_user
    and s.estado = 'pendiente'
  order by s.created_at desc limit 1;

  insert into public.intentos_pin
    (user_id, manzana_id, intentos, ventana_desde, bloqueado_hasta, updated_at)
  values (v_user, v_manzana_id, 0, now(), null, now())
  on conflict (user_id, manzana_id) do update
  set intentos = 0, ventana_desde = now(), bloqueado_hasta = null, updated_at = now();

  insert into public.auditoria
    (organizacion_id, actor_user_id, accion, entidad, entidad_id, detalles)
  values (v_org, v_user, 'ingreso.solicitado', 'solicitudes_ingreso',
          v_solicitud_id::text, jsonb_build_object('unidad_id', v_unidad_id));

  return jsonb_build_object('ok', true, 'solicitud_id', v_solicitud_id);
end;
$$;

create or replace function public.resolver_solicitud_ingreso(
  p_solicitud_id uuid,
  p_aprobar boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_s public.solicitudes_ingreso%rowtype;
  v_autorizado boolean;
begin
  if auth.uid() is null then raise exception 'Autenticación requerida'; end if;

  select * into v_s
  from public.solicitudes_ingreso
  where id = p_solicitud_id
  for update;

  if not found or v_s.estado <> 'pendiente' or v_s.unidad_id is null then
    raise exception 'Solicitud no disponible';
  end if;

  v_autorizado := public._vigiared_puede_administrar_org(v_s.organizacion_id)
    or exists (
      select 1 from public.membresias_unidad mu
      where mu.unidad_id = v_s.unidad_id
        and mu.user_id = auth.uid()
        and mu.rol = 'responsable'
        and mu.estado = 'activa'
    );

  if not v_autorizado then raise exception 'No autorizado'; end if;

  if p_aprobar then
    if exists (
      select 1 from public.membresias_unidad mu
      where mu.unidad_id = v_s.unidad_id and mu.user_id = v_s.user_id
    ) then
      raise exception 'Ya existe una membresía para esta cuenta';
    end if;

    insert into public.membresias_unidad
      (unidad_id, user_id, rol, estado)
    values (v_s.unidad_id, v_s.user_id, 'miembro', 'activa');
  end if;

  update public.solicitudes_ingreso
  set estado = case when p_aprobar then 'aprobada' else 'rechazada' end,
      revisada_por = auth.uid(),
      revisada_at = now()
  where id = p_solicitud_id;

  insert into public.auditoria
    (organizacion_id, actor_user_id, accion, entidad, entidad_id, detalles)
  values (v_s.organizacion_id, auth.uid(),
          case when p_aprobar then 'ingreso.aprobado' else 'ingreso.rechazado' end,
          'solicitudes_ingreso', p_solicitud_id::text,
          jsonb_build_object('unidad_id', v_s.unidad_id,
                             'usuario_solicitante', v_s.user_id));

  return jsonb_build_object('ok', true, 'estado',
    case when p_aprobar then 'aprobada' else 'rechazada' end);
end;
$$;

-- Los índices de unicidad se crean antes de las RPC que los utilizan.

revoke all on function public.crear_manzana(uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function public.crear_domicilio_con_responsable(uuid,uuid,text,text,text,text,text,text,uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function public.rotar_pin_domicilio(uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function public.solicitar_ingreso_con_pin(uuid,text,text)
  from public, anon, service_role;
revoke all on function public.resolver_solicitud_ingreso(uuid,boolean)
  from public, anon, service_role;

grant execute on function public.crear_manzana(uuid,text) to authenticated;
grant execute on function public.crear_domicilio_con_responsable(uuid,uuid,text,text,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.rotar_pin_domicilio(uuid,text) to authenticated;
grant execute on function public.solicitar_ingreso_con_pin(uuid,text,text) to authenticated;
grant execute on function public.resolver_solicitud_ingreso(uuid,boolean) to authenticated;

commit;
