-- UstazQor consultation bookings
create table if not exists public.consultation_bookings (
 id uuid primary key default gen_random_uuid(),
 requester_id uuid not null references public.profiles(id),
 teacher_id uuid not null references public.profiles(id),
 slot_label text not null,
 status text not null default 'pending' check(status in ('pending','confirmed','declined')),
 created_at timestamptz not null default now(),
 check(requester_id <> teacher_id)
);
alter table public.consultation_bookings enable row level security;
drop policy if exists "requesters book consultations" on public.consultation_bookings;
create policy "requesters book consultations" on public.consultation_bookings for insert to authenticated
with check(requester_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=teacher_id and p.role='teacher'));
drop policy if exists "participants read consultations" on public.consultation_bookings;
create policy "participants read consultations" on public.consultation_bookings for select to authenticated
using(requester_id=(select auth.uid()) or teacher_id=(select auth.uid()));
drop policy if exists "teachers manage consultations" on public.consultation_bookings;
create policy "teachers manage consultations" on public.consultation_bookings for update to authenticated
using(teacher_id=(select auth.uid())) with check(teacher_id=(select auth.uid()));
