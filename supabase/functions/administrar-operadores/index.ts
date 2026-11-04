// Supabase Edge Function: administrar-operadores
// Deploy only after RBAC v0.1 + v0.2 migrations have been reviewed and
// applied in an isolated Supabase project. Never expose SERVICE_ROLE_KEY.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": Deno.env.get("APP_ORIGIN") ?? "https://appvecinaldeseguridad.vercel.app",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
const allowedRoles = new Set([
  "administrador_municipal", "supervisor_municipal",
  "operador_municipal", "auditor_municipal",
]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Sesión requerida" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: "Configuración del servidor incompleta" }, 500);

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: authData, error: authError } = await caller.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "Sesión inválida" }, 401);
  const actorId = authData.user.id;

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "JSON inválido" }, 400); }
  const action = String(body.action ?? "");

  const { data: context, error: contextError } = await caller.rpc("obtener_contexto_administrativo");
  if (contextError || !context) {
    return json({ error: "No se pudo verificar el perfil administrativo. Compruebe las migraciones RBAC." }, 403);
  }
  const organizations = Array.isArray(context.organizaciones) ? context.organizaciones : [];

  if (action === "create_organization") {
    if (context.es_propietario !== true) return json({ error: "Solo el propietario de la plataforma puede crear organizaciones." }, 403);
    const name = String(body.name ?? "").trim();
    const code = String(body.code ?? "").trim().toLowerCase();
    if (name.length < 3 || name.length > 120) return json({ error: "El nombre debe tener entre 3 y 120 caracteres." }, 400);
    if (!/^[a-z0-9][a-z0-9-]{1,39}$/.test(code)) return json({ error: "El código debe tener entre 2 y 40 caracteres: letras minúsculas, números y guiones." }, 400);
    const { data: created, error: createError } = await admin.from("organizaciones_municipales")
      .insert({ nombre: name, codigo: code, estado: "activa" })
      .select("id,nombre,codigo,estado").single();
    if (createError || !created) return json({ error: createError?.code === "23505" ? "Ese código de organización ya existe." : "No se pudo crear la organización." }, 409);
    const { error: auditError } = await admin.from("auditoria_administrativa").insert({
      organizacion_id: created.id, actor_auth_user_id: actorId,
      accion: "organizacion_creada", detalle: { nombre: name, codigo: code },
    });
    return json({ ok: true, organization: created, warning: auditError ? "Organización creada; falló el asiento de auditoría y requiere revisión." : undefined });
  }

  const organizationId = String(body.organization_id ?? "");
  if (!organizationId) return json({ error: "Falta organization_id" }, 400);
  const organization = organizations.find((item: Record<string, unknown>) => item.id === organizationId);
  if (!organization || organization.estado !== "activa") {
    return json({ error: "No tiene acceso a esa organización o no está activa." }, 403);
  }

  if (action === "list") {
    if (context.es_propietario !== true && organization.rol !== "administrador_municipal") {
      return json({ error: "Solo el administrador municipal puede consultar la gestión de operadores." }, 403);
    }
    const { data, error } = await admin.from("membresias_municipales")
      .select("id, organizacion_id, auth_user_id, email, rol, estado, creada_at, actualizada_at")
      .eq("organizacion_id", organizationId)
      .order("creada_at", { ascending: false });
    if (error) return json({ error: "No se pudo consultar el personal autorizado." }, 500);
    return json({ organization, memberships: data ?? [] });
  }

  if (action === "invite") {
    const email = String(body.email ?? "").trim().toLowerCase();
    const role = String(body.role ?? "");
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "Correo electrónico inválido." }, 400);
    if (!allowedRoles.has(role)) return json({ error: "Rol no permitido." }, 400);
    const { data: permission, error: permissionError } = await caller.rpc("puede_gestionar_membresias", {
      p_organizacion_id: organizationId, p_rol_objetivo: role,
    });
    if (permissionError || permission !== true) return json({ error: "No tiene permisos para asignar ese rol." }, 403);

    const redirectTo = Deno.env.get("AUTH_REDIRECT_URL");
    const { data: inviteData, error: inviteError } = await admin.auth.admin.inviteUserByEmail(
      email, redirectTo ? { redirectTo } : undefined,
    );
    if (inviteError || !inviteData.user) {
      return json({
        error: inviteError?.message ?? "No se pudo crear la invitación.",
        hint: "Si la persona ya tiene cuenta, debe incorporarse mediante un flujo seguro de vinculación de cuenta existente.",
      }, 409);
    }

    const targetId = inviteData.user.id;
    const { error: membershipError } = await admin.from("membresias_municipales").upsert({
      organizacion_id: organizationId, auth_user_id: targetId, email, rol: role,
      estado: "pendiente", creada_por: actorId, actualizada_at: new Date().toISOString(),
    }, { onConflict: "organizacion_id,auth_user_id" });
    if (membershipError) {
      return json({ error: "Invitación creada, pero no se registró la membresía. Requiere revisión; no reenvíe invitaciones repetidas." }, 500);
    }

    const { error: auditError } = await admin.from("auditoria_administrativa").insert({
      organizacion_id: organizationId, actor_auth_user_id: actorId,
      objetivo_auth_user_id: targetId, accion: "invitacion_enviada",
      detalle: { rol: role, correo: email },
    });
    if (auditError) return json({ ok: true, warning: "Invitación registrada; falló el asiento de auditoría y requiere revisión." });
    return json({ ok: true, message: "Invitación enviada. La membresía queda pendiente hasta confirmar el correo y activar el acceso.", user_id: targetId });
  }

  if (action === "activate" || action === "revoke" || action === "change_role") {
    const targetId = String(body.user_id ?? "");
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(targetId)) {
      return json({ error: "Identificador de usuario inválido." }, 400);
    }
    const { data: protectedOwner, error: ownerError } = await admin.from("propietarios_plataforma")
      .select("auth_user_id").eq("auth_user_id", targetId).eq("activo", true).maybeSingle();
    if (ownerError) return json({ error: "No se pudo verificar la cuenta objetivo." }, 500);
    if (protectedOwner) return json({ error: "La cuenta propietaria de la plataforma está protegida." }, 403);

    const { data: target, error: targetError } = await admin.from("membresias_municipales")
      .select("id, rol, estado").eq("organizacion_id", organizationId)
      .eq("auth_user_id", targetId).maybeSingle();
    if (targetError || !target) return json({ error: "No se encontró esa membresía." }, 404);

    if (action === "activate") {
      const { data: authUser, error: authUserError } = await admin.auth.admin.getUserById(targetId);
      if (authUserError || !authUser.user?.email_confirmed_at) {
        return json({ error: "La persona todavía no confirmó su correo. No se puede activar el acceso." }, 409);
      }
      const { data: permission, error } = await caller.rpc("puede_gestionar_membresias", {
        p_organizacion_id: organizationId, p_rol_objetivo: target.rol,
      });
      if (error || permission !== true) return json({ error: "No puede activar esa membresía." }, 403);
    } else if (action === "change_role") {
      const role = String(body.role ?? "");
      if (!allowedRoles.has(role)) return json({ error: "Rol no permitido." }, 400);
      const { data: permission, error } = await caller.rpc("puede_gestionar_membresias", {
        p_organizacion_id: organizationId, p_rol_objetivo: role,
      });
      if (error || permission !== true) return json({ error: "No puede asignar ese rol." }, 403);
    } else {
      const { data: permission, error } = await caller.rpc("puede_gestionar_membresias", {
        p_organizacion_id: organizationId, p_rol_objetivo: target.rol,
      });
      if (error || permission !== true) return json({ error: "No puede revocar esa membresía." }, 403);
    }

    const newRole = String(body.role ?? "");
    const update = action === "activate"
      ? { estado: "activa", actualizada_at: new Date().toISOString() }
      : action === "revoke"
        ? { estado: "revocada", actualizada_at: new Date().toISOString() }
        : { rol: newRole, actualizada_at: new Date().toISOString() };
    const { error: updateError } = await admin.from("membresias_municipales")
      .update(update).eq("id", target.id);
    if (updateError) return json({ error: "No se pudo actualizar la membresía." }, 500);

    const auditAction = action === "activate" ? "membresia_activada"
      : action === "revoke" ? "membresia_revocada" : "rol_modificado";
    const { error: auditError } = await admin.from("auditoria_administrativa").insert({
      organizacion_id: organizationId, actor_auth_user_id: actorId,
      objetivo_auth_user_id: targetId, accion: auditAction,
      detalle: action === "change_role"
        ? { rol_anterior: target.rol, rol_nuevo: newRole }
        : { rol: target.rol },
    });
    if (auditError) return json({ ok: true, warning: "Cambio aplicado, pero falló el asiento de auditoría y requiere revisión." });
    return json({ ok: true, message: action === "activate" ? "Acceso activado." : action === "revoke" ? "Acceso revocado." : "Rol actualizado." });
  }

  return json({ error: "Acción no reconocida." }, 400);
});
