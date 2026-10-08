-- UstazQor: fix recursive group membership RLS
-- Run in Supabase SQL Editor as project owner.
create or replace function public.is_class_member(p_group_id uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = (select auth.uid())
  );
$$;
revoke all on function public.is_class_member(uuid) from public;
grant execute on function public.is_class_member(uuid) to authenticated;

drop policy if exists "members see memberships" on public.group_members;
create policy "members see memberships" on public.group_members
for select to authenticated
using (user_id = (select auth.uid()) or public.is_class_member(group_id));

drop policy if exists "members see groups" on public.class_groups;
drop policy if exists "admins see all groups" on public.class_groups;
create policy "members and admins see groups" on public.class_groups
for select to authenticated
using (
  public.is_class_member(id)
  or exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  )
);

drop policy if exists "members read group messages" on public.group_messages;
create policy "members read group messages" on public.group_messages
for select to authenticated using (public.is_class_member(group_id));

drop policy if exists "members send group messages" on public.group_messages;
create policy "members send group messages" on public.group_messages
for insert to authenticated
with check (sender_id = (select auth.uid()) and public.is_class_member(group_id));
