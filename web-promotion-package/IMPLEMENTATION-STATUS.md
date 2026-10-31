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
- [ ] Ejecutar nuevas pruebas de comportamiento para redondeo, límites de uso y sesiones vencidas/revocadas; la regresión concurrente aún requiere resultado CI.
- [x] Definida la regla compatible de importe: `reservas.precio` conserva pesos enteros y la vista calcula el mismo redondeo para que el importe guardado coincida con lo mostrado.
- [ ] Revisar que el montaje de Admin funciona en la ruta y el hosting real cuando el código web esté versionado como raíz desplegable.
- [ ] Verificar el scheduler diario en la configuración real de Supabase; la migración no habilita extensiones que no estén instaladas.
- [ ] Ejecutar regresión end-to-end Admin/Cliente/POS. El POS solo está versionado como referencia y no se modificó.
- [ ] No se aplicó ninguna migración a Supabase ni se creó rama de pago ni se cambió Vercel.

**Estado:** las migraciones y contratos de esquema pasaron en PostgreSQL temporal; las pruebas añadidas de comportamiento/concurrencia y la regresión end-to-end siguen pendientes de resultado. No certificada para producción. No fusionar ni desplegar hasta cerrar los puntos anteriores.
