# Estado de implementación (actualizado 2026-10-31)

## Avance sin crear infraestructura de pago
- [x] Recuperadas en la rama aislada las fuentes actuales de `/admin`, `/cliente` y `/pos` bajo `web-recovery/`; no se modificó el despliegue.
- [x] Añadido al Admin recuperado un acceso separado a Servicios y Promociones, reutilizando el login/token actual y el adaptador de RPC. La agenda existente queda intacta por defecto.
- [x] El cliente recuperado consulta el catálogo administrable, muestra solo servicios activos y calcula la oferta aprobada aplicable a la fecha/hora/servicio seleccionados.
- [x] Añadida RPC aditiva `barber_create_reservation_with_promotion`: valida promoción aprobada en servidor, servicio, fecha, hora, usos y precio; conserva el importe en la reserva y no recalcula citas existentes. La RPC antigua permanece.
- [x] Los IDs de servicio permanecen numéricos 1–9 y el catálogo inicial conserva nombres y precios históricos conocidos.
- [x] La función de sugerencias diarias para scheduler queda restringida a `service_role`; el script intenta programarla solo si `pg_cron` ya existe.
- [x] Preparado workflow de GitHub Actions con PostgreSQL temporal para probar migraciones y contratos sin crear rama de Supabase de pago.
- [x] Abierto PR de borrador #1, no fusionado: https://github.com/jorgechable05/elegance-barber-studio/pull/1

## Pendiente de validación
- [x] Corregido el delimitador SQL de la función interna de sugerencias; las ejecuciones 12 y 13 del workflow pasaron con JS, migraciones temporales y aserciones de esquema.
- [x] Pruebas de comportamiento y concurrencia completadas en GitHub Actions: redondeo de importes, límite de usos, promociones pendientes, sesiones vencidas/revocadas y dos reservas simultáneas con un solo uso disponible. Ejecución final anterior: https://github.com/jorgechable05/elegance-barber-studio/actions/runs/41209259949.
- [x] Validación aislada de SQL/JavaScript verificada en la ejecución 40: pruebas JavaScript, análisis sintáctico de las tres vistas, migraciones en PostgreSQL temporal, contratos, permisos/sesiones y concurrencia pasaron: https://github.com/jorgechable05/elegance-barber-studio/actions/runs/41210225486.
- [x] Pruebas de navegador con Playwright y RPC simuladas: Admin monta el panel, Cliente muestra la promoción aprobada y llama a la RPC de reserva, y POS recorre venta de mostrador hasta ticket. Se comprobó que no hubo peticiones al Supabase de producción. Ejecución PR: https://github.com/jorgechable05/elegance-barber-studio/actions/runs/41210230447.
- [x] Definida la regla compatible de importe: `reservas.precio` conserva pesos enteros y la vista calcula el mismo redondeo para que el importe guardado coincida con lo mostrado.
- [x] Probar en un servidor local aislado el montaje de los módulos relativos de Admin y Cliente; los smoke tests de Playwright pasan con mocks.
- [ ] Probar las rutas reales de publicación en un preview aislado de Vercel. La comprobación de producción fue solo GET de lectura: `/admin`, `/cliente` y `/pos` responden 200, pero aún no incluyen los módulos de promociones.
- [ ] Verificar el scheduler diario en la configuración real de Supabase; la migración no habilita extensiones que no estén instaladas.
- [ ] Ejecutar integración real contra un proyecto Supabase no productivo de Elegance para aprobar/rechazar promociones, crear reservas y validar los permisos reales. No se identificó un proyecto separado de Elegance para pruebas; no reutilizar el backend activo.
- [ ] Completar regresión del POS contra el backend de prueba, incluidos los cuatro métodos de pago y la impresión 58 mm. El navegador pasó el flujo de mostrador usando RPC simuladas; no hubo ventas reales.
- [x] No se aplicó ninguna migración a Supabase; no se creó rama de pago ni se cambió Vercel.

**Estado:** la CI aislada más reciente (ejecuciones 40 y 41) pasa con PostgreSQL temporal y Playwright local usando mocks. Las pruebas de navegador no validan RPC reales. La certificación integral sigue pendiente de un proyecto Supabase no productivo de Elegance, un preview que refleje las rutas reales de publicación, la regresión POS contra ese backend y la verificación del scheduler. No certificada para producción; no fusionar ni desplegar hasta cerrar esos puntos.


- [x] La página Cliente recuperada contenía un bloque JavaScript truncado y fragmentos duplicados detrás de `</html>`; se reconstruyó el bloque de catálogo/reserva preservando la interfaz y se añadió verificación de sintaxis para Admin, Cliente y POS.
