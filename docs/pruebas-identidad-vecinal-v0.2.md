# Plan de pruebas — identidad vecinal VIGIARED v0.2

**Estado:** casos definidos; NO ejecutados.  
**Entorno requerido:** proyecto Supabase desechable, distinto del proyecto compartido por Preview y Producción.  
**Datos:** exclusivamente cuentas, establecimientos y unidades sintéticas.

## Reglas de seguridad para la ejecución

- No ejecutar en el proyecto Supabase actual ni desde el deployment Preview.
- No usar vecinos, domicilios, teléfonos ni alertas reales.
- No enviar invitaciones por correo/SMS a personas reales.
- Crear cuentas de prueba con direcciones controladas por el equipo.
- Guardar las claves privilegiadas solo en entorno servidor; nunca en navegador, repositorio o logs.
- No ejecutar la migración hasta revisar la migración base de `establecimientos` y `unidades`.
- Hacer backup del proyecto desechable antes de cada corrida destructiva.
- Registrar versión del SQL, fecha, entorno y resultado de cada caso.

## Fixture sintético requerido

Crear en el entorno aislado:

- Dos establecimientos activos: E-A y E-B.
- Tres unidades activas: U-A1 y U-A2 en E-A; U-B1 en E-B.
- Una unidad suspendida U-S.
- Cuentas verificadas: titular-A1, titular-A2, persona-X, persona-Y y titular-B1.
- Cuenta no verificada: persona-pendiente.
- Membresía titular activa de titular-A1 en U-A1, titular-A2 en U-A2 y titular-B1 en U-B1.
- Perfil de persona-X con membresía activa en U-A2 y pendiente de solicitud en U-A1, según el caso.
- No importar filas de `public.vecinos`.

Los identificadores deben generarse en el entorno aislado y no copiarse a producción.

## Casos funcionales

| ID | Caso | Resultado esperado |
|---|---|---|
| ID-01 | Provisionar perfil para Auth verificado con service role | Crea perfil y auditoría |
| ID-02 | Repetir provisionamiento de misma cuenta | Devuelve el mismo perfil; no duplica |
| ID-03 | Provisionar cuenta no verificada | Rechazado |
| ID-04 | Provisionar desde authenticated/anon | Permiso denegado |
| ID-05 | Inicializar titular para unidad activa con referencia de verificación | Membresía titular activa |
| ID-06 | Inicializar segundo titular activo en misma unidad | Rechazado |
| ID-07 | Inicializar titular desde navegador | Permiso denegado |
| ID-08 | Emitir invitación como titular de su unidad | Token aleatorio devuelto una vez; DB solo hash |
| ID-09 | Emitir invitación como integrante/no miembro | Rechazado |
| ID-10 | Canjear token válido con perfil activo | Solicitud pendiente, nunca membresía activa |
| ID-11 | Canjear token vencido, revocado o usado | Rechazado |
| ID-12 | Canjear invitación para unidad/establecimiento suspendido | Rechazado |
| ID-13 | Canjear token con cuenta sin perfil o perfil suspendido | Rechazado |
| ID-14 | Aprobar como titular de la misma unidad | Membresía integrante activa |
| ID-15 | Aprobar como titular de otra unidad | Rechazado |
| ID-16 | Aprobar solicitud propia | Rechazado |
| ID-17 | Aprobar con perfil solicitante suspendido/no verificado | Rechazado |
| ID-18 | Rechazar como titular de la misma unidad | Solicitud rechazada y auditada |
| ID-19 | Rechazar con perfil del titular suspendido | Rechazado |
| ID-20 | Revocar como integrante su propia membresía | Revoca solo esa membresía |
| ID-21 | Revocar como titular la membresía de otro integrante | Revoca solo esa membresía |
| ID-22 | Revocar al último titular | Rechazado |
| ID-23 | Contexto de cuenta con membresías en U-A1 y U-A2 | Devuelve solo ambas unidades propias |
| ID-24 | Contexto de cuenta sin membresías activas | Cero filas |
| ID-25 | Leer tablas directamente como anon/authenticated | Denegado |
| ID-26 | Cuenta suspendida intenta emitir/canjear/aprobar | Rechazado |
| ID-27 | Revocar membresía en U-A1 | La membresía de U-A2 sigue activa |
| ID-28 | Buscar asociación automática con filas legadas en vecinos | Ninguna asociación ni permiso |

