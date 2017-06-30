-- 1 up
create table if not exists "songs" (
  id serial primary key,
  title text not null,
  artist text not null,
  album text not null default '',
  track smallint,
  source text not null,
  duration interval minute to second not null,
  unique ("artist","album","title","track")
);
create index if not exists "artist_title" on "songs" ("artist","title");
create index if not exists "title" on "songs" ("title");
create index if not exists "source" on "songs" ("source");
create index if not exists "songtext" on "songs" using gin (to_tsvector('english', title || ' ' || artist || ' ' || album));

--1 down
drop table if exists "songs";

--2 up
create index if not exists "songtext" on "songs" using gin (to_tsvector('english', title || ' ' || artist || ' ' || album));

