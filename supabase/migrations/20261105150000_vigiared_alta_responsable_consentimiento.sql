-- VIGIARED v0.4 — alta de domicilio e invitación con aceptación del responsable
-- Propuesta para pruebas aisladas. No ejecutar en Supabase real sin aprobación.
begin;

create table if not exists public.invitaciones_responsable (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  unidad_id uuid not null,
  email_destino text not null check (length(email_destino) between 3 and 254),
  token_hmac text not null unique check (token_hmac ~ '^[0-9a-f]{64}$'),
  estado text not null default 'pendiente'
    check (estado in ('pendiente','aceptada','revocada','vencida')),
  vence_at timestamptz not null,
  creada_por uuid references auth.users(id) on delete set null,
  aceptada_por uuid references auth.users(id) on delete set null,
  creada_at timestamptz not null default now(),
  aceptada_at timestamptz,
  revocada_at timestamptz,
  foreign key (organizacion_id, unidad_id)
    references public.unidades (organizacion_id, id) on delete cascade,
  check (
    (estado = 'pendiente' and aceptada_at is null and revocada_at is null)
    or (estado = 'aceptada' and aceptada_at is not null and revocada_at is null)
    or (estado = 'revocada' and revocada_at is not null)
    or (estado = 'vencida' and aceptada_at is null)
  )
);

create unique index if not exists invitaciones_responsable_pendiente_unidad_uidx
  on public.invitaciones_responsable (unidad_id)
  where estado = 'pendiente';

create index if not exists invitaciones_responsable_vencimiento_idx
  on public.invitaciones_responsable (vence_at)
  where estado = 'pendiente';

alter table public.invitaciones_responsable enable row level security;
alter table public.invitaciones_responsable force row level security;
revoke all on public.invitaciones_responsable from public, anon, authenticated, service_role;

