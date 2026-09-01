begin;

-- Reset only invitations that have not been accepted yet. Authentication users,
-- accepted invitation history, and existing store memberships are unchanged.
delete from public.store_invitations
where status = 'pending';

commit;

