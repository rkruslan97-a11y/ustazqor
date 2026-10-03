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