-- Registra domicilio sin adjudicar responsable ni emitir PIN.
create or replace function public.crear_domicilio_pendiente(
  p_organizacion_id uuid,
  p_manzana_vigiared_id uuid,
  p_nombre text,
  p_tipo text,
  p_direccion text default null,
  p_localidad text default null,
  p_provincia text default null,
  p_codigo_postal text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_unidad_id uuid;
  v_nombre text := btrim(coalesce(p_nombre,''));
begin
  if v_actor is null then raise exception 'Autenticación requerida'; end if;
  if not public._vigiared_puede_administrar_org(p_organizacion_id,v_actor) then
    raise exception 'No autorizado';
  end if;
  if not exists(select 1 from public.organizaciones o
    where o.id=p_organizacion_id and o.estado='activa') then
    raise exception 'Organización no disponible';
  end if;
  if not exists(select 1 from public.manzanas_vigiared m
    where m.id=p_manzana_vigiared_id and m.organizacion_id=p_organizacion_id
      and m.estado='activa') then raise exception 'Manzana no disponible'; end if;
  if length(v_nombre)<1 or length(v_nombre)>150 then
    raise exception 'Identificación del domicilio inválida';
  end if;
  if p_tipo not in ('vivienda','departamento','habitacion','comercio','establecimiento','otra') then
    raise exception 'Tipo de unidad inválido';
  end if;
  insert into public.unidades(
    organizacion_id,manzana_vigiared_id,nombre,tipo,direccion,localidad,
    provincia,codigo_postal,estado,created_by
  ) values (
    p_organizacion_id,p_manzana_vigiared_id,v_nombre,p_tipo,
    nullif(btrim(coalesce(p_direccion,'')),''),
    nullif(btrim(coalesce(p_localidad,'')),''),
    nullif(btrim(coalesce(p_provincia,'')),''),
    nullif(btrim(coalesce(p_codigo_postal,'')),''),
    'activa',v_actor
  ) returning id into v_unidad_id;

  insert into public.auditoria(
    organizacion_id,actor_user_id,accion,entidad,entidad_id,detalles
  ) values (
    p_organizacion_id,v_actor,'domicilio.creado_pendiente_responsable',
    'unidades',v_unidad_id::text,
    jsonb_build_object('manzana_vigiared_id',p_manzana_vigiared_id,'tipo',p_tipo)
  );
  return jsonb_build_object('ok',true,'unidad_id',v_unidad_id,'estado_responsable','pendiente');
end;
$$;

-- Crea invitación de un solo uso. Sólo la Edge Function entrega el token legible.
create or replace function public.crear_invitacion_responsable(
  p_unidad_id uuid,
  p_email_destino text,
  p_token_hmac text,
  p_vence_at timestamptz,
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_email text := lower(btrim(coalesce(p_email_destino,'')));
  v_id uuid;
begin
  if p_actor_user_id is null or not exists(select 1 from auth.users where id=p_actor_user_id) then
    raise exception 'Actor no válido';
  end if;
  select u.organizacion_id into v_org
  from public.unidades u
  join public.organizaciones o on o.id=u.organizacion_id and o.estado='activa'
  where u.id=p_unidad_id and u.estado='activa';
  if v_org is null or not public._vigiared_puede_administrar_org(v_org,p_actor_user_id) then
    raise exception 'No autorizado o domicilio no disponible';
  end if;
  if length(v_email)<3 or length(v_email)>254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
    raise exception 'Correo destinatario inválido';
  end if;
  if p_token_hmac !~ '^[0-9a-f]{64}$' then raise exception 'Token inválido'; end if;
  if p_vence_at <= now() or p_vence_at > now()+interval '7 days' then
    raise exception 'Vencimiento inválido';
  end if;
  if exists(select 1 from public.membresias_unidad mu
    where mu.unidad_id=p_unidad_id and mu.rol='responsable' and mu.estado='activa') then
    raise exception 'El domicilio ya tiene responsable activo';
  end if;

  update public.invitaciones_responsable
  set estado='revocada',revocada_at=now()
  where unidad_id=p_unidad_id and estado='pendiente';

  insert into public.invitaciones_responsable(
    organizacion_id,unidad_id,email_destino,token_hmac,vence_at,creada_por
  ) values(v_org,p_unidad_id,v_email,p_token_hmac,p_vence_at,p_actor_user_id)
  returning id into v_id;

  insert into public.auditoria(
    organizacion_id,actor_user_id,accion,entidad,entidad_id,detalles
  ) values(v_org,p_actor_user_id,'responsable.invitacion_creada',
    'invitaciones_responsable',v_id::text,jsonb_build_object('unidad_id',p_unidad_id));

  return jsonb_build_object('ok',true,'invitacion_id',v_id,'vence_at',p_vence_at);
end;
$$;

-- Consume token y crea membresía responsable en una única transacción.
create or replace function public.aceptar_invitacion_responsable(
  p_token_hmac text,
  p_actor_user_id uuid,
  p_pin_hmac text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv public.invitaciones_responsable%rowtype;
  v_email text;
  v_estado_membresia text;
begin
  -- La Edge Function valida el JWT con auth.getUser y transmite este UUID.
  -- Esta RPC sólo admite service_role; el email confirmado debe coincidir con la invitación.
  if p_actor_user_id is null or not exists(select 1 from auth.users where id=p_actor_user_id) then
    raise exception 'Identidad autenticada no válida';
  end if;
  if p_token_hmac !~ '^[0-9a-f]{64}$' or p_pin_hmac !~ '^[0-9a-f]{64}$' then
    raise exception 'Credencial inválida';
  end if;

  select lower(btrim(u.email)) into v_email
  from auth.users u
  where u.id=p_actor_user_id and u.email_confirmed_at is not null
    and nullif(u.email,'') is not null;
  if v_email is null then raise exception 'Se requiere correo electrónico verificado'; end if;

  select * into v_inv
  from public.invitaciones_responsable i
  where i.token_hmac=p_token_hmac
  for update;
  if not found or v_inv.estado<>'pendiente' or v_inv.vence_at<=now()
    or v_inv.email_destino<>v_email then
    raise exception 'Invitación no válida o no disponible';
  end if;

  if not exists(select 1 from public.unidades u
    join public.organizaciones o on o.id=u.organizacion_id
    join public.manzanas_vigiared m on m.id=u.manzana_vigiared_id
    where u.id=v_inv.unidad_id and u.estado='activa'
      and o.estado='activa' and m.estado='activa') then
    raise exception 'Domicilio no disponible';
  end if;

  select mu.estado into v_estado_membresia
  from public.membresias_unidad mu
  where mu.unidad_id=v_inv.unidad_id and mu.user_id=p_actor_user_id
  for update;
  if found and v_estado_membresia='activa' then
    raise exception 'La cuenta ya tiene acceso activo al domicilio';
  elsif found then
    update public.membresias_unidad
    set rol='responsable',estado='activa',updated_at=now()
    where unidad_id=v_inv.unidad_id and user_id=p_actor_user_id;
  else
    insert into public.membresias_unidad(unidad_id,user_id,rol,estado)
    values(v_inv.unidad_id,p_actor_user_id,'responsable','activa');
  end if;

  insert into public.credenciales_domicilio(
    organizacion_id,unidad_id,pin_hmac,emitido_por
  ) values(v_inv.organizacion_id,v_inv.unidad_id,p_pin_hmac,p_actor_user_id);

  update public.invitaciones_responsable
  set estado='aceptada',aceptada_por=p_actor_user_id,aceptada_at=now()
  where id=v_inv.id;

  insert into public.auditoria(
    organizacion_id,actor_user_id,accion,entidad,entidad_id,detalles
  ) values(v_inv.organizacion_id,p_actor_user_id,'responsable.invitacion_aceptada',
    'invitaciones_responsable',v_inv.id::text,
    jsonb_build_object('unidad_id',v_inv.unidad_id));

  return jsonb_build_object('ok',true,'unidad_id',v_inv.unidad_id,
    'estado','responsable_activo');
end;
$$;

create or replace function public.revocar_invitacion_responsable(
  p_invitacion_id uuid,
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_inv public.invitaciones_responsable%rowtype;
begin
  if p_actor_user_id is null or not exists(select 1 from auth.users where id=p_actor_user_id) then
    raise exception 'Actor no válido';
  end if;
  select * into v_inv from public.invitaciones_responsable
  where id=p_invitacion_id for update;
  if not found or not public._vigiared_puede_administrar_org(v_inv.organizacion_id,p_actor_user_id) then
    raise exception 'No autorizado o invitación no disponible';
  end if;
  if v_inv.estado<>'pendiente' then raise exception 'Invitación no disponible'; end if;
  update public.invitaciones_responsable
  set estado='revocada',revocada_at=now() where id=v_inv.id;
  insert into public.auditoria(
    organizacion_id,actor_user_id,accion,entidad,entidad_id,detalles
  ) values(v_inv.organizacion_id,p_actor_user_id,'responsable.invitacion_revocada',
    'invitaciones_responsable',v_inv.id::text,jsonb_build_object('unidad_id',v_inv.unidad_id));
  return jsonb_build_object('ok',true,'estado','revocada');
end;
$$;

revoke all on function public.crear_domicilio_pendiente(uuid,uuid,text,text,text,text,text,text)
  from public,anon,service_role;
revoke all on function public.crear_invitacion_responsable(uuid,text,text,timestamptz,uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.aceptar_invitacion_responsable(text,uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.revocar_invitacion_responsable(uuid,uuid)
  from public,anon,authenticated,service_role;

grant execute on function public.crear_domicilio_pendiente(uuid,uuid,text,text,text,text,text,text)
  to authenticated;
grant execute on function public.crear_invitacion_responsable(uuid,text,text,timestamptz,uuid)
  to service_role;
grant execute on function public.aceptar_invitacion_responsable(text,uuid,text)
  to service_role;
grant execute on function public.revocar_invitacion_responsable(uuid,uuid)
  to service_role;

comment on table public.invitaciones_responsable is
  'Invitaciones de un solo uso para primer responsable; almacena HMAC, nunca token legible.';
commit;
