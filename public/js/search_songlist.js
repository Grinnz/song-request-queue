var search_data = {
  search_songlist_query: '',
  search_songlist_results: [],
  search_for_queue: null,
  confirming_delete_song: null,
  editing_song: null,
  edit_song_title: '',
  edit_song_artist: '',
  edit_song_album: '',
  edit_song_track: '',
  edit_song_genre: '',
  edit_song_source: '',
  edit_song_duration: '',
  edit_song_url: '',
};
var search_vm = new Vue({
  el: '#search_songlist',
  data: search_data,
  methods: {
    search_songlist: function (event) {
      var search_url = new URL('/api/songs/search', window.location.href);
      search_url.searchParams.set('query', search_data.search_songlist_query);
      fetch(search_url).then(function(response) {
        if (response.ok) {
          return response.json();
        } else {
          throw new Error(response.status + ' ' + response.statusText);
        }
      }).then(function(results) {
        search_data.search_songlist_results = results;
      }).catch(function(error) {
        console.log('Error searching song list', error);
      });
    },
    clear_search_songlist: function (event) {
      search_data.search_songlist_results = [];
      search_data.search_songlist_query = '';
    },
    queue_song: function (song_id) {
      var queue_add_body = new URLSearchParams();
      queue_add_body.set('song_id', song_id);
      fetch('/api/queue/add', {
        method: 'POST',
        body: queue_add_body,
        credentials: 'include'
      }).then(function(response) {
        if (response.ok) {
          queue_vm.refresh_queue();
        } else {
          throw new Error(response.status + ' ' + response.statusText);
        }
      }).catch(function(error) {
        console.log('Error adding song to queue', error);
      });
    },
    queue_random_song: function (query) {
      var queue_random_body = new URLSearchParams();
      queue_random_body.set('random', 1);
      if (query !== null && query !== '') {
        queue_random_body.set('query', query);
      }
      fetch('/api/queue/add', {
        method: 'POST',
        body: queue_random_body,
        credentials: 'include'
      }).then(function(response) {
        if (response.ok) {
          queue_vm.refresh_queue();
        } else {
          throw new Error(response.status + ' ' + response.statusText);
        }
      }).catch(function(error) {
        console.log('Error adding random song to queue', error);
      });
    },
    set_search_for_queue: function (request) {
      search_data.search_for_queue = request;
      queue_data.search_for_queue = request;
    },
    set_queued_song: function (queue_id, song_id) {
      if (queue_id) {
        search_vm.set_search_for_queue(null);
        var queue_set_body = new URLSearchParams();
        queue_set_body.set('song_id', song_id);
        fetch('/api/queue/' + queue_id, {
          method: 'POST',
          body: queue_set_body,
          credentials: 'include'
        }).then(function(response) {
          if (response.ok) {
            queue_vm.refresh_queue();
          } else {
            throw new Error(response.status + ' ' + response.statusText);
          }
        }).catch(function(error) {
          console.log('Error setting queued song', error);
        });
      }
    },
    confirm_delete_song: function (song_id) {
      search_data.confirming_delete_song = song_id;
    },
    unconfirm_delete_song: function (song_id) {
      search_data.confirming_delete_song = null;
    },
    delete_song: function (song_id) {
      if (song_id) {
        search_vm.unconfirm_delete_song(song_id);
        fetch('/api/songs/' + song_id, {
          method: 'DELETE',
          credentials: 'include'
        }).then(function(response) {
          if (response.ok) {
            search_vm.search_songlist();
          } else {
            throw new Error(response.status + ' ' + response.statusText);
          }
        }).catch(function(error) {
          console.log('Error deleting song', error);
        });
      }
    },
    set_editing_song: function (song) {
      if (song === null) {
        search_data.editing_song = null;
      } else {
        search_data.editing_song = song.id;
        search_data.edit_song_title = song.title;
        search_data.edit_song_artist = song.artist;
        search_data.edit_song_album = song.album;
        search_data.edit_song_track = song.track;
        search_data.edit_song_genre = song.genre;
        search_data.edit_song_source = song.source;
        search_data.edit_song_duration = song.duration;
        search_data.edit_song_url = song.url;
      }
    },
    edit_song: function (event) {
      if (search_data.editing_song) {
        var song_id = search_data.editing_song;
        var edit_song_body = new URLSearchParams();
        edit_song_body.set('title', search_data.edit_song_title);
        edit_song_body.set('artist', search_data.edit_song_artist);
        edit_song_body.set('album', search_data.edit_song_album);
        if (search_data.edit_song_track !== null && search_data.edit_song_track !== '') {
          edit_song_body.set('track', search_data.edit_song_track);
        }
        edit_song_body.set('genre', search_data.edit_song_genre);
        if (search_data.edit_song_source !== null) {
          edit_song_body.set('source', search_data.edit_song_source);
        }
        edit_song_body.set('duration', search_data.edit_song_duration);
        if (search_data.edit_song_url !== null && search_data.edit_song_url !== '') {
          edit_song_body.set('url', search_data.edit_song_url);
        }
        search_data.editing_song = null;
        fetch('/api/songs/' + song_id, {
          method: 'POST',
          body: edit_song_body,
          credentials: 'include'
        }).then(function(response) {
          if (response.ok) {
            search_vm.search_songlist();
          } else {
            throw new Error(response.status + ' ' + response.statusText);
          }
        }).catch(function(error) {
          console.log('Error editing song', error);
        });
      }
    }
  }
});
