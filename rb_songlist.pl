#!/usr/bin/env perl

use strict;
use warnings;
use Mojo::JSON::MaybeXS;
use Mojolicious::Lite;
use Crypt::Eksblowfish::Bcrypt qw(en_base64 bcrypt);
use Digest::MD5 'md5';
use List::Util ();
use Mojo::Pg;
use Text::CSV 'csv';
use Time::Seconds;
use experimental 'signatures';

plugin 'Config';

app->secrets(app->config->{secrets}) if app->config->{secrets};

app->sessions->default_expiration(ONE_WEEK);

helper pg => sub ($c) { state $pg = Mojo::Pg->new($c->config('pg')) };

my $migrations_file = app->home->child('rb_songlist.sql');
app->pg->auto_migrate(1)->migrations->name('rb_songlist')->from_file($migrations_file);

helper normalize_duration => sub ($c, $duration) {
  my @duration_segments = split /:/, ($duration // '');
  my $seconds = pop @duration_segments;
  my $minutes = pop @duration_segments;
  my $hours = pop @duration_segments;
  return sprintf '%02d:%02d:%02d', $hours // 0, $minutes // 0, $seconds // 0;
};

helper hash_password => sub ($c, $password, $username) {
  my $remote_address = $c->tx->remote_address // '127.0.0.1';
  my $salt = en_base64 md5 join '$', $username, \my $dummy, time, $remote_address;
  my $hash = bcrypt $password, sprintf '$2a$08$%s', $salt;
  return $hash;
};

helper user_details => sub ($c, $user_id) {
  my $query = 'SELECT true AS "is_admin", "username" FROM "users" WHERE "id"=$1';
  return $c->pg->db->query($query, $user_id)->hashes->first;
};

helper valid_bot_key => sub ($c, $bot_key) {
  return 1 if defined $bot_key
    and List::Util::any { $_ eq $bot_key } @{$c->config('bot_keys') // []};
  return 0;
};

helper import_from_csv => sub ($c, $file) {
  my $songs = csv(in => $file, encoding => 'UTF-8', detect_bom => 1)
    or die Text::CSV->error_diag;
  my $db = $c->pg->db;
  my $tx = $db->begin;
  foreach my $song (@$songs) {
    $song->{duration} = $c->normalize_duration($song->{duration});
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

helper add_song => sub ($c, $details) {
  my %properties;
  $properties{$_} = $details->{$_} for qw(title artist album track source duration);
  my $inserted = $c->pg->db->insert('songs', \%properties, {returning => 'id'})->arrays->first;
  return $inserted->[0];
};

helper update_song => sub ($c, $song_id, $details) {
  my %updates;
  $updates{$_} = $details->{$_} for grep { exists $details->{$_} }
    qw(title artist album track source duration);
  $updates{duration} = $c->normalize_duration($updates{duration});
  return $c->pg->db->update('songs', \%updates, {id => $song_id})->rows;
};

helper delete_song => sub ($c, $song_id) {
  my $query = 'DELETE FROM "songs" WHERE "id"=$1 RETURNING "title"';
  my $deleted = $c->pg->db->query($query, $song_id)->arrays->first;
  return defined $deleted ? $deleted->[0] : undef;
};

helper clear_songs => sub ($c) {
  my $query = 'TRUNCATE TABLE "songs" CASCADE';
  return $c->pg->db->query($query)->rows;
};

helper queue_details => sub ($c) {
  my $query = <<'EOQ';
SELECT "songs"."id" AS "song_id", "title", "artist", "album", "track",
"source", "duration", "requested_by", "requested_at", "raw_request", "position"
FROM "queue" LEFT JOIN "songs" ON "songs"."id"="queue"."song_id"
ORDER BY "queue"."position"
EOQ
  return $c->pg->db->query($query)->hashes;
};

helper queue_song => sub ($c, $song_id, $requested_by, $raw_request) {
  my $query = <<'EOQ';
INSERT INTO "queue" ("song_id","requested_by","raw_request","position")
VALUES ($1,$2,$3,COALESCE((SELECT MAX("position") FROM "queue"),0)+1)
EOQ
  return $c->pg->db->query($query, $song_id, $requested_by, $raw_request)->rows;
};

helper unqueue_song => sub ($c, $position) {
  my $query = 'DELETE FROM "queue" WHERE "position"=$1 RETURNING "song_id"';
  my $deleted = $c->pg->db->query($query, $position)->arrays->first;
  return defined $deleted ? $deleted->[0] : undef;
};

helper reorder_queue => sub ($c, $position, $direction) {
  my $query = 'SELECT "id" FROM "queue" WHERE "position"=$1';
  $c->pg->db->query($query, $position)->arrays->first // return 0;
  if (defined $direction and $direction eq 'up') {
    $query = 'SELECT MAX("position") FROM "queue" WHERE "position"<$1';
  } else {
    $query = 'SELECT MIN("position") FROM "queue" WHERE "position">$1';
  }
  my $swap_position = $c->pg->db->query($query, $position)->arrays->first // return 0;
  $swap_position = $swap_position->[0] // return 0;
  $query = <<'EOQ';
UPDATE "queue" SET "position" = CASE WHEN "position" = $1 THEN $2 ELSE $1 END
WHERE "position" IN ($1,$2)
EOQ
  $c->pg->db->query($query, $position, $swap_position);
  return 1;
};

helper set_queued_song => sub ($c, $position, $song_id) {
  my $query = 'UPDATE "queue" SET "song_id"=$1 WHERE "position"=$2';
  return $c->pg->db->query($query, $song_id, $position)->rows;
};

helper set_requested_by => sub ($c, $position, $requested_by) {
  my $query = 'UPDATE "queue" SET "requested_by"=$1 WHERE "position"=$2';
  return $c->pg->db->query($query, $requested_by, $position)->rows;
};

helper clear_queue => sub ($c) {
  my $query = 'DELETE FROM "queue" WHERE true';
  return $c->pg->db->query($query)->rows;
};

helper search_songs => sub ($c, $search) {
  my $query = <<'EOQ';
SELECT * FROM "songs"
WHERE to_tsvector('english', title || ' ' || artist || ' ' || album) @@ to_tsquery($1)
EOQ
  return $c->pg->db->query($query, $search)->hashes;
};

helper song_details => sub ($c, $song_id) {
  my $query = 'SELECT * FROM "songs" WHERE "id"=$1';
  return $c->pg->db->query($query, $song_id)->hashes->first;
};

# Pages

under '/' => sub ($c) {
  my $user_id = $c->session->{user_id};
  if (defined $user_id and defined(my $details = $c->user_details($user_id))) {
    $c->stash(user_id => $user_id, username => $details->{username});
    $c->stash(is_admin => 1) if $details->{is_admin};
  }
  my $bot_key = $c->param('bot_key');
  if (defined $bot_key and $c->valid_bot_key($bot_key)) {
    $c->stash(is_bot => 1);
  }
  return 1;
};

get '/' => 'index';

get '/admin' => sub ($c) {
  return $c->redirect_to('/login') unless $c->stash('is_admin');
  $c->render;
};

get '/login';
post '/login' => sub ($c) {
  my $username = $c->param('username');
  my $password = $c->param('password');
  return $c->render(text => 'Missing parameters')
    unless defined $username and defined $password;
  
  my $query = <<'EOQ';
SELECT "id", "username", "password_hash" FROM "users" WHERE "username"=$1
EOQ
  my $user = $c->pg->db->query($query, $username)->hashes->first;
  return $c->render(text => 'Login failed') unless defined $user
    and bcrypt($password, $user->{password_hash}) eq $user->{password_hash};
  
  $c->session->{user_id} = $user->{id};
  $c->session->{username} = $user->{username};
  $c->redirect_to('/');
};
any '/logout' => sub ($c) {
  delete @{$c->session}{'user_id','username'};
  $c->session(expires => 1);
  $c->redirect_to('/');
};

get '/set_password';
post '/set_password' => sub ($c) {
  my $username = $c->param('username');
  my $code = $c->param('code');
  my $password = $c->param('password');
  my $verify = $c->param('verify');
  
  return $c->render(text => 'Missing parameters')
    unless defined $username and defined $code and defined $password and defined $verify;
  return $c->render(text => 'Passwords do not match') unless $password eq $verify;
  my $query = <<'EOQ';
SELECT "id" FROM "users" WHERE "username"=$1 AND "password_reset_code"=decode($2, 'hex')
EOQ
  my $user_exists = $c->pg->db->query($query, $username, $code)->arrays->first;
  return $c->render(text => 'Unknown user or invalid code') unless defined $user_exists;
  
  my $hash = $c->hash_password($password, $username);
  $query = <<'EOQ';
UPDATE "users" SET "password_hash"=$1, "password_reset_code"=NULL
WHERE "username"=$2 AND "password_reset_code"=decode($3, 'hex')
EOQ
  my $updated = $c->pg->db->query($query, $hash, $username, $code)->rows;
  return $c->render(text => 'Password set successfully') if $updated > 0;
  $c->render(text => 'Password was not set');
};

# Public API

get '/api/songs/search' => sub ($c) {
  my $search = $c->param('query') // '';
  return $c->render(json => []) unless length $search;
  my $results = $c->search_songs($search);
  $c->render(json => $results);
};

get '/api/songs/:song_id' => sub ($c) {
  my $song_id = $c->param('song_id');
  my $details = $c->song_details($song_id);
  $c->render(json => $details);
};

get '/api/queue' => sub ($c) {
  my $queue_details = $c->queue_details;
  $c->render(json => $queue_details);
};

# Admin functions
group {
  under '/' => sub ($c) {
    return 1 if $c->stash('is_admin') or $c->stash('is_bot');
    $c->render(text => 'Access denied', status => 403);
    return 0;
  };
  
  post '/api/songs/import' => sub ($c) {
    return $c->render(text => 'Access denied', status => 403) unless $c->stash('is_admin');
    my $upload = $c->req->upload('songlist');
    return $c->render(text => 'No songlist provided.') unless defined $upload;
    my $name = $upload->filename;
    $c->import_from_csv(\($upload->asset->slurp));
    $c->render(text => "Import of $name successful.");
  };
  
  post '/api/songs' => sub ($c) {
    return $c->render(text => 'Access denied', status => 403) unless $c->stash('is_admin');
    my $song_id = $c->add_song($c->req->body_params->to_hash);
    my $details = $c->song_details($song_id);
    $c->render(text => "Failed to add song") unless defined $details;
    $c->render(text => "Added song '$details->{title}'");
  };
  
  del '/api/songs' => sub ($c) {
    return $c->render(text => 'Access denied', status => 403) unless $c->stash('is_admin');
    my $deleted = $c->clear_songs;
    $c->render(text => "Cleared songlist");
  };
  
  post '/api/songs/:song_id' => sub ($c) {
    return $c->render(text => 'Access denied', status => 403) unless $c->stash('is_admin');
    my $song_id = $c->param('song_id');
    my $updated = $c->update_song($song_id, $c->req->body_params->to_hash);
    my $details = $c->song_details($song_id);
    $c->render(text => "Invalid song ID $song_id") unless defined $details;
    $c->render(text => "Updated song $song_id '$details->{title}'");
  };
  
  del '/api/songs/:song_id' => sub ($c) {
    return $c->render(text => 'Access denied', status => 403) unless $c->stash('is_admin');
    my $song_id = $c->param('song_id');
    my $deleted_title = $c->delete_song($song_id);
    return $c->render(text => "Invalid song ID $song_id") unless defined $deleted_title;
    $c->render(text => "Deleted song $song_id '$deleted_title'");
  };
  
  any '/api/queue/add' => sub ($c) {
    my $song_id = $c->param('song_id');
    my $song_details;
    my $raw_request;
    if (defined $song_id) {
      $song_details = $c->song_details($song_id);
      return $c->render(text => "Invalid song ID $song_id") unless defined $song_details;
    } else {
      my $search = $c->param('query') // '';
      return $c->render(text => 'No song ID or search query provided.') unless length $search;
      my $search_results = $c->search_songs($search);
      $song_details = $search_results->first;
      $song_id = $song_details->{id} if defined $song_details;
      $raw_request = $search;
    }
    
    my $requested_by = $c->param('requested_by') // $c->stash('username') // '';
    $c->queue_song($song_id, $requested_by, $raw_request);
    my $response_title = defined $song_details ? $song_details->{title} : $raw_request;
    $c->render(text => "Added '$response_title' to queue (requested by $requested_by)");
  };
  
  post '/api/queue/:position' => sub ($c) {
    return $c->render(text => 'Access denied', status => 403) unless $c->stash('is_admin');
    my $position = $c->param('position');
    
    my $reorder = $c->param('reorder');
    if (defined $reorder) {
      return $c->render(text => "Don't know how to reorder position to $reorder")
        unless $reorder eq 'up' or $reorder eq 'down';
      my $reordered = $c->reorder_queue($position, $reorder);
      return $c->render(text => "Cannot reorder position $position $reorder") unless $reordered;
      return $c->render(text => "Reordered position $position $reorder");
    }
    
    my $song_id = $c->param('song_id');
    if (defined $song_id) {
      my $song_details = $c->song_details($song_id);
      return $c->render(text => "Invalid song ID $song_id") unless defined $song_details;
      $c->set_queued_song($position, $song_id);
      return $c->render(text => "Set queued song $position to '$song_details->{title}'");
    }
    
    my $requested_by = $c->param('requested_by');
    if (defined $requested_by) {
      my $updated = $c->set_requested_by($position, $requested_by);
      return $c->render(text => "Unknown queue position $position") unless $updated;
      return $c->render(text => "Set queue position $position requested by $requested_by");
    }
    
    return $c->render(text => "No changes");
  };
  
  del '/api/queue/:position' => sub ($c) {
    return $c->render(text => 'Access denied', status => 403) unless $c->stash('is_admin');
    my $position = $c->param('position');
    my $deleted_id = $c->unqueue_song($position);
    return $c->render(text => "No song in position $position") unless defined $deleted_id;
    my $deleted_song = $c->song_details($deleted_id);
    $c->render(text => "Removed song '$deleted_song->{title}' from queue position $position");
  };
  
  del '/api/queue' => sub ($c) {
    return $c->render(text => 'Access denied', status => 403) unless $c->stash('is_admin');
    my $deleted = $c->clear_queue;
    $c->render(text => "Cleared queue (removed $deleted songs)");
  };
};

app->start;
