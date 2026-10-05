-- UstazQor MVP schema
create extension if not exists pgcrypto;

create table if not exists public.pilot_feedback (
  id uuid primary key default gen_random_uuid(),
  role text not null check (role in ('teacher','parent','student','admin')),
  usability int not null check (usability between 1 and 5),
  work_hours_useful boolean not null,
  qorai_useful boolean not null,
  comment text,
  created_at timestamptz not null default now()
);

alter table public.pilot_feedback enable row level security;

drop policy if exists "anonymous can submit pilot feedback" on public.pilot_feedback;
create policy "anonymous can submit pilot feedback"
on public.pilot_feedback for insert
to anon, authenticated
with check (
  role in ('teacher','parent','student','admin')
  and usability between 1 and 5
);

-- No SELECT policy is intentionally created:
-- public visitors can submit feedback but cannot read all responses.


-- UstazQor 2.0: authenticated profiles and direct messaging
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null,
 role text not null check (role in ('teacher','parent','student','admin')),
 school_name text default 'Пилотная школа',
 class_name text,
 created_at timestamptz not null default now()
);
create table if not exists public.messages (
 id uuid primary key default gen_random_uuid(),
 sender_id uuid not null references public.profiles(id) on delete cascade,
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check (char_length(body) between 1 and 2000),
 deliver_after timestamptz,
 created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
alter table public.messages enable row level security;
drop policy if exists "authenticated users can view profiles" on public.profiles;
create policy "authenticated users can view profiles" on public.profiles for select to authenticated using (true);
drop policy if exists "users create own profile" on public.profiles;
create policy "users create own profile" on public.profiles for insert to authenticated with check (auth.uid() = id);
drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);
drop policy if exists "participants read own messages" on public.messages;
create policy "participants read own messages" on public.messages for select to authenticated using (auth.uid() = sender_id or auth.uid() = recipient_id);
drop policy if exists "sender creates message" on public.messages;
create policy "sender creates message" on public.messages for insert to authenticated with check (auth.uid() = sender_id and sender_id <> recipient_id);


-- Realtime for direct messages (safe to run once; ignore duplicate membership if already enabled)
do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null;
end $$;
