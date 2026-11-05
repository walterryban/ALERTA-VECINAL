// VIGIARED — Edge Function para PIN de domicilio
// Variables de entorno (sólo en Supabase Edge Functions):
// SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
// VIGIARED_PIN_HMAC_SECRET (secreto aleatorio de al menos 32 bytes),
// VIGIARED_ALLOWED_ORIGINS (lista separada por comas de orígenes HTTPS exactos).
// Nunca colocar secretos en el cliente, repositorio, QR, URL ni auditoría.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const baseHeaders = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
  "Cache-Control": "no-store, max-age=0",
  "Pragma": "no-cache",
};

function corsFor(req: Request): HeadersInit | null {
  const origin = req.headers.get("Origin");
  if (!origin) return baseHeaders; // llamadas server-to-server
  const configured = (Deno.env.get("VIGIARED_ALLOWED_ORIGINS") ?? "")
    .split(",").map((value) => value.trim()).filter(Boolean);
  if (configured.length === 0 || !configured.includes(origin)) return null;
  return { ...baseHeaders, "Access-Control-Allow-Origin": origin };
}

function response(body: unknown, status = 200, headers: HeadersInit = baseHeaders) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, "Content-Type": "application/json; charset=utf-8" },
  });
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function boundedText(value: unknown, max: number): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") return null;
  const clean = value.trim();
  return clean.length <= max ? clean : null;
}

function randomPin(): string {
  // Muestreo por rechazo para evitar sesgo de módulo.
  let pin = "";
  const bytes = new Uint8Array(32);
  while (pin.length < 10) {
    crypto.getRandomValues(bytes);
    for (const byte of bytes) {
      if (byte < 250) pin += String(byte % 10);
      if (pin.length === 10) break;
    }
  }
  return pin;
}

