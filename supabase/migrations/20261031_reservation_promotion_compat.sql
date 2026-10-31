-- Additive compatibility RPC. The legacy barber_create_reservation remains untouched.
-- New client code may opt into promotions; old clients keep using the existing RPC.
alter table public.reservas
  add column if not exists promotion_id uuid references public.barber_promotions(id);

create or replace function public.barber_create_reservation_with_promotion(
  p_barbero_id integer,
  p_fecha date,
  p_hora text,
  p_nombre text,
  p_notas text,
  p_servicio_id integer,
  p_telefono text,
  p_promotion_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_barbero text;
  v_servicio text;
  v_base_price numeric(10,2);
  v_final_price integer;
  v_promo public.barber_promotions;
  v_start_at timestamptz;
  v_weekday smallint;
  v_time time;
begin
  if p_barbero_id = 1 then v_barbero := 'EdgarMay';
  elsif p_barbero_id = 2 then v_barbero := 'Staff 2';
  else raise exception 'Barbero no válido'; end if;

  select s.name, s.price
    into v_servicio, v_base_price
    from public.barber_services s
   where s.id = p_servicio_id and s.is_active;
  if v_servicio is null then raise exception 'Servicio no válido o inactivo'; end if;

  if p_fecha is null or p_fecha < current_date then raise exception 'La fecha ya pasó'; end if;
  if extract(isodow from p_fecha) = 7 then raise exception 'Domingo cerrado'; end if;
  if nullif(trim(p_hora),'') is null then raise exception 'Horario no válido'; end if;
  begin
    v_time := left(trim(p_hora),5)::time;
  exception when others then
    raise exception 'Horario no válido';
  end;
  v_start_at := (p_fecha::text || ' ' || v_time::text || ' America/Merida')::timestamptz;
  v_weekday := extract(dow from p_fecha)::smallint;

  if exists (
    select 1 from public.reservas r
     where r.fecha=p_fecha and r.hora=left(trim(p_hora),5) and r.barbero=v_barbero
       and lower(coalesce(r.estado,'pendiente')) not in ('rechazada','cancelada','atendida')
  ) then raise exception 'Ese horario ya fue reservado'; end if;

  v_final_price := round(v_base_price)::integer;
  if p_promotion_id is not null then
    select p.* into v_promo
      from public.barber_promotions p
      join public.barber_promotion_services ps on ps.promotion_id=p.id
     where p.id=p_promotion_id
       and ps.service_id=p_servicio_id
       and p.status='approved'
       and v_start_at >= p.starts_at and v_start_at < p.ends_at
       and (p.max_uses is null or p.uses_count < p.max_uses)
       and (cardinality(p.weekdays)=0 or v_weekday=any(p.weekdays))
       and (p.start_time is null or v_time >= p.start_time)
       and (p.end_time is null or v_time < p.end_time)
     for update of p;
    if not found then raise exception 'La promoción ya no está disponible para esa cita'; end if;
    if v_promo.discount_type='percent' then
      if v_promo.discount_value <= 0 or v_promo.discount_value > 100 then raise exception 'Descuento no válido'; end if;
      v_final_price := round(v_base_price * (1 - v_promo.discount_value / 100))::integer;
    elsif v_promo.discount_type='fixed_price' then
      if v_promo.discount_value < 0 or v_promo.discount_value > v_base_price then raise exception 'Precio especial no válido'; end if;
      v_final_price := round(v_promo.discount_value)::integer;
    else raise exception 'Tipo de promoción no válido'; end if;
  end if;

  insert into public.reservas(
    nombre,telefono,wa,serv,servicio,precio,barbero,fecha,hora,estado,stock_key,promotion_id
  ) values (
    trim(p_nombre),trim(p_telefono),trim(p_telefono),v_servicio,v_servicio,v_final_price,
    v_barbero,p_fecha,left(trim(p_hora),5),'pendiente',
    p_fecha::text || '_' || v_barbero || '_' || left(trim(p_hora),5),p_promotion_id
  ) returning id into v_id;

  if p_promotion_id is not null then
    update public.barber_promotions set uses_count=uses_count+1,updated_at=now() where id=p_promotion_id;
  end if;
  return v_id;
end;
$$;

revoke all on function public.barber_create_reservation_with_promotion(integer,date,text,text,text,integer,text,uuid) from public;
grant execute on function public.barber_create_reservation_with_promotion(integer,date,text,text,text,integer,text,uuid) to anon, authenticated;