## Casos de concurrencia obligatorios

1. **Canje doble:** dos sesiones intentan canjear el mismo token al mismo tiempo. Solo una debe obtener solicitud; la otra debe fallar sin duplicar.
2. **Dos invitaciones al mismo perfil/unidad:** ambas se canjean en paralelo. La restricción parcial debe permitir una sola solicitud pendiente.
3. **Aprobación doble:** dos titulares intentan aprobar la misma solicitud. Solo una transición debe registrarse; no debe duplicar membresía ni auditoría.
4. **Bootstrap doble:** dos operaciones intentan inicializar titular para la misma unidad. Debe quedar un solo titular inicial.
5. **Último titular:** dos operaciones concurrentes intentan revocar los dos titulares de una unidad. Nunca debe quedar la unidad sin titular activo.
6. **Revocación/canje:** revocar invitación mientras se canjea. El resultado debe ser serializable en la práctica: canje exitoso o revocación exitosa, nunca ambos incompatiblemente.
7. **Suspensión durante operación:** suspender unidad/establecimiento mientras se canjea o aprueba; confirmar que la operación no autorice acceso a unidad suspendida.

Para cada prueba concurrente usar dos conexiones PostgreSQL reales, barreras sincronizadas y registrar los estados antes/después. No simular concurrencia con llamadas secuenciales.

## Pruebas de privilegios y SECURITY DEFINER

- Inspeccionar `pg_proc.prosecdef`, `proconfig`, propietario y ACL de cada función.
- Confirmar `search_path=""` en todas las funciones SECURITY DEFINER.
- Confirmar que el propietario sea un rol confiable y que los roles de aplicación no puedan alterar funciones ni objetos referenciados.
- Confirmar EXECUTE de provisionamiento/bootstrap solo para service_role.
- Confirmar EXECUTE de RPC de usuario solo para authenticated.
- Confirmar que PUBLIC y anon no tengan EXECUTE.
- Confirmar que no haya grants heredados que permitan SELECT/INSERT/UPDATE/DELETE en tablas sensibles.
- Confirmar que RLS permanezca habilitado y no existan políticas amplias inesperadas.
- Probar con JWT reales de roles anon/authenticated, no solo con SQL Editor como postgres.

## Hallazgos que deben resolverse antes de habilitar usuarios

- Implementar una bandeja segura de solicitudes pendientes para titulares; no abrir SELECT directo.
- Implementar cancelación de solicitud y transferencia de titularidad.
- Agregar rate limit contra intentos de token inválido; el límite actual de invitaciones por auditoría no limita canjes fallidos.
- Evaluar revocación de sesiones/dispositivos y recuperación de cuenta.
- Revisar si la identidad verificada debe requerir email, teléfono o ambos según riesgo.
- Revisar tutoría/consentimiento para menores y política de datos personales.
- Confirmar que el titular no pueda alterar su propio rol mediante rutas distintas al bootstrap controlado.
- Revisar idempotencia y auditoría ante reintentos de red.

## Evidencia por caso

Completar al ejecutar:

| ID | Resultado (PASA/FALLA/BLOQUEADO) | Evidencia/log | Incidencia |
|---|---|---|---|
| ID-01 a ID-28 | Pendiente | — | — |
| CONC-01 a CONC-07 | Pendiente | — | — |
| SEC-01 a SEC-08 | Pendiente | — | — |

## Criterio de aprobación

No se conecta la terminal ni se autoriza producción hasta que:

1. Todos los casos ID-01 a ID-28 pasen.
2. Todas las pruebas CONC-01 a CONC-07 pasen.
3. Todas las pruebas SEC-01 a SEC-08 pasen.
4. No haya hallazgos críticos/altos abiertos.
5. La migración se haya compilado y ensayado desde cero en un proyecto aislado.
6. Exista un informe firmado con evidencia y decisión de aprobación.
