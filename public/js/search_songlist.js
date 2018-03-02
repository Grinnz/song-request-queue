var search_data = {
  search_songlist_query: '',
  search_songlist_results: [],
  search_for_queue: null,
  confirming_delete_song: null,
  editing_song: null
};
var search_vm = new Vue({
  el: '#search_songlist',
  data: search_data,
  methods: {
    search_songlist: function (event) {
      var search_url = new URL('/api/songs/search', window.location.href);
      search_url.searchParams.set('query', search_data.search_songlist_query);
      fetch(search_url).then(function(response) {
        return response.json();
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
        queue_vm.refresh_queue();
      }).catch(function(error) {
        console.log('Error adding song to queue', error);
      });
    },
    set_search_for_queue: function (position) {
      search_data.search_for_queue = position;
      queue_data.search_for_queue = position;
    },
    set_queued_song: function (position, song_id) {
      if (position) {
        search_vm.set_search_for_queue(null);
        var queue_set_body = new URLSearchParams();
        queue_set_body.set('song_id', song_id);
        fetch('/api/queue/' + position, {
          method: 'POST',
          body: queue_set_body,
          credentials: 'include'
        }).then(function(response) {
          queue_vm.refresh_queue();
        }).catch(function(error) {
          console.log('Error setting queue position', error);
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
          search_vm.search_songlist();
        }).catch(function(error) {
          console.log('Error deleting song', error);
        });
      }
    },
    set_editing_song: function (song_id) {
      search_data.editing_song = song_id;
    },
    edit_song: function (event) {
      if (search_data.editing_song) {
        var song_id = search_data.editing_song;
        var form_data = $('#edit_song_form').serialize();
        search_data.editing_song = null;
        $.post('/api/songs/' + song_id, form_data)
          .done(function () {
            search_vm.search_songlist();
          })
      }
    }
  }
});
