begin;
create extension if not exists btree_gist;
create table public.consultation_slots (
 id uuid primary key default gen_random_uuid(),
 teacher_id uuid not null references public.profiles(id),
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 check (ends_at > starts_at and ends_at <= starts_at + interval '4 hours'),
 exclude using gist (teacher_id with =, tstzrange(starts_at,ends_at,'[)') with &&)
);
alter table public.consultation_slots enable row level security;
create policy "teachers publish slots" on public.consultation_slots for insert to authenticated
 with check (teacher_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='teacher') and starts_at>now());
create policy "teachers read own slots" on public.consultation_slots for select to authenticated using(teacher_id=auth.uid());
grant select,insert on public.consultation_slots to authenticated;
revoke update,delete on public.consultation_slots from authenticated,anon;
alter table public.consultation_bookings
 add column slot_id uuid references public.consultation_slots(id),
 add column starts_at timestamptz,
 add column ends_at timestamptz;
-- Historical labels have no date: retain their status, never guess a date.
alter table public.consultation_bookings add constraint booking_interval check (
 (slot_id is null and starts_at is null and ends_at is null) or
 (slot_id is not null and starts_at is not null and ends_at is not null and ends_at>starts_at));
alter table public.consultation_bookings add constraint no_confirmed_overlap
 exclude using gist (teacher_id with =,tstzrange(starts_at,ends_at,'[)') with &&)
 where (status='confirmed' and starts_at is not null);
create unique index one_active_request_per_slot on public.consultation_bookings(requester_id,slot_id)
 where status in ('pending','confirmed');
drop policy if exists "requesters book consultations" on public.consultation_bookings;
drop policy if exists "teachers manage consultations" on public.consultation_bookings;
revoke insert,update,delete on public.consultation_bookings from authenticated,anon;
grant select on public.consultation_bookings to authenticated;

create function public.available_consultation_slots(p_teacher uuid)
returns table(id uuid,starts_at timestamptz,ends_at timestamptz)
language sql stable security definer set search_path=public,pg_temp as $$
 select s.id,s.starts_at,s.ends_at from consultation_slots s
 where s.teacher_id=p_teacher and s.starts_at>now()
 and exists(select 1 from profiles where id=auth.uid() and role in ('parent','student'))
 and not exists(select 1 from consultation_bookings b where b.slot_id=s.id and
 (b.status='confirmed' or (b.requester_id=auth.uid() and b.status='pending')))
 order by s.starts_at
$$;
create function public.request_consultation(p_slot uuid) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare s consultation_slots; result uuid;
begin
 if not exists(select 1 from profiles where id=auth.uid() and role in ('parent','student')) then
 raise exception 'Только родители и ученики могут записываться' using errcode='42501'; end if;
 select * into s from consultation_slots where id=p_slot for update;
 if not found or s.starts_at<=now() then raise exception 'Время недоступно'; end if;
 if exists(select 1 from consultation_bookings where slot_id=p_slot and status='confirmed') then raise exception 'Время уже занято'; end if;
 insert into consultation_bookings(requester_id,teacher_id,slot_id,starts_at,ends_at,slot_label)
 values(auth.uid(),s.teacher_id,s.id,s.starts_at,s.ends_at,to_char(s.starts_at at time zone 'Asia/Oral','DD.MM.YYYY HH24:MI')) returning id into result;
 return result;
end $$;
create function public.decide_consultation(p_booking uuid,p_status text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare b consultation_bookings;
begin
 if p_status is null or p_status not in ('confirmed','declined') then raise exception 'Недопустимый статус'; end if;
 select * into b from consultation_bookings where id=p_booking for update;
 if not found or b.teacher_id<>auth.uid() or not exists(select 1 from profiles where id=auth.uid() and role='teacher') then
 raise exception 'Нет доступа' using errcode='42501'; end if;
 if b.status=p_status then return; end if;
 if b.status<>'pending' then raise exception 'Заявка уже рассмотрена'; end if;
 if p_status='confirmed' and (b.slot_id is null or b.starts_at<=now()) then raise exception 'Создайте новую заявку на доступную дату'; end if;
 -- The GiST exclusion constraint arbitrates concurrent confirmations atomically.
 update consultation_bookings set status=p_status where id=b.id;
end $$;
revoke all on function public.available_consultation_slots(uuid),public.request_consultation(uuid),public.decide_consultation(uuid,text) from public,anon;
grant execute on function public.available_consultation_slots(uuid),public.request_consultation(uuid),public.decide_consultation(uuid,text) to authenticated;
commit;
