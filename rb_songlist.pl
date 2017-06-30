#!/usr/bin/env perl

use strict;
use warnings;
use Mojo::JSON::MaybeXS;
use Mojolicious::Lite;
use List::Util ();
use Mojo::Pg;
use Text::CSV 'csv';
use experimental 'signatures';

plugin 'Config';

helper pg => sub ($c) { state $pg = Mojo::Pg->new($c->config('pg')) };

helper import_from_csv => sub ($c, $file) {
  my $songs = csv(in => $file, encoding => 'UTF-8', detect_bom => 1)
    or die Text::CSV->error_diag;
  my $db = $c->pg->db;
  my $tx = $db->begin;
  foreach my $song (@$songs) {
    my $query = <<'EOQ';
INSERT INTO "songs" ("title","artist","album","track","source","duration")
VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING
EOQ
    my @params = @$song{'song title','artist','album name','track #','source','duration'};
    $db->query($query, @params);
  }
  $tx->commit;
  return 1;
};

my $migrations_file = app->home->child('rb_songlist.sql');
app->pg->auto_migrate(1)->migrations->name('rb_songlist')->from_file($migrations_file);

get '/' => 'index';

post '/import_songlist' => sub ($c) {
  my $upload = $c->req->upload('songlist');
  return $c->render(text => 'No songlist provided.') unless defined $upload;
  my $name = $upload->filename;
  $c->import_from_csv(\($upload->asset->slurp));
  $c->render(text => "Import of $name successful.");
};

get '/find_song' => sub ($c) {
  my $search = $c->param('query') // '';
  $c->render(json => []) unless length $search;
  my $query = <<'EOQ';
SELECT * FROM "songs" WHERE to_tsvector('english', title || ' ' || artist || ' ' || album) @@ to_tsquery($1)
EOQ
  my $results = $c->pg->db->query($query, $search)->hashes;
  $c->render(json => $results);
};

app->start;
