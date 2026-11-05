# VIGIARED — Diseño funcional base v1.0

**Estado:** base funcional aprobada para orientar el desarrollo; sujeta a reformas evaluadas.  
**Rama:** integracion-segura-2026-11-04  
**Presupuesto inicial:** cero pesos. No contratar servicios ni habilitar cargos sin autorización expresa.  
**Producción:** no modificar ni desplegar hasta completar revisión, pruebas y aprobación.

## 1. Principios del producto

VIGIARED es una plataforma independiente de prevención y respuesta comunitaria. Debe ser segura, inclusiva, sencilla para adultos mayores y adaptable a las necesidades de cada comunidad.

La versión 1.0 constituye una base estable, no un diseño inmutable. Las solicitudes de vecinos, operadores y organizaciones se registrarán, evaluarán y priorizarán. Las reformas compatibles podrán incorporarse mediante versiones posteriores, sin romper la seguridad ni la continuidad del servicio.

## 2. Incorporación vecinal: QR de manzana + PIN por domicilio

- Cada manzana tiene un QR que identifica la comunidad/manzana y abre el flujo de incorporación.
- Cada domicilio registrado recibe un PIN único generado automáticamente por VIGIARED.
- El PIN pertenece a la vivienda; no es un PIN general de la manzana ni un PIN individual por persona.
- El QR no contiene el PIN ni datos personales y no concede acceso por sí solo.
- El vecino escanea el QR e introduce el PIN de su vivienda.
- El backend valida la credencial y crea una solicitud de incorporación.
- El primer responsable se aprueba mediante un procedimiento controlado y auditable.
- Los integrantes adicionales tienen cuentas individuales y requieren autorización según las reglas del domicilio.
- Revocar o rotar el PIN impide nuevas incorporaciones con el PIN anterior, pero no elimina membresías ya aprobadas.
- El PIN nunca reemplaza la autenticación individual ni autoriza a consultar alertas o datos privados antes de aprobar la membresía.

## 3. Teléfono e identidad

- Cada vecino debe disponer de un teléfono inteligente compatible con cámara y conexión a Internet para el uso normal de la aplicación.
- El correo electrónico es opcional; no se obliga a utilizar el correo de familiares.
- Cada persona mantiene una cuenta individual. No se comparten cuentas ni se fusionan automáticamente identidades.
- La verificación real del teléfono debe resolverse antes de declarar el número como verificado.
- SMS y WhatsApp se evaluarán como canales distintos. No se presupone gratuidad de mensajes salientes ni se habilitan proveedores pagos sin autorización.
- Mientras no exista un mecanismo seguro y sostenible a costo cero, el alta real por teléfono queda como requisito técnico pendiente; los números de prueba solo sirven para desarrollo.

## 4. Accesibilidad e inclusión

Accesibilidad desde el inicio: tipografía ampliable, contraste suficiente, controles grandes, etiquetas compatibles con lectores de pantalla, navegación por teclado, instrucciones claras y alertas no dependientes exclusivamente del color o sonido. Se contemplan alternativas visuales, sonoras y vibratorias cuando el dispositivo las admita, además de asistencia por voz como opción complementaria. No se exigirán diagnósticos médicos ni datos de salud innecesarios.

## 5. Organización y permisos

- Propietario de plataforma: supervisión global.
- Administrador de organización: administra exclusivamente su organización.
- Supervisor, operador y auditor: permisos acotados a su función.
- Responsable e integrantes de domicilio: permisos limitados a su unidad y membresía.
- Ninguna organización puede modificar la configuración global ni acceder a otras organizaciones.

## 6. Módulos funcionales

1. Identidad, acceso y recuperación.
2. Organizaciones y administración.
3. Comunidades, manzanas y domicilios.
4. Credenciales QR/PIN por domicilio.
5. Solicitudes y membresías individuales.
6. Alertas vecinales y distribución a integrantes autorizados.
7. Centro de Monitoreo y gestión de alertas.
8. Auditoría, privacidad y seguridad.
9. Preferencias de accesibilidad.

## 7. Política de cambios y reformas

Las solicitudes de reforma se registrarán con: necesidad, solicitante o grupo solicitante, beneficio esperado, impacto en accesibilidad, privacidad, seguridad, costos y compatibilidad.

Clasificación:
- **Mejora menor:** textos, ayudas, presentación y ajustes que no cambian permisos ni datos.
- **Mejora funcional:** nuevas opciones o flujos; requiere diseño, pruebas y versión.
- **Cambio crítico:** autenticación, autorización, PIN, datos personales, alertas o aislamiento entre organizaciones; requiere revisión de seguridad, pruebas específicas y aprobación del propietario de plataforma.

No se implementarán cambios que expongan datos, debiliten autenticación o creen costos sin aprobación. Cada reforma tendrá registro de versión, pruebas y posibilidad de reversión.

## 8. Reglas técnicas y de seguridad

- PIN generado en backend con aleatoriedad criptográfica.
- No almacenar PIN de baja entropía con SHA-256 simple; evaluar HMAC con secreto protegido o esquema apropiado, límites de intentos y protección contra fuerza bruta.
- Nunca incluir PIN en URL, QR, logs, auditoría ni analítica.
- Validación en backend, respuestas que no permitan enumerar domicilios y rotación transaccional.
- RLS y funciones de confianza; sin grants amplios a tablas protegidas.
- Auditoría de altas, aprobaciones, revocaciones y cambios, sin secretos.
- Separación estricta por organización y domicilio.
- No importar datos ficticios o heredados como identidades reales.

## 9. Orden de implementación

1. Inspeccionar el esquema real de Supabase, RLS, políticas, funciones, triggers e índices, sin modificarlo.
2. Diseñar la entidad de credenciales de domicilio y su generación automática.
3. Diseñar RPC/Edge Function para validar PIN y crear solicitudes pendientes.
4. Definir y probar el alta del primer responsable y de integrantes adicionales.
5. Resolver autenticación telefónica individual y recuperación sin costos no autorizados.
6. Implementar la experiencia vecinal accesible.
7. Integrar alertas y Centro de Monitoreo.
8. Probar en entorno aislado con datos ficticios.
9. Revisar y aprobar antes de cualquier despliegue.

## 10. Límites operativos

No ejecutar este documento como SQL. No modificar producción ni desplegar la terminal vecinal en esta etapa. No habilitar Phone, SMS o WhatsApp pagos sin evaluación y autorización expresa. No reutilizar credenciales ni datos heredados.
