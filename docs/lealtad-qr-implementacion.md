# ELEGANCE BARBER STUDIO — Lealtad mediante QR único

## Alcance
Implementación aislada sobre `feat/lealtad-qr-clientes`. No modifica producción ni aplica SQL a Supabase alojado.

## Flujo del cliente
1. Un único QR permanente apunta a `/fidelidad`; no se generan QR individuales.
2. La primera visita al QR muestra registro con nombre y teléfono. El teléfono se normaliza y se usa como identificador único.
3. Si el teléfono ya existe, el formulario no crea otro cliente ni permite al visitante incrementar sus visitas.
4. La página muestra una confirmación neutral y pide acudir al personal para registrar la visita.

## Registro de visitas y premio
- Solo Administración o POS, después de verificar una atención/cobro completado, pueden registrar una visita.
- La operación debe ser idempotente por venta/folio para impedir doble conteo al reintentar.
- El contador se incrementa una sola vez por venta válida; cancelaciones y devoluciones no generan visitas.
- Al alcanzar cinco visitas válidas se crea un premio pendiente: un corte de cortesía.
- El premio queda visible en Administración y POS. El personal lo marca como entregado/redimido; no se vuelve a emitir por el mismo ciclo.
- Tras redimir el premio, el ciclo de fidelidad inicia nuevamente desde cero y conserva el historial de visitas y premios.

## Paneles
### Administración
- Apartado Lealtad: QR único descargable/imprimible, URL pública, clientes, visitas, alertas de quinto corte y premios pendientes/redimidos.
- Búsqueda por nombre/teléfono y detalle de historial.
- Registro manual de visita con motivo obligatorio solo para correcciones autorizadas y auditadas.

### POS
- Buscar cliente por teléfono o escanear el mismo QR.
- Confirmar la visita desde una venta finalizada.
- Mostrar progreso 1/5 a 5/5 y alerta destacada cuando se gana el corte.
- No alterar el flujo de cobro ni los tickets existentes; la integración de visita debe ser idempotente.

## Datos y seguridad
- Tabla de clientes de lealtad con teléfono normalizado único.
- Tabla inmutable de eventos de visita vinculados a una venta/folio cuando corresponda.
- Tabla de recompensas con estados pendiente, entregada y cancelada.
- RLS habilitado en todas las tablas expuestas.
- RPC de registro público limitada a alta/consulta mínima; jamás puede incrementar visitas ni leer la lista de clientes.
- RPC de registro de visita exige sesión válida de personal y venta completada.
- No exponer `service_role`, tokens administrativos ni datos de otros clientes al navegador.
- El número de teléfono es dato personal: mostrarlo enmascarado en vistas no administrativas y solicitar aviso/consentimiento de privacidad en el registro.

## Criterios de aceptación
1. El mismo QR sirve para todos los clientes y no caduca.
2. Primer registro con teléfono nuevo crea un solo perfil.
3. Repetir el registro con el mismo teléfono no duplica al cliente.
4. El cliente no puede sumar visitas por escanear el QR ni manipulando la página.
5. Una venta finalizada suma exactamente una visita; doble envío no duplica.
6. Venta cancelada o devuelta no suma visita.
7. La quinta visita crea exactamente un premio de corte de cortesía y alerta en Admin/POS.
8. Redimir el premio registra fecha y empleado; no se puede redimir dos veces.
9. Tras redimir, el siguiente ciclo comienza desde cero y el historial anterior permanece.
10. Pruebas de permisos, RLS, concurrencia, duplicados y regresión de reservas/POS deben pasar antes de publicar.

## Bloqueos de certificación
- El proyecto Supabase `elegance-piste` está activo y se considera producción; no ejecutar migraciones ni datos de prueba ahí.
- No se identificó una instancia Supabase no productiva disponible. No se debe crear un proyecto de pago ni cambiar el plan sin autorización adicional.
- El proyecto Vercel `elegance-barber-piste` no aparece vinculado a Git en el contexto consultado. El preview existente es una maqueta aislada sin persistencia real.
- El código web recuperado vive en `web-recovery/` y los módulos de promociones en `web-promotion-package/`; no están publicados en las rutas activas.
- Mantener la PR de promociones existente en borrador y no fusionar ni desplegar hasta certificar backend y regresiones en entorno aislado.
