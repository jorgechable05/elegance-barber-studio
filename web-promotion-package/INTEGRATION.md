# Integración de servicios y promociones — estado de la rama

## Estado actual

Las páginas recuperadas y versionadas para pruebas están en `web-recovery/admin.html`, `web-recovery/cliente.html` y `web-recovery/pos.html`. La rama conecta el panel de promociones del Admin y la oferta de Cliente con los módulos `web-promotion-package/admin-promotions.js` y `customer-promotion-utils.js`.

Esto **no significa que se haya publicado la integración**. Las rutas de producción `/admin`, `/cliente` y `/pos` siguen respondiendo con el contenido anterior y no cargan estos módulos. No se ha fusionado el PR ni se ha desplegado esta rama.

## Comportamiento implementado en la rama de pruebas

### Admin
- Conserva el login y el token de sesión administrativo existentes.
- Monta el panel Servicios y Promociones dentro de la vista recuperada solo después del login.
- Las promociones se guardan en borrador/pendiente de revisión; los botones de aprobar, rechazar y pausar llaman a las RPC administrativas de la propuesta.
- El montaje de la UI fue probado con Playwright usando RPC simuladas, no contra una sesión Supabase real.

### Cliente
- Conserva IDs numéricos de servicio del 1 al 9.
- Consulta el catálogo, determina la oferta aplicable a la fecha/hora/servicio y calcula el precio visual de promoción.
- Al reservar, invoca `barber_create_reservation_with_promotion` con el ID de la promoción; el navegador no envía un precio autoritativo.
- La lógica SQL temporal valida la aprobación, vigencia, servicio, precio y disponibilidad de usos.
- La visualización de oferta y llamada de reserva pasaron en Playwright con respuestas de RPC simuladas. La reserva no se insertó en ningún backend real.

### POS
- El archivo recuperado está versionado como referencia; su interfaz y scripts de producción no se rediseñaron.
- El smoke test local completa el flujo de venta de mostrador hasta el ticket con el endpoint simulado. No valida persistencia, cobros ni impresora física reales.

## Evidencia automática más reciente

- GitHub Actions — validación integrada aislada, Playwright local, pruebas JS, migraciones en PostgreSQL temporal, contratos SQL, permisos/sesiones y concurrencia: https://github.com/jorgechable05/elegance-barber-studio/actions/runs/41210225486
- GitHub Actions — ejecución equivalente asociada al PR: https://github.com/jorgechable05/elegance-barber-studio/actions/runs/41210230447

En el smoke test se interceptan las RPC con fixtures y se bloquea el tráfico externo no necesario; además, la prueba afirma que no se envió ninguna petición al Supabase de producción.

## Bloqueos antes de certificar

1. **Supabase aislado:** no se identificó un proyecto separado de Elegance Barber para aceptación. No usar el backend activo para crear reservas de prueba, ni usar proyectos de otros sistemas.
2. **Preview de hosting:** crear/verificar una vista previa aislada cuya raíz reproduzca las rutas de publicación. La prueba local valida imports en una estructura de staging, no el hosting real.
3. **RPC reales:** probar el login administrativo, listado/guardado/revisión de promociones, rechazo de sesiones vencidas/revocadas, oferta aprobada, rechazo de ofertas no aprobadas y reserva con precio persistido en el backend aislado.
4. **POS:** ejecutar regresión de ventas con reserva y de mostrador, métodos de pago, recibo de 58 mm y persistencia en el mismo backend de prueba, manteniendo las vistas actuales.
5. **Scheduler:** revisar `pg_cron`, el rol de ejecución y el resultado de la función interna de sugerencias en el Supabase de pruebas. Las sugerencias deben quedar pendientes de aprobación; el scheduler no debe publicarlas por sí mismo.

## Restricciones de seguridad

- No aplicar migraciones a producción.
- No conectar ni ejecutar pruebas con creación de datos contra el Supabase activo.
- No fusionar el PR ni promover un despliegue hasta cerrar los bloqueos de arriba.
- No cambiar el flujo ni el diseño del POS como parte de estas pruebas.
