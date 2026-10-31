# ELEGANCE BARBER STUDIO — Integración de servicios y promociones

## Estado verificado (2026-10-30)

- El proyecto Vercel `elegance-barber-piste` sirve las rutas existentes `/admin`, `/cliente` y `/pos`.
- El repositorio GitHub conectado a esta rama contiene el wrapper Android y documentos de construcción; no contiene el código fuente web de esas tres páginas.
- Una copia recuperada de las tres páginas se encontró en un sandbox persistente de Vercel. Es una copia de trabajo de rescate, no un repositorio/fuente versionada y no se ha desplegado.
- El flujo actual del cliente llama a `barber_create_reservation` con `p_servicio_id: selectedServiceId` donde `selectedServiceId` se usa como número. También sigue leyendo nombres/precios a partir del catálogo embebido.
- El flujo de Admin inicia sesión con `barber_admin_login` y conserva un token de sesión que se envía como `p_token` a las RPC administrativas existentes.
- POS utiliza RPC existentes para las ventas y debe seguir sin cambios.

## Reglas de seguridad para la integración

1. No aplicar las migraciones borrador a producción.
2. No sobrescribir la página de Cliente usando solamente UUID nuevos hasta cerrar la compatibilidad con `barber_create_reservation` y su catálogo actual.
3. No recalcular retrospectivamente el precio de reservas ya creadas; el importe guardado de cada reserva es histórico.
4. Las sugerencias automáticas solo se guardan en estado `pending_review`. No deben mostrarse al cliente ni tener efecto en POS hasta que el administrador las apruebe.
5. Las promociones públicas deben ser válidas en la fecha y hora que el cliente elija, no solo en `now()`. Deben comprobar fecha de inicio/fin, día de semana, intervalo horario y servicio seleccionado.
6. No cambiar ni recrear las RPC de venta, devolución o tickets POS como parte de esta tarea.
7. Las funciones administrativas deben validar una sesión activa y no confiar únicamente en que el cliente oculte botones.
8. Antes de integrar, ejecutar los casos de regresión históricos y nuevas pruebas de compatibilidad en una copia no productiva.

## Bloqueos técnicos encontrados en los borradores

- El esquema nuevo usa UUID para servicios, pero la página Cliente recuperada usa IDs numéricos en la llamada de reserva. Se necesita una tabla de equivalencia/cambio compatible o una ampliación de RPC deliberada y probada.
- La función pública de promociones debe recibir una fecha/hora objetivo para filtrar la promoción aplicable a la cita; filtrar únicamente con `now()` no resuelve reservas futuras.
- `barber_promotions_generate_daily_suggestions(p_token uuid)` exige un token de administrador aunque una tarea programada no puede tener sesión interactiva. Separar una función interna no ejecutable por `anon/authenticated` de la función manual administrativa, y programar con un rol de confianza protegido.
- La heurística de sugerencia debe incluir en el alcance fecha/días y horas requeridos y evitar sugerencias duplicadas en caso de ejecuciones concurrentes.
- El borrador requiere validar `p_price is not null`, arrays de días vacíos, y el caso de horario que cruza medianoche si se desea soportarlo; por ahora debería prohibirse de forma explícita.
- No sembrar precios del catálogo de memoria como verdad; primero importar/verificar el catálogo vigente y mantener sus identificadores funcionales actuales.

## Pruebas mínimas antes de desplegar

- Página Cliente, Admin y POS responden HTTP 200.
- Reserva normal para cada servicio habilitado conserva el ID y precio esperados.
- Promoción en borrador/pendiente/rechazada/pausada/no vigente no aparece al cliente.
- Promoción aprobada aparece solo en la fecha, día, horario y servicio configurados.
- Descuento porcentual y precio especial calculan el importe correctamente; límites y redondeo explícitos.
- Cambiar una promoción o precio no cambia citas ya confirmadas.
- Sesión administrativa vencida/revocada no puede editar servicios ni revisar promociones.
- POS: venta con reserva, venta sin reserva, pagos existentes, recibo 58 mm, consulta de ventas; sin cambios de comportamiento.
- Sugerencias se generan como pendientes, no se publican, y no se duplican al repetir la tarea diaria.

## Estado de implementación

Este documento y los SQL borrador son artefactos de diseño en la rama de característica. No se han aplicado migraciones ni se ha desplegado ningún cambio a producción. La interfaz aún requiere integración real y pruebas end-to-end antes de considerarse terminada.
