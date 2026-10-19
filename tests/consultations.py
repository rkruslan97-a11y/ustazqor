"""Integration tests. DATABASE_URL must point to an EMPTY disposable PostgreSQL database."""
import os, subprocess, unittest
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1]
URL=os.environ['DATABASE_URL']
def sql(query, user=None, ok=True):
    prefix=(f"set role authenticated; set request.jwt.claim.sub='{user}';" if user else '')
    r=subprocess.run(['psql',URL,'-XAt','-v','ON_ERROR_STOP=1','-c',prefix+query],capture_output=True,text=True)
    if ok and r.returncode: raise AssertionError(r.stderr)
    return r
T='00000000-0000-0000-0000-000000000001'
P='00000000-0000-0000-0000-000000000002'
S='00000000-0000-0000-0000-000000000003'
OTHER='00000000-0000-0000-0000-000000000004'
class BookingTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
    sql("create role authenticated; create role anon; create schema auth; create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$; grant usage on schema auth to authenticated; create table public.profiles(id uuid primary key,role text,full_name text); grant select on public.profiles to authenticated; insert into profiles values ('"+T+"','teacher','Teacher'),('"+P+"','parent','Parent'),('"+S+"','student','Student'),('"+OTHER+"','teacher','Other');")
    sql((ROOT/'supabase/consultations.sql').read_text())
    sql((ROOT/'supabase/migrations/20261019_consultation_slots.sql').read_text())
 def setUp(self):
    sql('truncate consultation_bookings,consultation_slots;')
    self.slot=sql(f"insert into consultation_slots(teacher_id,starts_at,ends_at) values ('{T}',now()+interval '1 day',now()+interval '1 day 20 minutes') returning id").stdout.splitlines()[0]
 def request(self,u):
    return sql(f"select request_consultation('{self.slot}')",u).stdout.splitlines()[-1]
 def decide(self,b,status='confirmed',u=T,ok=True):
    return sql(f"select decide_consultation('{b}','{status}')",u,ok)
 def test_repeat_request(self):
    self.request(P)
    self.assertNotEqual(sql(f"select request_consultation('{self.slot}')",P,False).returncode,0)
 def test_concurrent_requests_and_confirmation(self):
    with ThreadPoolExecutor(2) as pool: ids=list(pool.map(self.request,[P,S]))
    with ThreadPoolExecutor(2) as pool: results=list(pool.map(lambda b:self.decide(b,ok=False),ids))
    self.assertEqual(sum(r.returncode==0 for r in results),1)
    self.assertEqual(sql("select count(*) from consultation_bookings where status='confirmed'").stdout.strip(),'1')
    self.assertEqual(sql(f"select count(*) from available_consultation_slots('{T}')",S).stdout.splitlines()[-1],'0')
 def test_concurrent_duplicate(self):
    with ThreadPoolExecutor(2) as pool:
     results=list(pool.map(lambda _:sql(f"select request_consultation('{self.slot}')",P,False),range(2)))
    self.assertEqual(sum(r.returncode==0 for r in results),1)
 def test_decline_reapply_and_status(self):
    b=self.request(P);self.decide(b,'declined');new=self.request(P);self.decide(new)
    self.assertEqual(sql(f"select status from consultation_bookings where id='{b}'",P).stdout.splitlines()[-1],'declined')
    self.assertNotEqual(self.decide(b,ok=False).returncode,0)
 def test_access_and_direct_bypass(self):
    b=self.request(P)
    for u in [P,S,OTHER]:self.assertNotEqual(self.decide(b,u=u,ok=False).returncode,0)
    self.assertNotEqual(sql(f"update consultation_bookings set status='confirmed' where id='{b}'",P,False).returncode,0)
    self.assertEqual(sql('select count(*) from consultation_bookings',S).stdout.splitlines()[-1],'0')
    self.assertNotEqual(sql(f"select request_consultation('{self.slot}')",T,False).returncode,0)
 def test_schedule_overlap_and_adjacent(self):
    self.assertNotEqual(sql(f"insert into consultation_slots(teacher_id,starts_at,ends_at) select teacher_id,starts_at+interval '10 minutes',ends_at+interval '10 minutes' from consultation_slots",T,False).returncode,0)
    sql(f"insert into consultation_slots(teacher_id,starts_at,ends_at) select teacher_id,ends_at,ends_at+interval '20 minutes' from consultation_slots",T)
 def test_legacy_not_confirmable(self):
    b=sql(f"insert into consultation_bookings(requester_id,teacher_id,slot_label) values('{P}','{T}','Пн 16:00') returning id").stdout.splitlines()[0]
    self.assertNotEqual(self.decide(b,ok=False).returncode,0)
    self.decide(b,'declined')
if __name__=='__main__':unittest.main()
