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
- [x] Pruebas de comportamiento y concurrencia completadas en GitHub Actions: redondeo de importes, límite de usos, promociones pendientes, sesiones vencidas/revocadas y dos reservas simultáneas con un solo uso disponible. Ejecución final verificada: https://github.com/jorgechable05/elegance-barber-studio/actions/runs/41209259949.
- [x] Definida la regla compatible de importe: `reservas.precio` conserva pesos enteros y la vista calcula el mismo redondeo para que el importe guardado coincida con lo mostrado.
- [ ] Revisar que el montaje de Admin funciona en la ruta y el hosting real cuando el código web esté versionado como raíz desplegable.
- [ ] Verificar el scheduler diario en la configuración real de Supabase; la migración no habilita extensiones que no estén instaladas.
- [ ] Ejecutar regresión end-to-end Admin/Cliente/POS. El POS solo está versionado como referencia y no se modificó.
- [x] No se aplicó ninguna migración a Supabase; no se creó rama de pago ni se cambió Vercel.

**Estado:** las migraciones, contratos de esquema, pruebas JavaScript y pruebas de comportamiento/concurrencia pasan en PostgreSQL temporal. La certificación integral sigue pendiente de pruebas end-to-end de Admin/Cliente/POS y de verificar el montaje y el scheduler en los entornos reales. No certificada para producción; no fusionar ni desplegar hasta cerrar esos puntos.


- [x] La página Cliente recuperada contenía un bloque JavaScript truncado y fragmentos duplicados detrás de `</html>`; se reconstruyó el bloque de catálogo/reserva preservando la interfaz y se añadió verificación de sintaxis para Admin, Cliente y POS.
