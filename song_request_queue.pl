#!/usr/bin/env perl

use 5.020;
use Mojolicious::Lite -signatures;
use Crypt::Passphrase;
use Digest::MD5 qw(md5_hex);
use Math::Random::Secure 'rand';
use Mojo::Asset::Memory;
use Mojo::JSON qw(decode_json encode_json true false);
use Mojo::Pg;
use Mojo::Util 'trim';
use Spreadsheet::ParseXLSX;
use Syntax::Keyword::Try;
use Text::CSV 'csv';
use Text::Unidecode;
use Time::HiRes;
use Time::Seconds;

plugin 'Config';

app->log->with_roles('Mojo::Log::Role::Clearable')->path(app->config->{logfile}) if app->config->{logfile};

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
  if ($seconds >= 60) {
    $minutes += int($seconds / 60);
    $seconds %= 60;
  }
  if ($minutes >= 60) {
    $hours += int($minutes / 60);
    $minutes %= 60;
  }
  return sprintf '%02d:%02d:%02d', $hours, $minutes, $seconds;
};

helper authenticator => sub ($c) { Crypt::Passphrase->new(encoder => {module => 'Bcrypt'}) };

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
    and grep { $_ eq $bot_key } @{$c->config('bot_keys') // []};
  return 0;
};

helper check_user_password => sub ($c, $username, $password) {
  my $user = $c->pg->db->select('users', [qw(id password_hash)],
    {username => $username})->hashes->first // return undef;
  return $user->{id} if length $user->{password_hash}
    and $c->authenticator->verify_password($password, $user->{password_hash});
  return undef;
};

helper rehash_user_password => sub ($c, $user_id, $password) {
  my $hash = $c->pg->db->select('users', ['password_hash'],
    {id => $user_id})->arrays->first // return 0;
  $hash = $hash->[0];
  return $c->set_user_password($user_id, $password) if length $hash
    and $c->authenticator->needs_rehash($hash) and $c->authenticator->verify_password($password, $hash);
  return 0;
};

helper check_user_reset_code => sub ($c, $username, $code) {
    my $user = $c->pg->db->select('users', ['id'], {
      username => $username,
      password_reset_code => {'=' => \[q{decode(?, 'hex')}, $code]}
    })->arrays->first // return undef;
    return $user->[0];
};

helper set_user_password => sub ($c, $user_id, $password) {
  my $hash = $c->authenticator->hash_password($password);
  return $c->pg->db->update('users', {
    password_hash => $hash,
    password_reset_code => undef,
  }, {id => $user_id})->rows;
};

helper update_last_login => sub ($c, $user_id) {
  $c->pg->db->update('users', {last_login_at => \['now()']}, {id => $user_id});
};

helper import_from_csv => sub ($c, $file) {
  my $songs = csv(in => $file, encoding => 'UTF-8', detect_bom => 1, sep_set => [',', "\t"], auto_diag => 2);
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
    title    => $_->{title} // $_->{Name} // $_->{songName},
    artist   => $_->{artist} // $_->{Artist} // $_->{artistName},
    album    => $_->{album} // $_->{Album} // $_->{albumName},
    track    => $_->{track},
    genre    => $_->{genre} // $_->{Genre} // $_->{genreName},
    source   => $_->{source} // $_->{Charter} // $_->{charterName},
    duration => $_->{duration} // (defined $_->{songlength} ? ($_->{songlength} / 1000) : defined $_->{songLength} ? ($_->{songLength} / 1000) : undef),
    url      => $_->{url},
  } for @$songs;
  $c->import_songs($songs);
};

