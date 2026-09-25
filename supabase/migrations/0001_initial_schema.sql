-- RELIO v0.5 cloud schema. Drift remains the offline source of truth.
create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.devices (
  device_id text primary key,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null default '',
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.conversations (
  id uuid primary key,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table public.messages (
  id uuid primary key,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete restrict,
  sender_device_id text,
  message_type text not null check (message_type in ('text', 'image', 'video', 'location', 'system')),
  content text,
  delivery_status text not null default 'pending' check (delivery_status in ('pending', 'nearbySent', 'delivered', 'synced', 'failed')),
  is_outgoing boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.attachments (
  id uuid primary key,
  message_id uuid not null unique references public.messages(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null unique,
  media_type text not null check (media_type in ('image', 'video')),
  mime_type text not null,
  file_name text not null,
  byte_size bigint not null check (byte_size >= 0),
  transfer_status text not null default 'pending' check (transfer_status in ('pending', 'preparing', 'transferring', 'received', 'completed', 'failed', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.sos_events (
  id uuid primary key,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  owner_device_id text not null,
  message text,
  latitude double precision,
  longitude double precision,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index messages_conversation_created_idx on public.messages(conversation_id, created_at);
create index conversation_members_user_idx on public.conversation_members(user_id);
create index sos_events_owner_active_idx on public.sos_events(owner_user_id, is_active);
