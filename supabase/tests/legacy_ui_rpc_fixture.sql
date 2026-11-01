-- CI ONLY: disposable legacy UI RPCs with isolated write/read persistence.
-- Never apply this file to any hosted Supabase project. Credentials and records are synthetic.
create table public.ci_barber_sales (
 id bigint generated always as identity primary key,
 folio text not null unique, cliente text not null, servicio text not null, barbero text not null,
 total numeric(12,2) not null check(total>=0),
 metodo text not null check(metodo in ('Efectivo','Transferencia','Tarjeta','Mixto')),
 efectivo numeric(12,2) not null default 0 check(efectivo>=0),
 tarjeta numeric(12,2) not null default 0 check(tarjeta>=0),
 created_at timestamptz not null default now(),
 check(metodo<>'Mixto' or round(efectivo+tarjeta,2)=total)
);
create table public.ci_barber_sale_payments (
 sale_id bigint not null references public.ci_barber_sales(id) on delete cascade,
 metodo text not null check(metodo in ('Efectivo','Tarjeta','Transferencia')),
 importe numeric(12,2) not null check(importe>0),
 primary key(sale_id,metodo)
);

create or replace function public.barber_admin_login(p_username text,p_password text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_token constant uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
begin
 if p_username<>'local-qa-user' or p_password<>'local-qa-password-not-a-credential' then
  raise exception 'Credenciales de prueba inválidas' using errcode='28000';
 end if;
 insert into public.barber_admin_sessions(token,username,expires_at,revoked_at)
 values(v_token,'local-qa-user',now()+interval '1 hour',null)
 on conflict(token) do update set username=excluded.username,expires_at=excluded.expires_at,revoked_at=null;
 return jsonb_build_object('token',v_token::text);
end;
$$;

create or replace function public.barber_admin_reservations(p_token uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.barber_admin_sessions s where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
  raise exception 'Sesión de prueba inválida o vencida' using errcode='28000';
 end if;
 return '[]'::jsonb;
end;
$$;

create or replace function public.barber_admin_sales(p_token uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.barber_admin_sessions s where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
  raise exception 'Sesión de prueba inválida o vencida' using errcode='28000';
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
  'folio',folio,'total',total,'cliente',cliente,'servicio',servicio,'barbero',barbero,
  'metodo',metodo,'efectivo',efectivo,'tarjeta',tarjeta) order by id desc)
  from public.ci_barber_sales),'[]'::jsonb);
end;
$$;

