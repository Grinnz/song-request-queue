-- 1 up
create table if not exists "users" (
  id serial primary key,
  username text not null unique,
  password_hash text not null default '',
  last_login_at timestamp with time zone,
  password_reset_code bytea
);

create table if not exists "songs" (
  id serial primary key,
  title text not null,
  artist text not null,
  album text not null default '',
  track smallint,
  source text not null,
  duration interval hour to second not null,
  unique ("artist","album","title","track")
);
create index if not exists "songs_artist_title" on "songs" ("artist","title");
create index if not exists "songs_title" on "songs" ("title");
create index if not exists "songs_source" on "songs" ("source");
create index if not exists "songs_songtext" on "songs" using gin (to_tsvector('english', title || ' ' || artist || ' ' || album));

create table if not exists "queue" (
  id serial primary key,
  position integer not null unique,
  song_id integer null,
  requested_by text not null default '',
  requested_at timestamp with time zone default now(),
  raw_request text null,
  foreign key ("song_id") references "songs" ("id") on delete set null on update cascade
);

--1 down
drop table if exists "queue";
drop table if exists "songs";
drop table if exists "users";
