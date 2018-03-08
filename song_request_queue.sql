-- 1 up
create text search dictionary "english_stem_nostop" (
  template = snowball,
  language = english,
  stopwords = empty
);

create text search configuration "english_nostop" (copy = english);
alter text search configuration "english_nostop"
  alter mapping replace "english_stem" with "english_stem_nostop";

create or replace function "songs_update_songtext"() returns trigger as $$
begin
  "new"."songtext" :=
    setweight(to_tsvector('english_nostop',
      replace("new"."title",'/',' ') || ' ' ||
      replace("new"."title_ascii",'/',' ')), 'A') ||
    setweight(to_tsvector('english_nostop',
      replace("new"."artist",'/',' ') || ' ' ||
      replace("new"."artist_ascii",'/',' ')), 'B') ||
    setweight(to_tsvector('english_nostop',
      replace("new"."album",'/',' ') || ' ' ||
      replace("new"."album_ascii",'/',' ')), 'D');
  "new"."songtext_withstop" :=
    setweight(to_tsvector('english',
      replace("new"."title",'/',' ') || ' ' ||
      replace("new"."title_ascii",'/',' ')), 'A') ||
    setweight(to_tsvector('english',
      replace("new"."artist",'/',' ') || ' ' ||
      replace("new"."artist_ascii",'/',' ')), 'B') ||
    setweight(to_tsvector('english',
      replace("new"."album",'/',' ') || ' ' ||
      replace("new"."album_ascii",'/',' ')), 'D');
  return new;
end
$$ language plpgsql;

create table if not exists "users" (
  id serial primary key,
  username text not null unique,
  password_hash text not null default '',
  created_at timestamp with time zone default now(),
  last_login_at timestamp with time zone,
  password_reset_code bytea,
  is_admin bool not null default false,
  is_mod bool not null default false
);

create table if not exists "songs" (
  id serial primary key,
  title text not null,
  artist text not null,
  album text not null default '',
  track smallint,
  source text not null,
  duration interval hour to second not null,
  title_ascii text not null,
  artist_ascii text not null,
  album_ascii text not null default '',
  songtext tsvector not null,
  songtext_withstop tsvector not null,
  constraint "songs_artist_album_title_track_key" unique ("artist","album","title","track")
);
create index if not exists "songs_artist_title" on "songs" ("artist","title");
create index if not exists "songs_title" on "songs" ("title");
create index if not exists "songs_source" on "songs" ("source");
create index if not exists "songs_songtext" on "songs" using gin ("songtext");
create index if not exists "songs_songtext_withstop" on "songs" using gin ("songtext_withstop");

create trigger "songs_songtext_trigger" before insert or update on "songs"
  for each row execute procedure songs_update_songtext();

create table if not exists "queue" (
  id serial primary key,
  position integer not null unique deferrable,
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
drop function if exists "songs_update_songtext";
drop text search configuration if exists "english_nostop";
drop text search dictionary if exists "english_stem_nostop";

--2 up
alter table "queue"
  drop constraint "queue_position_key",
  add constraint "queue_position_key" unique ("position") deferrable;

--3 up
alter table "songs" drop constraint "songs_artist_album_title_track_key";
create unique index "songs_artist_album_title_track_key" on "songs" ("artist","album","title",coalesce("track",0));

--3 down
drop index "songs_artist_album_title_track_key";
alter table "songs" add constraint "songs_artist_album_title_track_key" unique ("artist","album","title","track");

--4 up
drop index "songs_artist_album_title_track_key";
create unique index "songs_artist_album_title_source_track_key" on "songs" ("artist","album","title","source",coalesce("track",0));

create or replace function "songs_update_songtext"() returns trigger as $$
begin
  "new"."songtext" :=
    setweight(to_tsvector('english_nostop', concat_ws(' ',
      replace("new"."title",'/',' '),
      replace("new"."title_ascii",'/',' '))), 'A') ||
    setweight(to_tsvector('english_nostop', concat_ws(' ',
      replace("new"."artist",'/',' '),
      replace("new"."artist_ascii",'/',' '))), 'B') ||
    setweight(to_tsvector('english_nostop', concat_ws(' ',
      replace("new"."album",'/',' '),
      replace("new"."album_ascii",'/',' '),
      replace("new"."source",'/',' '))), 'D');
  "new"."songtext_withstop" :=
    setweight(to_tsvector('english', concat_ws(' ',
      replace("new"."title",'/',' '),
      replace("new"."title_ascii",'/',' '))), 'A') ||
    setweight(to_tsvector('english', concat_ws(' ',
      replace("new"."artist",'/',' '),
      replace("new"."artist_ascii",'/',' '))), 'B') ||
    setweight(to_tsvector('english', concat_ws(' ',
      replace("new"."album",'/',' '),
      replace("new"."album_ascii",'/',' '),
      replace("new"."source",'/',' '))), 'D');
  return new;
end
$$ language plpgsql;

--4 down
drop index "songs_artist_album_title_source_track_key";
create unique index "songs_artist_album_title_track_key" on "songs" ("artist","album","title",coalesce("track",0));

--5 up
alter table "songs" add "genre" text not null default '';
create index "songs_genre" on "songs" ("genre");

--5 down
drop index "songs_genre";
alter table "songs" drop "genre";