create or replace function public.barber_admin_create_walkin_sale(
 p_token uuid,p_cliente text,p_servicio_id integer,p_barbero_id integer,p_metodo text,p_recibido numeric,
 p_efectivo numeric,p_tarjeta numeric
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_total numeric(12,2); v_cash numeric(12,2); v_card numeric(12,2);
 v_folio text; v_id bigint; v_service text; v_barber text;
begin
 if not exists(select 1 from public.barber_admin_sessions s where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
  raise exception 'Sesión de prueba inválida o vencida' using errcode='28000';
 end if;
 if p_servicio_id not between 1 and 9 or p_barbero_id not between 1 and 2 or
    p_metodo not in ('Efectivo','Transferencia','Tarjeta','Mixto') then
  raise exception 'Datos de venta de prueba inválidos' using errcode='22023';
 end if;
 v_total:=case p_servicio_id when 1 then 160 when 2 then 180 when 3 then 130 when 4 then 40 when 5 then 80 when 6 then 280 when 7 then 250 when 8 then 400 else 550 end;
 if p_metodo='Mixto' then
  if p_efectivo is null or p_tarjeta is null or p_efectivo<0 or p_tarjeta<0 or round(p_efectivo+p_tarjeta,2)<>v_total then
   raise exception 'Pago mixto inválido: efectivo + tarjeta debe igualar el total' using errcode='22023';
  end if;
  v_cash:=p_efectivo; v_card:=p_tarjeta;
 else
  v_cash:=case when p_metodo='Efectivo' then v_total else 0 end;
  v_card:=case when p_metodo='Tarjeta' then v_total else 0 end;
 end if;
 v_service:=case p_servicio_id when 1 then 'Corte Clásico' when 2 then 'Corte Desvanecido' when 3 then 'Corte Infantil' when 4 then 'Alineación de Ceja' when 5 then 'Alineación de Barba' when 6 then 'Corte + Masaje' when 7 then 'Corte y Lavado de Cabello' when 8 then 'VIP' else 'Premium' end;
 v_barber:=case when p_barbero_id=1 then 'EdgarMay' else 'Staff 2' end;
 v_folio:='QA-WALKIN-'||lpad((coalesce((select max(id) from public.ci_barber_sales),0)+1)::text,6,'0');
 insert into public.ci_barber_sales(folio,cliente,servicio,barbero,total,metodo,efectivo,tarjeta)
 values(v_folio,coalesce(nullif(trim(p_cliente),''),'Cliente QA'),v_service,v_barber,v_total,p_metodo,v_cash,v_card)
 returning id into v_id;
 if v_cash>0 then insert into public.ci_barber_sale_payments values(v_id,'Efectivo',v_cash); end if;
 if v_card>0 then insert into public.ci_barber_sale_payments values(v_id,'Tarjeta',v_card); end if;
 if p_metodo='Transferencia' then insert into public.ci_barber_sale_payments values(v_id,'Transferencia',v_total); end if;
 return jsonb_build_object('folio',v_folio,'total',v_total,'cliente',coalesce(nullif(trim(p_cliente),''),'Cliente QA'),
  'servicio',v_service,'barbero',v_barber,'metodo',p_metodo,'efectivo',v_cash,'tarjeta',v_card,
  'cambio',case when p_metodo='Efectivo' then greatest(coalesce(p_recibido,0)-v_total,0) else 0 end);
end;
$$;

create or replace function public.barber_public_schedule(p_fecha date,p_barbero_id integer)
returns table(hora text,disponible boolean)
language sql stable security definer set search_path=public,pg_temp as $$
 select h.hora,true from unnest(array['13:30','14:00','14:30','15:00','15:30','16:00','16:30','17:00',
 '17:30','18:00','18:30','19:00','19:30','20:00','20:30']::text[]) as h(hora)
 where p_fecha is not null and p_barbero_id in (1,2) order by h.hora;
$$;

grant execute on function public.barber_admin_login(text,text) to anon,authenticated;
grant execute on function public.barber_public_schedule(date,integer) to anon,authenticated;
grant execute on function public.barber_admin_reservations(uuid) to anon,authenticated;
grant execute on function public.barber_admin_sales(uuid) to anon,authenticated;
grant execute on function public.barber_admin_create_walkin_sale(uuid,text,integer,integer,text,numeric,numeric,numeric) to anon,authenticated;

-- CI-only legacy payment RPCs used as the underlying implementation by the
-- additive mixed-payment overloads. These write only to the disposable fixture.
create or replace function public.barber_admin_create_sale(
 p_token uuid,p_reserva_id uuid,p_metodo text,p_recibido numeric
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare r public.reservas%rowtype; s public.barber_sales%rowtype;
begin
 if not exists(select 1 from public.barber_admin_sessions where token=p_token and revoked_at is null and expires_at>now()) then
  raise exception 'Sesión inválida' using errcode='28000';
 end if;
 select * into r from public.reservas where id=p_reserva_id for update;
 if not found then raise exception 'Reserva no encontrada'; end if;
 if exists(select 1 from public.barber_sales where reserva_id=p_reserva_id) then raise exception 'Reserva ya cobrada'; end if;
 insert into public.barber_sales(reserva_id,cliente,servicio,barbero,total,metodo,recibido,cambio)
 values(r.id,r.nombre,coalesce(r.servicio,r.serv),'EdgarMay',r.precio,p_metodo,
        greatest(coalesce(p_recibido,r.precio),0),
        case when p_metodo='Efectivo' then greatest(coalesce(p_recibido,r.precio)-r.precio,0) else 0 end)
 returning * into s;
 update public.reservas set estado='atendida' where id=r.id;
 return jsonb_build_object('id',s.id,'folio',s.folio,'total',s.total,'cliente',s.cliente,
   'servicio',s.servicio,'barbero',s.barbero,'metodo',s.metodo,'recibido',s.recibido,'cambio',s.cambio);
end $$;

create or replace function public.barber_admin_create_walkin_sale(
 p_token uuid,p_cliente text,p_servicio_id integer,p_barbero_id integer,p_metodo text,p_recibido numeric
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare s public.barber_sales%rowtype; v_service public.barber_services%rowtype; v_barber text;
begin
 if not exists(select 1 from public.barber_admin_sessions where token=p_token and revoked_at is null and expires_at>now()) then
  raise exception 'Sesión inválida' using errcode='28000';
 end if;
 select * into v_service from public.barber_services where id=p_servicio_id and is_active;
 if not found or p_barbero_id not in (1,2) then raise exception 'Servicio o barbero inválido'; end if;
 v_barber:=case when p_barbero_id=1 then 'EdgarMay' else 'Staff 2' end;
 insert into public.barber_sales(cliente,servicio,barbero,total,metodo,recibido,cambio)
 values(coalesce(nullif(trim(p_cliente),''),'Cliente QA'),v_service.name,v_barber,v_service.price,p_metodo,
   greatest(coalesce(p_recibido,v_service.price),0),
   case when p_metodo='Efectivo' then greatest(coalesce(p_recibido,v_service.price)-v_service.price,0) else 0 end)
 returning * into s;
 return jsonb_build_object('id',s.id,'folio',s.folio,'total',s.total,'cliente',s.cliente,
   'servicio',s.servicio,'barbero',s.barbero,'metodo',s.metodo,'recibido',s.recibido,'cambio',s.cambio);
end $$;