async function pinHmac(pin: string): Promise<string> {
  const secret = Deno.env.get("VIGIARED_PIN_HMAC_SECRET");
  if (!secret || new TextEncoder().encode(secret).length < 32) {
    throw new Error("Configuración segura del PIN incompleta");
  }
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(pin));
  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  const corsHeaders = corsFor(req);
  if (!corsHeaders) return response({ error: "Origen no autorizado" }, 403, baseHeaders);

  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method !== "POST") return response({ error: "Método no permitido" }, 405, corsHeaders);

  const authorization = req.headers.get("Authorization");
  if (!authorization || !/^Bearer\s+\S+$/i.test(authorization)) {
    return response({ error: "Autenticación requerida" }, 401, corsHeaders);
  }
  if (!(req.headers.get("Content-Type") ?? "").toLowerCase().startsWith("application/json")) {
    return response({ error: "Formato de solicitud no válido" }, 415, corsHeaders);
  }

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!url || !anonKey) throw new Error("Configuración de Supabase incompleta");

    const rawBody = await req.text();
    if (rawBody.length > 16_384) return response({ error: "Solicitud demasiado extensa" }, 413, corsHeaders);
    let body: Record<string, unknown>;
    try {
      const parsed: unknown = JSON.parse(rawBody);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        return response({ error: "Solicitud no válida" }, 400, corsHeaders);
      }
      body = parsed as Record<string, unknown>;
    } catch {
      return response({ error: "JSON no válido" }, 400, corsHeaders);
    }

    const accessToken = authorization.replace(/^Bearer\s+/i, "");
    const supabase = createClient(url, anonKey, {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userResult, error: userError } = await supabase.auth.getUser(accessToken);
    if (userError || !userResult.user) return response({ error: "Sesión inválida" }, 401, corsHeaders);

    const action = body.action;

    if (action === "crear_manzana") {
      if (!isUuid(body.organizacion_id)) return response({ error: "Datos incompletos" }, 400, corsHeaders);
      const nombre = boundedText(body.nombre, 120);
      if (!nombre || nombre.length < 2) return response({ error: "Datos incompletos" }, 400, corsHeaders);
      const { data, error } = await supabase.rpc("crear_manzana", {
        p_organizacion_id: body.organizacion_id,
        p_nombre: nombre,
      });
      if (error) return response({ error: "No se pudo crear la manzana" }, 400, corsHeaders);
      return response(data, 200, corsHeaders);
    }

    if (action === "crear_domicilio") {
      const requiredUuids = [body.organizacion_id, body.manzana_id, body.responsable_user_id];
      if (!requiredUuids.every(isUuid)) return response({ error: "Datos incompletos" }, 400, corsHeaders);
      const nombre = boundedText(body.nombre, 150);
      const tipo = boundedText(body.tipo, 32);
      if (!nombre || nombre.length < 1 || !tipo) return response({ error: "Datos incompletos" }, 400, corsHeaders);
      const direccion = boundedText(body.direccion, 200);
      const localidad = boundedText(body.localidad, 120);
      const provincia = boundedText(body.provincia, 120);
      const codigoPostal = boundedText(body.codigo_postal, 20);
      if ([body.direccion, body.localidad, body.provincia, body.codigo_postal].some((v, i) =>
        v !== undefined && v !== null &&
        [direccion, localidad, provincia, codigoPostal][i] === null
      )) return response({ error: "Datos de domicilio no válidos" }, 400, corsHeaders);

      const pin = randomPin();
      const digest = await pinHmac(pin);
      const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      if (!serviceRoleKey) throw new Error("Servicio privilegiado no configurado");
      const privileged = createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await privileged.rpc("crear_domicilio_con_responsable", {
        p_organizacion_id: body.organizacion_id,
        p_manzana_id: body.manzana_id,
        p_nombre: nombre,
        p_tipo: tipo,
        p_direccion: direccion,
        p_localidad: localidad,
        p_provincia: provincia,
        p_codigo_postal: codigoPostal,
        p_responsable_user_id: body.responsable_user_id,
        p_pin_hmac: digest,
        p_actor_user_id: userResult.user.id,
      });
      if (error) return response({ error: "No se pudo registrar el domicilio" }, 400, corsHeaders);
      // Entrega única del PIN. No registrar esta respuesta en logs ni almacenarla en caché.
      return response({ ...data, pin_entrega_unica: pin }, 200, corsHeaders);
    }

    if (action === "rotar_pin") {
      if (!isUuid(body.unidad_id)) return response({ error: "Datos incompletos" }, 400, corsHeaders);
      const pin = randomPin();
      const digest = await pinHmac(pin);
      const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      if (!serviceRoleKey) throw new Error("Servicio privilegiado no configurado");
      const privileged = createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await privileged.rpc("rotar_pin_domicilio", {
        p_unidad_id: body.unidad_id,
        p_pin_hmac_nuevo: digest,
        p_actor_user_id: userResult.user.id,
      });
      if (error) return response({ error: "No se pudo renovar el PIN" }, 400, corsHeaders);
      return response({ ...data, pin_entrega_unica: pin }, 200, corsHeaders);
    }

    if (action === "solicitar_ingreso") {
      const user = userResult.user;
      if (!user.phone || !user.phone_confirmed_at) {
        return response({
          error: "Para solicitar el ingreso vecinal se requiere un teléfono verificado.",
          codigo: "TELEFONO_NO_VERIFICADO",
        }, 403, corsHeaders);
      }
      const pin = typeof body.pin === "string" ? body.pin.trim() : "";
      if (!/^\d{10}$/.test(pin) || !isUuid(body.manzana_public_id)) {
        return response({ ok: false, mensaje: "No se pudo validar el ingreso" }, 400, corsHeaders);
      }
      const mensaje = boundedText(body.mensaje, 1000);
      if (body.mensaje !== undefined && body.mensaje !== null && mensaje === null) {
        return response({ error: "Mensaje no válido" }, 400, corsHeaders);
      }
      const digest = await pinHmac(pin);
      const { data, error } = await supabase.rpc("solicitar_ingreso_con_pin", {
        p_manzana_public_id: body.manzana_public_id,
        p_pin_hmac: digest,
        p_mensaje: mensaje,
      });
      if (error) return response({ error: "No se pudo procesar la solicitud" }, 400, corsHeaders);
      return response(data, 200, corsHeaders);
    }

    return response({ error: "Acción no reconocida" }, 400, corsHeaders);
  } catch (_error) {
    // No devolver secretos, PIN, token ni detalles internos al cliente.
    return response({ error: "No se pudo completar la operación" }, 500, corsHeaders);
  }
});
