# Estado de implementación: paquetes y promociones (actualizado 2026-11-01)

## Implementado en rama aislada `feat/paquetes-analitica-certificacion`

- [x] Editor de paquetes en Admin: nombre, descripción, precio conjunto y selección de dos o más servicios activos. El servidor rechaza duplicados, servicios inactivos y precios de paquete mayores a la suma individual.
- [x] POS recuperado ofrece selector separado para servicio individual o paquete; el cobro de paquete se registra con un RPC atómico, acepta pago mixto y conserva subtotal, descuento, total y desglose de servicios en ticket térmico.
- [x] RPC de reserva de paquete crea una cita con duración total, identificador de grupo, precio base y snapshots por servicio. La vista pública de Cliente permanece intacta para respetar la restricción de no cambiar su diseño; la RPC está preparada para integración cuando se valide el backend real.
- [x] Trigger de solapamiento con bloqueo por barbero/fecha rechaza citas que se crucen por duración, incluidas escrituras que usan el contrato heredado.
- [x] Costos unitarios históricos son opcionales y quedan NULL cuando se desconocen. Las ventas nuevas guardan snapshots de costo por servicio; el reporte no inventa márgenes de ventas antiguas.
- [x] Las sugerencias diarias consultan volumen real de ventas y margen solo cuando existen suficientes snapshots de costos. Guardan evidencia JSON con base, ventana, ventas, muestra de costos y margen estimado. Sin datos suficientes se etiquetan como heurísticas de respaldo. Ninguna sugerencia se publica sin aprobación manual.
- [x] Admin permite configurar periodo de análisis, margen mínimo y tamaño de muestra. Presenta ventas, ingreso atribuido, margen estimado y cobertura de costos.
- [x] Workflow `.github/workflows/packages-history-tests.yml` aplica y reaplica la migración en PostgreSQL temporal y ejecuta pruebas de paquete, solapamiento, pagos mixtos, snapshots, historial y sugerencias.
- [x] Se agregaron pruebas de contrato de UI para Admin y POS.

## Evidencia y certificación

- CI específico de la rama: [Package and history integration checks](https://github.com/jorgechable05/elegance-barber-studio/actions/workflows/packages-history-tests.yml). Consultar el workflow para el estado por commit; solo un resultado `success` en el HEAD actual cuenta como prueba aprobada.
- Las pruebas CI utilizan PostgreSQL temporal. No prueban persistencia en una instancia alojada de Supabase, privilegios reales ni que el job remoto de `pg_cron` se ejecute.
- El proyecto de producción `elegance-piste` no se ha modificado. No se aplicaron migraciones alojadas ni se desplegó nada. La PR #1 sigue separada, abierta y en borrador.
- El proveedor cotizó un proyecto QA Supabase dedicado en **US$0/mes**, pero exige confirmación explícita antes de crearlo. Por eso aún no es posible certificar la persistencia alojada y el scheduler remoto en este turno.
- Para cierre remoto: crear el proyecto QA autorizado, aplicar ahí las migraciones, crear y leer una venta sintética de paquete, verificar rollback de pago mixto incorrecto y comprobar `cron.job` para `elegance-promotion-suggestions-daily`, incluyendo comando y permisos de la función interna.
- Este estado es **NO CERTIFICADO PARA PRODUCCIÓN** hasta que pase la validación alojada y el preview/build aislado. No fusionar PR ni desplegar.

## Seguridad

No usar `elegance-piste`, `THOP-TEST` ni el proyecto CIBER-PISTE para pruebas de Elegance. No incluir secrets en GitHub ni usar credenciales reales en CI.
