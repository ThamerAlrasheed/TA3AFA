begin;

create table if not exists public.user_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  token text not null,
  platform text not null default 'ios'
    check (platform in ('ios', 'android', 'web')),
  environment text not null
    check (environment in ('sandbox', 'production')),
  device_id text,
  app_version text,
  language text not null default 'en'
    check (language in ('en', 'ar')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (user_id, token, environment)
);

create index if not exists user_push_tokens_user_id_idx
  on public.user_push_tokens (user_id);

create index if not exists user_push_tokens_is_active_idx
  on public.user_push_tokens (is_active);

create index if not exists user_push_tokens_environment_idx
  on public.user_push_tokens (environment);

alter table public.user_push_tokens
  add column if not exists language text not null default 'en'
    check (language in ('en', 'ar'));

create or replace function public.set_user_push_tokens_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  new.last_seen_at = now();
  return new;
end;
$$;

drop trigger if exists user_push_tokens_set_updated_at on public.user_push_tokens;
create trigger user_push_tokens_set_updated_at
  before update on public.user_push_tokens
  for each row
  execute function public.set_user_push_tokens_updated_at();

alter table public.user_push_tokens enable row level security;

grant select, insert, update, delete on public.user_push_tokens to authenticated;
grant all on public.user_push_tokens to service_role;

drop policy if exists "Users can read own push tokens" on public.user_push_tokens;
create policy "Users can read own push tokens"
  on public.user_push_tokens
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "Users can insert own push tokens" on public.user_push_tokens;
create policy "Users can insert own push tokens"
  on public.user_push_tokens
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "Users can update own push tokens" on public.user_push_tokens;
create policy "Users can update own push tokens"
  on public.user_push_tokens
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "Users can delete own push tokens" on public.user_push_tokens;
create policy "Users can delete own push tokens"
  on public.user_push_tokens
  for delete
  to authenticated
  using (user_id = auth.uid());

commit;
