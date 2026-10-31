# Estado de implementación (actualizado 2026-10-31)

## Avances comprobados en rama aislada
- [x] Recuperadas las fuentes de `/admin`, `/cliente` y `/pos` bajo `web-recovery/`; no se modificó el despliegue.
- [x] Añadido al Admin recuperado un acceso separado a Servicios y Promociones, sin alterar la agenda existente por defecto.
- [x] El cliente recuperado consulta servicios activos y ofertas aprobadas, y envía la selección a la RPC de reserva del servidor sin confiar en un precio enviado por el navegador.
- [x] Conservados los IDs numéricos de servicio 1–9 y el importe histórico entero de `reservas.precio`.
- [x] La función interna de sugerencias diarias queda restringida a `service_role`; el SQL intenta programar `pg_cron` solo si la extensión ya está disponible.
- [x] POS recuperado: se agregaron campos separados para efectivo y tarjeta cuando se elige `Mixto`, validación para que ambos sumen exactamente el total, y desglose visible en el ticket térmico de 58 mm.
- [x] La fixture CI exclusiva de PostgreSQL temporal ahora persiste ventas y pagos sintéticos, permite volver a leer las ventas y rechaza el desglose mixto incorrecto. La fixture está prohibida para bases alojadas.
- [x] GitHub Actions ahora activa las pruebas cuando cambian las páginas recuperadas del POS.
- [x] PR #1 sigue abierto como borrador, no fusionado: https://github.com/jorgechable05/elegance-barber-studio/pull/1

## Última ejecución automatizada
- [x] JavaScript unitario y análisis sintáctico de las vistas.
- [x] Playwright con backend simulado, sin peticiones al Supabase de producción.
- [x] Migraciones y contratos sobre PostgreSQL temporal.
- [x] Integración HTTP de RPC con PostgREST local.
- [x] Flujo de navegador contra PostgREST local y verificación/limpieza de la reserva creada.
- [x] Contratos del scheduler, permisos e idempotencia en PostgreSQL temporal.
- [x] Prueba concurrente de promoción de uso único.
- [x] Resultado de la ejecución aislada: https://github.com/jorgechable05/elegance-barber-studio/actions/runs/41242485408

## Bloqueos para certificar producción
- [ ] **Contrato real del POS:** el backend real no está versionado en este repositorio y no se confirmó que `barber_admin_create_sale` ni `barber_admin_create_walkin_sale` acepten `p_efectivo` y `p_tarjeta`. La prueba actual demuestra persistencia y lectura solo en el fixture de CI; no equivale a una venta persistida en Supabase. No desplegar el cambio de pagos mixtos hasta alinear y probar la RPC real en un entorno no productivo.
- [ ] **Supabase no productivo:** no se identificó un proyecto de pruebas separado de Elegance. No usar `elegance-piste`, no aplicar migraciones ni ejecutar ventas reales hasta identificar/autorizar el entorno aislado.
- [ ] **Scheduler en Supabase:** CI prueba la función e idempotencia en PostgreSQL temporal, pero no demuestra que `pg_cron` esté instalado/activo ni que exista el trabajo diario en una instancia de Supabase.
- [ ] **Preview de Vercel:** falta probar la publicación aislada. No publicar el POS recuperado en preview mientras conserve el endpoint del proyecto activo en el HTML; primero debe configurarse para exigir un endpoint de prueba, evitando que una vista previa pueda escribir en producción.
- [x] No se aplicaron migraciones a Supabase, no se creó rama/proyecto de pago y no se cambió Vercel.

**Estado de certificación: NO CERTIFICADO PARA PRODUCCIÓN.** Mantener PR #1 en borrador; no fusionar ni desplegar hasta resolver los bloqueos anteriores.