helper import_from_xlsx => sub ($c, $file) {
  my $parser = Spreadsheet::ParseXLSX->new;
  my $workbook = $parser->parse($file) // die "Failed to parse $file: " . $parser->error;
  my $songs = [];
  foreach my $worksheet ($workbook->worksheets) {
    my ($row_min, $row_max) = $worksheet->row_range;
    my ($col_min, $col_max) = $worksheet->col_range;
    my %cols;
    foreach my $col ($col_min..$col_max) {
      my $heading = $worksheet->get_cell($row_min, $col)->value;
      if ($heading =~ m/Artist/i) {
        $cols{artist} = $col;
      } elsif ($heading =~ m/Song Name/i) {
        $cols{title} = $col;
      } elsif ($heading =~ m/Author/i) {
        $cols{source} = $col;
      } elsif ($heading =~ m/Album/i) {
        $cols{album} = $col;
      } elsif ($heading =~ m/Duration/i) {
        $cols{duration} = $col;
      } elsif ($heading =~ m/Genre/i) {
        $cols{genre} = $col;
      } elsif ($heading =~ m/Track/i) {
        $cols{track} = $col;
      }
    }
    foreach my $row ($row_min+1..$row_max) {
      my %song;
      foreach my $key (qw(title artist album track genre source duration url)) {
        next unless defined $cols{$key};
        my $cell = $worksheet->get_cell($row, $cols{$key});
        $song{$key} = defined $cell ? $cell->value : '';
      }
      next unless grep { length } values %song;
      $song{album} //= '';
      $song{duration} //= 0;
      push @$songs, \%song;
    }
  }
  $c->import_songs($songs);
};

helper export_to_json => sub ($c, $songs) {
  $_ = {
    title    => $_->{title},
    artist   => $_->{artist},
    album    => $_->{album},
    track    => $_->{track},
    genre    => $_->{genre},
    source   => $_->{source},
    duration => $_->{duration},
    url      => $_->{url},
  } for @$songs;
  return Mojo::Asset::Memory->new->add_chunk(encode_json $songs);
};

helper song_for_insert => sub ($c, $details) {
  my %song;
  $song{$_} = $details->{$_}
    for grep { defined $details->{$_} } qw(title artist album genre source url);
  $song{"${_}_ascii"} = unidecode $details->{$_}
    for grep { defined $details->{$_} } qw(title artist album);
  $song{duration} = $c->normalize_duration($details->{duration})
    if defined $details->{duration};
  $song{track} = int $details->{track} if defined $details->{track};
  if (defined $details->{url}) {
    my $url = $details->{url} =~ m/^https?:/ ? $details->{url} : "http://$details->{url}";
    $song{url} = Mojo::URL->new($url)->to_string;
  }
  return \%song;
};

