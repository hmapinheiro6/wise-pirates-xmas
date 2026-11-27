-- Wise Pirates Christmas Plunder: one locked-down table, reachable only through three functions.
create table public.xmas_crew (
  id uuid primary key default gen_random_uuid(),
  edit_token uuid not null,
  name text not null check (char_length(name) between 1 and 40),
  lunch text[] not null default '{}',
  dinner text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.xmas_crew enable row level security;
revoke all on table public.xmas_crew from anon, authenticated;

-- Everyone may read names and dates (never the edit tokens).
create function public.crew_list()
returns table (id uuid, name text, lunch text[], dinner text[])
language sql stable security definer set search_path = ''
as $$ select c.id, c.name, c.lunch, c.dinner from public.xmas_crew c order by c.created_at $$;

-- Create a row (p_id null) or update your own row (id + matching token).
create function public.crew_upsert(p_id uuid, p_token uuid, p_name text, p_lunch text[], p_dinner text[])
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_name text := btrim(coalesce(p_name, ''));
  v_lunch text[] := coalesce(p_lunch, '{}');
  v_dinner text[] := coalesce(p_dinner, '{}');
begin
  if p_token is null then raise exception 'token required'; end if;
  if char_length(v_name) < 1 or char_length(v_name) > 40 then raise exception 'bad name'; end if;
  if coalesce(array_length(v_lunch, 1), 0) > 24 or coalesce(array_length(v_dinner, 1), 0) > 24 then raise exception 'too many days'; end if;
  if exists (select 1 from unnest(v_lunch || v_dinner) d where d !~ '^(0[1-9]|1[0-9]|2[0-4])$') then raise exception 'bad day'; end if;
  if p_id is null then
    if (select count(*) from public.xmas_crew) >= 150 then raise exception 'ship full'; end if;
    insert into public.xmas_crew (edit_token, name, lunch, dinner)
    values (p_token, v_name, v_lunch, v_dinner) returning id into v_id;
  else
    update public.xmas_crew
       set name = v_name, lunch = v_lunch, dinner = v_dinner, updated_at = now()
     where id = p_id and edit_token = p_token
    returning id into v_id;
    if v_id is null then raise exception 'not yours'; end if;
  end if;
  return v_id;
end $$;

-- Delete your own row.
create function public.crew_delete(p_id uuid, p_token uuid)
returns void
language sql security definer set search_path = ''
as $$ delete from public.xmas_crew where id = p_id and edit_token = p_token $$;

revoke execute on function public.crew_list(), public.crew_upsert(uuid, uuid, text, text[], text[]), public.crew_delete(uuid, uuid) from public;
grant execute on function public.crew_list(), public.crew_upsert(uuid, uuid, text, text[], text[]), public.crew_delete(uuid, uuid) to anon, authenticated;
