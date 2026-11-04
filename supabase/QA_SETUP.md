# Elegance Barber — puesta en marcha del entorno QA

Este procedimiento corresponde únicamente al proyecto aislado `elegance-barber-qa` (`mgsppzbsqulomykpdjfv`). No ejecutar en `elegance-piste`.

## 1. Inicializar el PIN del personal

La cuenta de QA está creada como `EdgarMay`, pero no se copió ningún PIN de producción y el campo `pin_hash` permanece vacío.

En el SQL Editor del proyecto QA, genera el hash y guárdalo en la misma operación sustituyendo `CAMBIA_ESTE_PIN` por un PIN nuevo que no uses en producción:

```sql
update public.barber_admin_config
set pin_hash = extensions.crypt('CAMBIA_ESTE_PIN', extensions.gen_salt('bf')),
    updated_at = now()
where id = true and pin_hash is null;
```

No envíes el PIN por chat. El mismo usuario `EdgarMay` y el PIN nuevo funcionarán en Admin y POS de QA.

## 2. Activar Cloudflare Turnstile para el registro QR

1. En Cloudflare Dashboard, abre Turnstile y crea un widget tipo **Managed**.
2. Autoriza estos hostnames:
   - `elegance-barber-piste-5j0r0px29-dell-723c.vercel.app` (vista previa QA actual).
   - `elegance-barber-piste.vercel.app` (dominio reservado para el despliegue futuro).
3. Copia el **Site Key** (clave pública) y envíala para incorporarla a `config.js`.
4. En Supabase Dashboard, abre el proyecto QA y ve a **Edge Functions → Secrets**. Añade:
   - Nombre: `CLOUDFLARE_TURNSTILE_SECRET`
   - Valor: el **Secret Key** de Turnstile.

No compartas el Secret Key por chat ni lo pongas en archivos del navegador. La función `barber-loyalty-register` falla de forma cerrada mientras falte ese secreto.

## 3. Validación antes de usar con clientes

- Admin y POS deben iniciar sesión con el PIN QA nuevo.
- El formulario QR debe mostrar el control Turnstile y aceptar registros válidos.
- Las visitas solo se agregan desde una venta cobrada y confirmada por el personal.
- Al registrar la quinta visita se crea una recompensa pendiente; el personal la canjea al entregar el corte de cortesía.
- Las promociones sugeridas diariamente quedan pendientes de aprobación; al aprobar/publicar una promoción, aparece en la página de reservas dentro de sus fechas, horarios y servicios.

## 4. Alcance

Este entorno no contiene reservas, ventas ni clientes de producción. La vista previa no tiene alias de producción y no modifica el sitio público actual.