helper import_songs => sub ($c, $songs) {
  my $db = $c->pg->db;
  my $tx = $db->begin;
  foreach my $song (@$songs) {
    my $data = $c->song_for_insert($song);
    next unless %$data;
    $db->insert('songs', $data,
      {on_conflict => \[q{("artist","album","title",coalesce("source",''),coalesce("track",0)) DO UPDATE
      SET "genre"="excluded"."genre", "duration"="excluded"."duration"}]});
  }
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

my @song_details_cols = qw(id title artist album track genre source duration url);

helper search_songs => sub ($c, $search) {
  my $select = join ', ', map { qq{"$_"} } @song_details_cols;
  
  my $and_select = my $or_select = $select;
  $and_select .= q{, ts_rank_cd(songtext, to_tsquery('english_nostop', $1), 1) AS "rank"};
  $or_select .= q{, ts_rank_cd(songtext_withstop, to_tsquery('english', $1), 1) AS "rank"};
  my $order_by = '"rank" DESC, "artist", "album", "track", "title", "source"';
  
  my @terms = map { "'$_':*" } map { quotemeta } split ' ', $search =~ tr[/.][  ]r;
  my $and_search = join ' & ', @terms;
  my $query = qq{SELECT $and_select FROM "songs"
    WHERE songtext \@\@ to_tsquery('english_nostop', \$1) ORDER BY $order_by};
  my $results = $c->pg->db->query($query, $and_search)->hashes;
  return $results if @$results;
  
  my $or_search = join ' | ', @terms;
  $query = qq{SELECT $or_select FROM "songs"
    WHERE songtext_withstop \@\@ to_tsquery('english', \$1) ORDER BY $order_by};
  return $c->pg->db->query($query, $or_search)->hashes;
};

helper song_details => sub ($c, $song_id) {
  return $c->pg->db->select('songs', \@song_details_cols,
    {id => $song_id})->hashes->first;
};

helper random_song_details => sub ($c) {
  return $c->pg->db->select('songs', \@song_details_cols,
    undef, {order_by => \'RANDOM()', limit => 1})->hashes->first;
};

helper all_song_details => sub ($c, $sort_by = 'artist', $sort_dir = 'asc') {
  my @sort = qw(artist album track title source);
  if ($sort_by eq 'album') {
    @sort = qw(album track artist title source);
  } else {
    @sort = ($sort_by, grep { $_ ne $sort_by } @sort);
  }
  return $c->pg->db->select('songs', \@song_details_cols, undef,
    {-$sort_dir => \@sort})->hashes;
};

helper queue_count => sub ($c) {
  return $c->pg->db->select('queue', [\'COUNT(*) AS "count"'])->arrays->[0][0];
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

helper promote_queued_song => sub ($c, $position) {
  my $db = $c->pg->db;
  $db->select('queue', ['id'],
    {position => $position})->arrays->first // return 0;
  my $top_position = $db->select('queue',
    [\'MIN("position")'])->arrays->first // return 0;
  $top_position = $top_position->[0] // return 0;
  return 0 if $position == $top_position;
  my $tx = $db->begin;
  $db->delete('queue', {position => $top_position});
  $db->update('queue', {position => $top_position}, {position => $position});
  $tx->commit;
  return $position;
};

helper promote_random_queued_song => sub ($c) {
  my $db = $c->pg->db;
  my $positions = $db->select('queue', ['position'], undef, {order_by => 'position'})->arrays;
  my $top_position = shift @$positions // return undef;
  $top_position = $top_position->[0];
  unless (@$positions) {
    $db->delete('queue', {position => $top_position});
    return undef;
  }
  my $position = $positions->[int rand $positions->size];
  $position = $position->[0];
  my $tx = $db->begin;
  $db->delete('queue', {position => $top_position});
  $db->update('queue', {position => $top_position}, {position => $position});
  $tx->commit;
  return $position;
};

helper set_queued_song => sub ($c, $position, $song_id) {
  return $c->pg->db->update('queue', {song_id => $song_id},
    {position => $position})->rows;
};

helper set_requested_by => sub ($c, $position, $requested_by) {
  return $c->pg->db->update('queue', {requested_by => $requested_by},
    {position => $position})->rows;
};

helper requester_is_in_queue => sub ($c, $requested_by) {
  return defined $c->pg->db->select('queue', ['id'],
    {requested_by => $requested_by, position => {'!=' => \'(SELECT MIN("position") FROM "queue")'}})->arrays->first;
};

helper set_queued_song_for_requester => sub ($c, $requested_by, $song_id, $raw_request) {
  return $c->pg->db->update('queue', {song_id => $song_id, raw_request => $raw_request},
    {requested_by => $requested_by, position => {'!=' => \'(SELECT MIN("position") FROM "queue")'}})->rows;
};

helper unqueue_song_for_requester => sub ($c, $requested_by) {
  my $deleted = $c->pg->db->delete('queue',
    {requested_by => $requested_by, position => {'!=' => \'(SELECT MIN("position") FROM "queue")'}},
    {returning => 'song_id'})->arrays->first;
  return defined $deleted ? $deleted->[0] : undef;
};

helper clear_queue => sub ($c) {
  return $c->pg->db->query('TRUNCATE TABLE "queue"')->rows;
};

helper get_setting => sub ($c, $name) {
  my $value = $c->pg->db->select('settings', ['value'], {name => $name})->arrays // return undef;
  return $value->[0][0];
};

helper get_settings => sub ($c, @names) {
  my @where = @names ? {name => \@names} : ();
  my $settings = $c->pg->db->select('settings', ['name','value'], @where)->arrays;
  my %settings_hash = map { @$_ } @$settings;
  return \%settings_hash;
};

helper update_settings => sub ($c, $settings) {
  my $db = $c->pg->db;
  my $tx = $db->begin;
  my $count = 0;
  foreach my $name (keys %$settings) {
    $count += $db->insert('settings', {name => $name, value => $settings->{$name}},
      {on_conflict => \['("name") DO UPDATE SET "value" = EXCLUDED."value"']})->rows;
  }
  $tx->commit;
  return $count;
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
  $c->stash(dark_mode => $c->cookie('srq_dark_mode'));
  return 1;
};

get '/' => 'index';

get '/now_playing' => 'now_playing';

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
  
  $c->rehash_user_password($user_id, $password);
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
  
  my $updated = $c->set_user_password($user_id, $password);
  return $c->render(json => {success => true}) if $updated > 0;
  $c->render(json => {success => false});
};

get '/api/songs/search' => sub ($c) {
  my $search = trim($c->param('query') // '');
  return $c->render(json => []) unless length $search;
  my $results = $c->search_songs($search);
  $c->render(json => $results);
};

get '/api/songs/export' => sub ($c) {
  my $asset = $c->export_to_json($c->all_song_details);
  $c->res->headers->content_type('application/json;charset=UTF-8')
    ->content_disposition('attachment; filename="songs.json"');
  $c->reply->asset($asset);
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

get '/api/queue/stats' => sub ($c) {
  my $queue_count = $c->queue_count;
  my $verb = $queue_count == 1 ? 'is' : 'are';
  my $plural = $queue_count == 1 ? '' : 's';
  $c->render(text => "There $verb currently $queue_count request$plural in the song queue");
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
    my $search = trim($c->param('query') // '');
    my $random = $c->param('random');
    
    if (!$c->stash('is_mod') and $c->get_setting('disable_requests')) {
      return $c->render(text => "Requests are currently disabled");
    }
    
    my $song_details;
    my $raw_request;
    if (defined $song_id) {
      $song_details = $c->song_details($song_id);
      return $c->render(text => "Invalid song ID $song_id") unless defined $song_details;
    } elsif (length $search) {
      my $search_results;
      try { $search_results = $c->search_songs($search) } catch {
        $c->app->log->error($@);
        return $c->render(text => 'Internal error searching song database');
      }
      return $c->render(text => "No match found for '$search'")
        if !$search_results->size and $c->get_setting('reject_unknown_requests');
      if ($random) {
        $song_details = $search_results->[int rand $search_results->size];
      } else {
        $song_details = $search_results->first;
      }
      $song_id = $song_details->{id} if defined $song_details;
      $raw_request = $search;
    } elsif ($random) {
      $song_details = $c->random_song_details;
      return $c->render(text => 'No songs to add to queue') unless defined $song_details;
      $song_id = $song_details->{id};
    } else {
      return $c->render(text => 'No song ID or search query provided.');
    }
    
    my $requested_by = $c->param('requested_by') // $c->stash('username') // '';
    if (!$c->stash('is_mod') and $c->get_setting('reject_multiple_requests') and $c->requester_is_in_queue($requested_by)) {
      my $cmd_text = $c->get_setting('update_command_text');
      my $error = "$requested_by already has a song in the queue";
      $error .= "; $cmd_text" if $cmd_text;
      return $c->render(text => $error);
    }
    try { $c->queue_song($song_id, $requested_by, $raw_request) } catch {
      $c->app->log->error($@);
      return $c->render(text => 'Internal error adding song to queue');
    }
    my $response_title = defined $song_details ? "$song_details->{artist} - $song_details->{title}" : $raw_request;
    $c->render(text => "Added '$response_title' to queue (requested by $requested_by)");
  };
  
  any '/api/queue/update' => sub ($c) {
    my $search = trim($c->param('query') // '');
    my $random = $c->param('random');
    
    my $song_details;
    if (length $search) {
      my $search_results;
      try { $search_results = $c->search_songs($search) } catch {
        $c->app->log->error($@);
        return $c->render(text => 'Internal error searching song database');
      }
      return $c->render(text => "No match found for '$search'") unless $search_results->size;
      if ($random) {
        $song_details = $search_results->[int rand $search_results->size];
      } else {
        $song_details = $search_results->first;
      }
    } elsif ($random) {
      $song_details = $c->random_song_details;
      return $c->render(text => 'No songs to add to queue') unless defined $song_details;
    } else {
      return $c->render(text => 'No search query provided.');
    }
    
    my $requested_by = $c->param('requested_by') // $c->stash('username') // '';
    my $updated;
    try { $updated = $c->set_queued_song_for_requester($requested_by, $song_details->{id}, $search) } catch {
      $c->app->log->error($@);
      return $c->render(text => 'Internal error updating song queue');
    }
    return $c->render(text => "$requested_by does not have an inactive request in the queue") unless $updated;
    return $c->render(text => "Updated request to '$song_details->{artist} - $song_details->{title}' (requested by $requested_by)");
  };
  
  any '/api/queue/remove' => sub ($c) {
    my $requested_by = $c->param('requested_by') // $c->stash('username') // '';
    my $removed;
    try { $removed = $c->unqueue_song_for_requester($requested_by) } catch {
      $c->app->log->error($@);
      return $c->render(text => 'Internal error removing song from queue');
    }
    return $c->render(text => "$requested_by does not have an inactive request in the queue") unless defined $removed;
    my $removed_song = $c->song_details($removed);
    return $c->render(text => "Removed request '$removed_song->{artist} - $removed_song->{title}' (requested by $requested_by)");
  };
  
  post '/api/queue/promote_random' => sub ($c) {
    return $c->render(text => 'Access denied', status => 403) unless $c->stash('is_mod');
    my $promoted = $c->promote_random_queued_song;
    return $c->render(text => "Failed to promote a random queued song") unless $promoted;
    return $c->render(text => "Promoted queued song from position $promoted to top");
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
    
    my $promote = $c->param('promote');
    if ($promote) {
      my $promoted = $c->promote_queued_song($position);
      return $c->render(text => "Failed to promote position $position") unless $promoted;
      return $c->render(text => "Promoted queued song from position $promoted to top");
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
    if ($name =~ m/\.xlsx$/i) {
      $c->import_from_xlsx(\$contents);
    } elsif ($contents =~ m/^[\[\{]/ or $name =~ m/\.json$/i) {
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
  
  get '/api/settings' => sub ($c) {
    $c->render(json => $c->get_settings);
  };
  
  post '/api/settings' => sub ($c) {
    my %settings;
    
    foreach my $setting_name (qw(now_playing_text_color now_playing_shadow_color now_playing_font_weight now_playing_font_style now_playing_text_transform now_playing_marquee_behavior)) {
      my $setting_value = $c->param($setting_name) // next;
      if (length $setting_value) {
        return $c->render(text => "Invalid setting for $setting_name")
          unless $setting_value =~ m/\A(?:#?[0-9a-fA-F]+|[a-zA-Z]+)\z/;
      } else {
        $setting_value = undef;
      }
      $settings{$setting_name} = $setting_value;
    }
    
    foreach my $setting_name (qw(now_playing_text_size now_playing_shadow_size now_playing_scroll_amount now_playing_scroll_delay)) {
      my $setting_value = $c->param($setting_name) // next;
      if (length $setting_value) {
        return $c->render(text => "Invalid setting for $setting_name")
          unless $setting_value =~ m/\A[0-9.]+\z/;
      } else {
        $setting_value = undef;
      }
      $settings{$setting_name} = $setting_value;
    }
    
    foreach my $setting_name (qw(now_playing_font_family)) {
      my $setting_value = $c->param($setting_name) // next;
      if (length $setting_value) {
        return $c->render(text => "Invalid setting for $setting_name")
          unless $setting_value =~ m/\A[-0-9a-zA-Z", ]+\z/;
      } else {
        $setting_value = undef;
      }
      $settings{$setting_name} = $setting_value;
    }
    
    foreach my $setting_name (qw(disable_requests reject_multiple_requests reject_unknown_requests)) {
      my $setting_value = $c->param($setting_name) // next;
      if (length $setting_value) {
        $setting_value = 0+!!$setting_value;
      } else {
        $setting_value = undef;
      }
      $settings{$setting_name} = $setting_value;
    }
    
    foreach my $setting_name (qw(queue_meta_column update_command_text)) {
      my $setting_value = $c->param($setting_name) // next;
      $settings{$setting_name} = length $setting_value ? $setting_value : undef;
    }
    
    $c->update_settings(\%settings);
    $c->render(text => 'Settings updated');
  };
};

app->start;
