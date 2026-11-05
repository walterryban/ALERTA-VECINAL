// VIGIARED — Edge Function para PIN de domicilio
// Variables: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
// VIGIARED_PIN_HMAC_SECRET (secreto aleatorio de al menos 32 bytes).
// La clave privilegiada sólo se usa dentro de esta Edge Function para las RPC
// de escritura de credenciales, que no aceptan llamadas desde authenticated.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
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
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(pin),
  );
  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return response({ error: "Método no permitido" }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return response({ error: "Autenticación requerida" }, 401);
  }

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!url || !anonKey) throw new Error("Configuración de Supabase incompleta");

    const accessToken = authorization.slice("Bearer ".length);
    const supabase = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userResult, error: userError } = await supabase.auth.getUser(accessToken);
    if (userError || !userResult.user) return response({ error: "Sesión inválida" }, 401);

    const body = await req.json();
    const action = body?.action;

    if (action === "crear_manzana") {
      const { data, error } = await supabase.rpc("crear_manzana", {
        p_organizacion_id: body.organizacion_id,
        p_nombre: body.nombre,
      });
      if (error) return response({ error: "No se pudo crear la manzana" }, 400);
      return response(data);
    }

    if (action === "crear_domicilio") {
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
        p_nombre: body.nombre,
        p_tipo: body.tipo,
        p_direccion: body.direccion ?? null,
        p_localidad: body.localidad ?? null,
        p_provincia: body.provincia ?? null,
        p_codigo_postal: body.codigo_postal ?? null,
        p_responsable_user_id: body.responsable_user_id,
        p_pin_hmac: digest,
        p_actor_user_id: userResult.user.id,
      });
      if (error) return response({ error: "No se pudo registrar el domicilio" }, 400);
      // Entrega única del PIN. No registrar esta respuesta en logs.
      return response({ ...data, pin_entrega_unica: pin });
    }

    if (action === "rotar_pin") {
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
      if (error) return response({ error: "No se pudo renovar el PIN" }, 400);
      return response({ ...data, pin_entrega_unica: pin });
    }

    if (action === "solicitar_ingreso") {
      const user = userResult.user;
      if (!user.phone || !user.phone_confirmed_at) {
        return response({
          error: "Para solicitar el ingreso vecinal se requiere un teléfono verificado.",
          codigo: "TELEFONO_NO_VERIFICADO",
        }, 403);
      }
      const pin = String(body.pin ?? "").trim();
      if (!/^\d{10}$/.test(pin)) {
        return response({ ok: false, mensaje: "No se pudo validar el ingreso" }, 400);
      }
      const digest = await pinHmac(pin);
      const { data, error } = await supabase.rpc("solicitar_ingreso_con_pin", {
        p_manzana_public_id: body.manzana_public_id,
        p_pin_hmac: digest,
        p_mensaje: body.mensaje ?? null,
      });
      if (error) return response({ error: "No se pudo procesar la solicitud" }, 400);
      return response(data);
    }

    return response({ error: "Acción no reconocida" }, 400);
  } catch (_error) {
    // No devolver secretos, PIN, token ni detalles internos al cliente.
    return response({ error: "No se pudo completar la operación" }, 500);
  }
});
