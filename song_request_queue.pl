#!/usr/bin/env perl

use 5.020;
use Mojo::JSON::MaybeXS;
use Mojolicious::Lite;
use Crypt::Eksblowfish::Bcrypt qw(en_base64 bcrypt);
use Digest::MD5 qw(md5 md5_hex);
use List::Util ();
use Mojo::JSON qw(decode_json true false);
use Mojo::Pg;
use Syntax::Keyword::Try;
use Text::CSV 'csv';
use Text::Unidecode;
use Time::HiRes;
use Time::Seconds;
use experimental 'signatures';

plugin 'Config';

app->secrets(app->config->{secrets}) if app->config->{secrets};

app->sessions->default_expiration(ONE_WEEK);

helper pg => sub ($c) { state $pg = Mojo::Pg->new($c->config('pg')) };

my $migrations_file = app->home->child('song_request_queue.sql');
app->pg->auto_migrate(1)->migrations->name('song_request_queue')->from_file($migrations_file);

helper normalize_duration => sub ($c, $duration) {
  my @duration_segments = split /:/, ($duration // '');
  my $seconds = pop(@duration_segments) // 0;
  my $minutes = pop(@duration_segments) // 0;
  my $hours = pop(@duration_segments) // 0;
  if ($seconds > 60) {
    $minutes += int($seconds / 60);
    $seconds %= 60;
  }
  if ($minutes > 60) {
    $hours += int($minutes / 60);
    $minutes %= 60;
  }
  return sprintf '%02d:%02d:%02d', $hours, $minutes, $seconds;
};

helper hash_password => sub ($c, $password, $username) {
  my $remote_address = $c->tx->remote_address // '127.0.0.1';
  my $salt = en_base64 md5 join '$', $username // '', \my $dummy, Time::HiRes::time, $remote_address;
  my $hash = bcrypt $password, sprintf '$2a$08$%s', $salt;
  return $hash;
};

helper user_details => sub ($c, $user_id) {
  return $c->pg->db->select('users', [qw(username is_admin is_mod)],
    {id => $user_id})->hashes->first;
};

helper add_user => sub ($c, $username, $is_mod) {
  my $remote_address = $c->tx->remote_address // '127.0.0.1';
  my $code = uc md5_hex join '$', $username, \my $dummy, Time::HiRes::time, $remote_address;
  my $created = $c->pg->db->insert('users', {
    username => $username,
    is_mod => $is_mod,
    password_reset_code => \[q{decode(?, 'hex')}, $code],
  }, {returning => ['id']})->arrays->first;
  return undef unless defined $created;
  return {user_id => $created->[0], reset_code => $code};
};

helper valid_bot_key => sub ($c, $bot_key) {
  return 1 if defined $bot_key
    and List::Util::any { $_ eq $bot_key } @{$c->config('bot_keys') // []};
  return 0;
};

helper check_user_password => sub ($c, $username, $password) {
  my $user = $c->pg->db->select('users', [qw(id password_hash)],
    {username => $username})->hashes->first // return undef;
  return $user->{id} if bcrypt($password, $user->{password_hash}) eq $user->{password_hash};
  return undef;
};

helper check_user_reset_code => sub ($c, $username, $code) {
    my $user = $c->pg->db->select('users', ['id'], {
      username => $username,
      password_reset_code => {'=' => \[q{decode(?, 'hex')}, $code]}
    })->arrays->first // return undef;
    return $user->[0];
};

helper set_user_password => sub ($c, $user_id, $password, $username) {
  my $hash = $c->hash_password($password, $username);
  return $c->pg->db->update('users', {
    password_hash => $hash,
    password_reset_code => undef,
  }, {id => $user_id})->rows;
};

helper update_last_login => sub ($c, $user_id) {
  $c->pg->db->update('users', {last_login_at => \['now()']}, {id => $user_id});
};

helper import_from_csv => sub ($c, $file) {
  my $songs = csv(in => $file, encoding => 'UTF-8', detect_bom => 1)
    or die Text::CSV->error_diag;
  $_ = {
    title    => $_->{'song title'},
    artist   => $_->{artist},
    album    => $_->{'album name'},
    track    => $_->{'track #'},
    genre    => $_->{genre},
    source   => $_->{source},
    duration => $_->{duration},
  } for @$songs;
  $c->import_songs($songs);
};

helper import_from_json => sub ($c, $file) {
  $file =~ s/,(?=\s*]\s*\z)//;
  my $songs = decode_json $file;
  $_ = {
    title    => $_->{songName},
    artist   => $_->{artistName},
    album    => $_->{albumName},
    track    => undef,
    genre    => $_->{genreName},
    source   => $_->{charterName},
    duration => ($_->{songLength} / 1000),
  } for @$songs;
  $c->import_songs($songs);
};

helper song_for_insert => sub ($c, $details) {
  my %song;
  $song{$_} = $details->{$_}
    for grep { defined $details->{$_} } qw(title artist album genre source);
  $song{"${_}_ascii"} = unidecode $details->{$_}
    for grep { defined $details->{$_} } qw(title artist album);
  $song{duration} = $c->normalize_duration($details->{duration})
    if defined $details->{duration};
  $song{track} = int $details->{track} if defined $details->{track};
  return \%song;
};

helper import_songs => sub ($c, $songs) {
  my $db = $c->pg->db;
  my $tx = $db->begin;
  $db->insert('songs', $c->song_for_insert($_),
    {on_conflict => \['("artist","album","title","source",coalesce("track",0)) DO UPDATE
    SET "genre"="excluded"."genre", "duration"="excluded"."duration"']}) for @$songs;
  $tx->commit;
  return 1;
};

helper add_song => sub ($c, $details) {
  return $c->pg->db->insert('songs', $c->song_for_insert($details),
    {returning => 'id'})->arrays->first->[0];
};

helper update_song => sub ($c, $song_id, $details) {
  return $c->pg->db->update('songs', $c->song_for_insert($details),
    {id => $song_id})->rows;
};

helper delete_song => sub ($c, $song_id) {
  my $deleted = $c->pg->db->delete('songs', {id => $song_id},
    {returning => 'title'})->arrays->first;
  return defined $deleted ? $deleted->[0] : undef;
};

helper clear_songs => sub ($c) {
  return $c->pg->db->query('TRUNCATE TABLE "songs" CASCADE')->rows;
};

my @song_details_cols = qw(id title artist album track genre source duration);

helper search_songs => sub ($c, $search) {
  my $select = join ', ', map { qq{"$_"} } @song_details_cols;
  my @terms = map { "'$_':*" } map { quotemeta } split ' ', $search =~ tr[/][ ]r;
  my $and_search = join ' & ', @terms;
  my $query = "SELECT $select, " . <<'EOQ';
ts_rank_cd(songtext, to_tsquery('english_nostop', $1), 1) AS "rank"
FROM "songs" WHERE songtext @@ to_tsquery('english_nostop', $1)
ORDER BY "rank" DESC, "artist", "album", "track", "title", "source"
EOQ
  my $results = $c->pg->db->query($query, $and_search)->hashes;
  return $results if @$results;
  
  my $or_search = join ' | ', @terms;
  $query = "SELECT $select, " . <<'EOQ';
ts_rank_cd(songtext_withstop, to_tsquery('english', $1), 1) AS "rank"
FROM "songs" WHERE songtext_withstop @@ to_tsquery('english', $1)
ORDER BY "rank" DESC, "artist", "album", "track", "title", "source"
EOQ
  return $c->pg->db->query($query, $or_search)->hashes;
};

helper song_details => sub ($c, $song_id) {
  return $c->pg->db->select('songs', \@song_details_cols,
    {id => $song_id})->hashes->first;
};

helper all_song_details => sub ($c, $sort_by = 'artist', $sort_dir = 'asc') {
  my @sorts = ($sort_by, grep { $_ ne $sort_by } qw(artist album track title source));
  return $c->pg->db->select('songs', \@song_details_cols, undef,
    {-$sort_dir => \@sorts})->hashes;
};

helper queue_details => sub ($c) {
  my @from = ('queue', [-left => 'songs', 'songs.id' => 'queue.song_id']);
  my @select = (['songs.id' => 'song_id'],
    (map { "songs.$_" } @song_details_cols),
    (map { "queue.$_" } qw(requested_by requested_at raw_request position)));
  return $c->pg->db->select(\@from, \@select, undef, 'queue.position')->hashes;
};

helper queue_song => sub ($c, $song_id, $requested_by, $raw_request) {
  return $c->pg->db->insert('queue', {
    song_id => $song_id,
    requested_by => $requested_by,
    raw_request => $raw_request,
    position => \['COALESCE((SELECT MAX("position") FROM "queue"),0)+1'],
  })->rows;
};

helper unqueue_song => sub ($c, $position) {
  my $deleted = $c->pg->db->delete('queue', {position => $position},
    {returning => 'song_id'})->arrays->first;
  return defined $deleted ? $deleted->[0] : undef;
};

helper reorder_queue => sub ($c, $position, $direction) {
  $c->pg->db->select('queue', ['id'],
    {position => $position})->arrays->first // return 0;
  my ($swap_to, $compare) = (defined $direction and $direction eq 'up')
    ? ('MAX("position")','<') : ('MIN("position")','>');
  my $swap_position = $c->pg->db->select('queue', [\$swap_to],
    {position => {$compare => $position}})->arrays->first // return 0;
  $swap_position = $swap_position->[0] // return 0;
  $c->pg->db->update('queue',
    {position => \['CASE WHEN "position" = ? THEN ?::integer ELSE ?::integer END',
      $position, $swap_position, $position]},
    {position => [$position, $swap_position]});
  return 1;
};

helper set_queued_song => sub ($c, $position, $song_id) {
  return $c->pg->db->update('queue', {song_id => $song_id},
    {position => $position})->rows;
};

helper set_requested_by => sub ($c, $position, $requested_by) {
  return $c->pg->db->update('queue', {requested_by => $requested_by},
    {position => $position})->rows;
};

helper clear_queue => sub ($c) {
  return $c->pg->db->query('TRUNCATE TABLE "queue"')->rows;
};

# Pages

under '/' => sub ($c) {
  my $user_id = $c->session->{user_id};
  if (defined $user_id and defined(my $details = $c->user_details($user_id))) {
    $c->stash(user_id => $user_id, username => $details->{username});
    $c->stash(is_admin => 1) if $details->{is_admin};
    $c->stash(is_mod => 1) if $details->{is_admin} or $details->{is_mod};
  }
  my $bot_key = $c->param('bot_key');
  if (defined $bot_key and $c->valid_bot_key($bot_key)) {
    $c->stash(is_bot => 1);
  }
  return 1;
};

get '/' => 'index';

my %allowed_sort = map { ($_ => 1) } qw(title artist album track genre source duration);
get '/browse' => sub ($c) {
  my $sort_by = $c->param('sort_by') // 'artist';
  $sort_by = 'artist' unless $allowed_sort{$sort_by};
  my $sort_dir = $c->param('sort_dir') // 'asc';
  $sort_dir = 'asc' unless $sort_dir eq 'desc';
  $c->render(
    songlist => $c->all_song_details($sort_by, $sort_dir),
    sort_by => $sort_by,
    sort_dir => $sort_dir,
  );
};

get '/admin' => sub ($c) {
  return $c->redirect_to('/login') unless $c->stash('is_admin');
  $c->render;
};

get '/login';

any '/logout' => sub ($c) {
  delete $c->session->{user_id};
  $c->session(expires => 1);
  $c->redirect_to('/');
};

get '/account' => sub ($c) {
  return $c->redirect_to('/login') unless $c->stash('user_id');
  $c->render;
};

get '/set_password';

# Public API

post '/api/login' => sub ($c) {
  my $username = $c->param('username');
  my $password = $c->param('password');
  return $c->render(json => {logged_in => false, error => 'Missing parameters'})
    unless length $username and length $password;
  
  my $user_id = $c->check_user_password($username, $password)
    // return $c->render(json => {logged_in => false, error => 'Login failed'});
  
  $c->update_last_login($user_id);
  $c->session->{user_id} = $user_id;
  
  $c->render(json => {logged_in => true});
};

post '/api/set_password' => sub ($c) {
  my $username = $c->param('username');
  my $code = $c->param('code');
  my $current = $c->param('current');
  my $password = $c->param('password');
  my $verify = $c->param('verify');
  
  return $c->render(json => {success => false, error => 'Missing parameters'})
    unless length $password and length $verify;
  return $c->render(json => {success => false, error => 'Passwords do not match'})
    unless $password eq $verify;
  
  my $user_id;
  if (length $username) {
    return $c->render(json => {success => false, error => 'Missing parameters'})
      unless length $code;
    return $c->render(json => {success => false, error => 'Unknown user or invalid code'})
      unless $code =~ m/\A([0-9a-f]{2})+\z/i;
    $user_id = $c->check_user_reset_code($username, $code)
      // return $c->render(json => {success => false, error => 'Unknown user or invalid code'});
  } elsif (!defined($username = $c->stash('username'))) {
    return $c->render(json => {success => false, error => 'Missing parameters'})
      if length $code;
    return $c->render(json => {success => false, error => 'You must be signed in to change your password'});
  } else {
    return $c->render(json => {success => false, error => 'Missing parameters'})
      unless length $current;
    $user_id = $c->check_user_password($username, $current)
      // return $c->render(json => {success => false, error => 'Unknown user or invalid password'});
  }
  
  my $updated = $c->set_user_password($user_id, $password, $username);
  return $c->render(json => {success => true}) if $updated > 0;
  $c->render(json => {success => false});
};

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

# Mod functions
group {
  under '/' => sub ($c) {
    return 1 if $c->stash('is_mod') or $c->stash('is_bot');
    $c->render(text => 'Access denied', status => 403);
    return 0;
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
      my $search_results;
      try { $search_results = $c->search_songs($search) } catch {
        $c->app->log->error($@);
        return $c->render(text => 'Internal error searching song database');
      }
      $song_details = $search_results->first;
      $song_id = $song_details->{id} if defined $song_details;
      $raw_request = $search;
    }
    
    my $requested_by = $c->param('requested_by') // $c->stash('username') // '';
    try { $c->queue_song($song_id, $requested_by, $raw_request) } catch {
      $c->app->log->error($@);
      return $c->render(text => 'Internal error adding song to queue');
    }
    my $response_title = defined $song_details ? "$song_details->{artist} - $song_details->{title}" : $raw_request;
    $c->render(text => "Added '$response_title' to queue (requested by $requested_by)");
  };
  
  post '/api/queue/:position' => sub ($c) {
    return $c->render(text => 'Access denied', status => 403) unless $c->stash('is_mod');
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
    return $c->render(text => 'Access denied', status => 403) unless $c->stash('is_mod');
    my $position = $c->param('position');
    my $deleted_id = $c->unqueue_song($position);
    return $c->render(text => "No song in position $position") unless defined $deleted_id;
    my $deleted_song = $c->song_details($deleted_id);
    $c->render(text => "Removed song '$deleted_song->{title}' from queue position $position");
  };
  
  del '/api/queue' => sub ($c) {
    return $c->render(text => 'Access denied', status => 403) unless $c->stash('is_mod');
    my $deleted = $c->clear_queue;
    $c->render(text => "Cleared queue (removed $deleted songs)");
  };
};

# Admin functions
group {
  under '/' => sub ($c) {
    return 1 if $c->stash('is_admin');
    $c->render(text => 'Access denied', status => 403);
    return 0;
  };
  
  post '/api/users' => sub ($c) {
    my $username = $c->param('username');
    return $c->render(json => {success => false, error => 'No username specified'})
      unless length $username;
    my $is_mod = $c->param('is_mod') ? 1 : 0;
    my $created_user = $c->add_user($username, $is_mod);
    return $c->render(json => {success => false}) unless defined $created_user;
    $c->render(json => {success => true, username => $username, reset_code => $created_user->{reset_code}});
  };
  
  post '/api/songs/import' => sub ($c) {
    my $upload = $c->req->upload('songlist');
    return $c->render(text => 'No songlist provided.') unless defined $upload;
    my $name = $upload->filename;
    my $contents = $upload->asset->slurp;
    if ($contents =~ m/^[\[\{]/ or $name =~ m/\.json$/) {
      $c->import_from_json($contents);
    } else {
      $c->import_from_csv(\$contents);
    }
    $c->render(text => "Import of $name successful.");
  };
  
  post '/api/songs' => sub ($c) {
    my $song_id = $c->add_song($c->req->body_params->to_hash);
    my $details = $c->song_details($song_id);
    $c->render(text => "Failed to add song") unless defined $details;
    $c->render(text => "Added song '$details->{title}'");
  };
  
  del '/api/songs' => sub ($c) {
    my $deleted = $c->clear_songs;
    $c->render(text => "Cleared songlist");
  };
  
  post '/api/songs/:song_id' => sub ($c) {
    my $song_id = $c->param('song_id');
    my $updated = $c->update_song($song_id, $c->req->body_params->to_hash);
    my $details = $c->song_details($song_id);
    $c->render(text => "Invalid song ID $song_id") unless defined $details;
    $c->render(text => "Updated song $song_id '$details->{title}'");
  };
  
  del '/api/songs/:song_id' => sub ($c) {
    my $song_id = $c->param('song_id');
    my $deleted_title = $c->delete_song($song_id);
    return $c->render(text => "Invalid song ID $song_id") unless defined $deleted_title;
    $c->render(text => "Deleted song $song_id '$deleted_title'");
  };
};

app->start;
