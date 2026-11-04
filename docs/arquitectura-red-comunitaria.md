# Alerta Vecinal Pro — Arquitectura de la Red Comunitaria

Estado: especificación funcional para implementación en la rama `integracion-segura-2026-11-04`.
Este documento no modifica la base de datos ni habilita funciones en producción.

## 1. Jerarquía territorial y de acceso

`manzana -> establecimiento -> unidad_habitacional -> integrante`

- **Manzana:** ámbito de participación y difusión de avisos comunitarios.
- **Establecimiento:** propiedad o predio registrado en una dirección. Tipos: vivienda única, vivienda con departamentos, edificio residencial, comercio, galería/conjunto comercial, pensión/residencia/hostel, complejo habitacional y uso mixto.
- **Unidad habitacional/funcional:** casa, piso/departamento, habitación, local o unidad de un complejo. Puede participar de forma independiente.
- **Integrante:** persona autorizada para una unidad. No hay tope fijo de integrantes; cada persona tiene credencial individual revocable.

La dirección postal no es una credencial ni un identificador único. Ejemplo: “San Martín 142” es el establecimiento; “Piso 3, Departamento C” es una unidad.

## 2. Comercios y uso mixto

Un establecimiento puede combinar usos residenciales y comerciales. Cada local, vivienda o unidad se registra por separado. Los titulares/responsables pueden solicitar altas y bajas; el operador municipal autorizado aprueba, suspende o revoca. Los empleados reciben accesos individuales y revocables.

Perfiles funcionales previstos: residente, titular/responsable de unidad, comerciante, empleado, encargado y operador municipal. Los perfiles no otorgan permisos administrativos automáticamente: los permisos se asignan por rol y alcance.

## 3. Credenciales y privacidad

- El QR público abre la aplicación; no contiene PIN, datos personales ni credenciales permanentes.
- Cada integrante recibe una credencial individual entregada de forma privada.
- Nunca almacenar PIN en texto plano; almacenar hash seguro, limitar intentos, aplicar demora/bloqueo y permitir revocación.
- No confiar en dirección, manzana, identidad o teléfono enviados desde el navegador: el servidor resuelve la identidad y la unidad desde la credencial validada.
- Para menores, el alta debe ser gestionada por madre/padre/tutor; no exigir teléfono propio.
- La alerta comunitaria contiene solo información mínima (tipo de evento y zona/manzana). Nunca divulgar nombre, teléfono, dirección exacta, ficha médica o identidad del emisor.
- El COM autenticado puede ver los datos estrictamente necesarios para responder, con permisos por rol, auditoría y retención definida.
- Un dispositivo asociado es una medida adicional, no prueba suficiente de identidad.

## 4. Alertas y notificaciones

- El servidor valida credencial y determina unidad, establecimiento y manzana.
- El COM recibe la alerta operativa con ubicación y datos autorizados.
- Participantes activos de la misma manzana pueden recibir un aviso comunitario anónimo sujeto a consentimiento y preferencias.
- Realtime en una página abierta no equivale a notificación cuando la app está cerrada. Para segundo plano se requiere Web Push/FCM, suscripción por dispositivo, revocación y pruebas.
- No prometer cifrado de extremo a extremo hasta implementarlo y auditarlo; HTTPS/TLS protege el transporte, no equivale a E2E.

## 5. Modelo de datos propuesto

- `establecimientos`: manzana_id, dirección, tipo, estado, responsable y marcas de auditoría.
- `unidades`: establecimiento_id, tipo, identificador visible, piso, estado.
- `vecinos`: mantener la tabla existente como personas; agregar unidad_id y tipo_integrante solo tras verificar constraints y compatibilidad. Una persona corresponde a una credencial individual.
- `alertas`: completar vecino_id y unidad_id/establecimiento_id mediante resolución en servidor; no aceptar esos vínculos desde el cliente.
- `credenciales` (recomendado): integrante_id, hash, estado, intentos, expiración, revocación y auditoría; no reutilizar el PIN compartido de manzana.

La tabla `manzanas` existente usa id identity bigint; las nuevas relaciones deben respetar ese tipo. No borrar ni renombrar datos existentes.

## 6. Secuencia segura de implementación

1. Confirmar esquema real, constraints, índices, RLS y definiciones completas de RPC en Supabase.
2. Preparar migración aditiva y reversible: tablas nuevas, claves foráneas e índices; sin borrar columnas ni políticas actuales.
3. Crear RPC de administración con autorización explícita por rol y RPC de acceso individual con límites anti-fuerza-bruta.
4. Adaptar el COM para gestionar establecimientos, unidades, integrantes y revocaciones, conservando alertas y gestión actual de manzanas.
5. Adaptar terminal vecinal y QR público sin secretos en URL.
6. Incorporar avisos anónimos por manzana y luego notificaciones push.
7. Probar en preview con datos ficticios y usuarios de prueba. Solo promover a producción con aprobación explícita y plan de reversión.

## 7. Criterios de aceptación

- Una manzana contiene muchos establecimientos.
- Un establecimiento admite muchas unidades de tipos y usos distintos.
- Cada unidad puede participar o no independientemente.
- Una unidad admite integrantes sin límite fijo, cada uno con credencial individual.
- La baja de un integrante no afecta a los demás.
- Un comercio puede registrar titular y empleados.
- Una alerta identifica exactamente la unidad ante el COM.
- El aviso comunitario no filtra identidad ni datos sensibles.
- Ningún PIN aparece en QR, URL, HTML público o logs.
- Los datos existentes y el acceso municipal actual siguen funcionando.

## 8. Límites de este entregable

Este documento define la arquitectura. No ejecuta SQL, no cambia Supabase, no modifica el dominio de producción y no afirma que la difusión vecinal o las notificaciones push estén ya operativas.


## 9. Avance de interfaz en la rama de integración (04-11-2026)

Cambios implementados en código de la rama de prueba, sin modificar producción ni Supabase:

- La página inicial ofrece dos accesos diferenciados: terminal ciudadana y consola municipal.
- La PWA abre ahora la página inicial unificada.
- La terminal ciudadana recibió una actualización visual y conserva las RPC actuales.
- La consola municipal incorpora indicadores de alertas por estado, búsqueda y filtro.
- El sonido de alertas requiere activación manual del operador y permite probar la sirena desde el botón de activación.
- Los QR nuevos de la consola y del cartel público abren la terminal con la manzana preseleccionada, sin incluir el PIN.
- La terminal ignora cualquier PIN recibido por parámetros de URL. Los carteles antiguos que imprimían PIN deben retirarse y reemplazarse.
- Se agregó un borrador de endurecimiento RLS para las tablas `vecinos` y `vendedores`; todavía no fue ejecutado.

## 10. Funciones que todavía no están implementadas

No se debe presentar como disponible hasta completar esquema, RPC, interfaz y pruebas:

- Credenciales individuales revocables.
- Alta y aprobación de integrantes por unidad.
- Gestión de establecimientos, departamentos, habitaciones y locales.
- Red de Comercios Protegidos y gestión de empleados.
- Difusión de alertas anónimas a vecinos de la misma manzana.
- Notificaciones push cuando la aplicación está cerrada.

La vista previa de Vercel usa la configuración actual de Supabase. No enviar alertas de prueba ni cambiar estados desde la vista previa, porque esas acciones pueden modificar datos reales.
