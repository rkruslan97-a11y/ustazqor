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


-- UstazQor competition features: complaints and class groups
create table if not exists public.complaints (
 id uuid primary key default gen_random_uuid(),
 author_id uuid not null references public.profiles(id) on delete cascade,
 against_user_id uuid references public.profiles(id) on delete set null,
 category text not null default 'communication',
 description text not null check (char_length(description) between 5 and 3000),
 status text not null default 'new' check (status in ('new','review','resolved')),
 created_at timestamptz not null default now()
);
create table if not exists public.class_groups (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now()
);
create table if not exists public.group_members (
 group_id uuid references public.class_groups(id) on delete cascade,
 user_id uuid references public.profiles(id) on delete cascade,
 primary key(group_id,user_id)
);
create table if not exists public.group_messages (
 id uuid primary key default gen_random_uuid(),
 group_id uuid not null references public.class_groups(id) on delete cascade,
 sender_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check (char_length(body) between 1 and 2000),
 created_at timestamptz not null default now()
);
alter table public.complaints enable row level security;
alter table public.class_groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_messages enable row level security;
drop policy if exists "users submit complaints" on public.complaints;
create policy "users submit complaints" on public.complaints for insert to authenticated with check(auth.uid()=author_id);
drop policy if exists "authors read complaints" on public.complaints;
create policy "authors read complaints" on public.complaints for select to authenticated using(auth.uid()=author_id or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "admins update complaints" on public.complaints;
create policy "admins update complaints" on public.complaints for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "members see groups" on public.class_groups;
create policy "members see groups" on public.class_groups for select to authenticated using(exists(select 1 from public.group_members gm where gm.group_id=id and gm.user_id=auth.uid()));
drop policy if exists "members see memberships" on public.group_members;
create policy "members see memberships" on public.group_members for select to authenticated using(user_id=auth.uid() or exists(select 1 from public.group_members gm where gm.group_id=group_members.group_id and gm.user_id=auth.uid()));
drop policy if exists "members read group messages" on public.group_messages;
create policy "members read group messages" on public.group_messages for select to authenticated using(exists(select 1 from public.group_members gm where gm.group_id=group_messages.group_id and gm.user_id=auth.uid()));
drop policy if exists "members send group messages" on public.group_messages;
create policy "members send group messages" on public.group_messages for insert to authenticated with check(sender_id=auth.uid() and exists(select 1 from public.group_members gm where gm.group_id=group_messages.group_id and gm.user_id=auth.uid()));
