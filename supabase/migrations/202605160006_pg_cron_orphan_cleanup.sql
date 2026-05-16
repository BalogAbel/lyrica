create extension if not exists pg_cron;

select cron.schedule(
  'cleanup-orphan-auth-users',
  '0 * * * *',
  $cron$
    delete from auth.users u
    where u.created_at < now() - interval '24 hours'
      and not exists (
        select 1
        from public.memberships m
        where m.user_id = u.id
          and m.status = 'active'
      )
  $cron$
);
