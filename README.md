# Song Request Queue

## Requirements

* PostgreSQL 9.5+
* Perl 5.20+

## Setup

1. Create a PostgreSQL database and user (that can create tables in the database) for the app to use. 

```
$ createuser song_request_user -lP
$ createdb song_request_queue -O song_request_user
```

2. Create song_request_queue.conf as a perl configuration file, example:

```
{
  pg => 'postgresql://user:pass@/dbname',
  hypnotoad => {
    listen => ['http://*:8080'], # 8080 is default for hypnotoad
  },
  secrets => ['change this'],
}
```

3. Create an empty stopwords file named empty.stop in the tsearch_data subdirectory of your PostgreSQL share directory.

```
# pg_config --sharedir
/path/to/sharedir
# touch /path/to/sharedir/tsearch_data/empty.stop
```

4. Install the perl module prerequisites from the cpanfile.

```
$ cpanm --installdeps .
```

5. Start the application.

```
$ perl song_request_queue.pl daemon --listen='http://*:3000'
```

Or with hypnotoad (production web server):

```
$ hypnotoad song_request_queue.pl
```

See the [Mojolicious deployment cookbook](https://metacpan.org/pod/Mojolicious::Guides::Cookbook#DEPLOYMENT) for more information on deployment options.

## Users

Admin users must be manually added to the `users` table (created once the webapp has been run and successfully connected to the database).
The binary field `password_reset_code` can be set to a one-time-use code to allow the user to set a password on the `/set_password` page.

```
> INSERT INTO "users" ("username","password_reset_code") VALUES ('someuser',E'\\xDEADBEEF');
```

Admin users can add queue moderators on the `/admin` page. The reset code will be returned and can be used similarly on the `/set_password` page.

## Song format

Songs can be manually added on the Admin page, but can also be imported in CSV format.
The CSV format is expected to be that exported by the C3 Tools Setlist Manager, or in general to have headers and the following columns (order not important):
* Song Title
* Artist
* Album Name
* Track #
* Source
* Duration

## Copyright and License

This software is Copyright (c) 2017 by Dan Book.

This is free software, licensed under:

    The Artistic License 2.0 (GPL Compatible)
