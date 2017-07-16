var search_data = { search_songlist_results: [], search_for_queue: null, confirming_delete_song: null };
var search_vm = new Vue({
  el: '#search_songlist',
  data: search_data,
  methods: {
    search_songlist: function (event) {
      $.getJSON('/api/songs/search', $('#search_songlist_form').serialize())
        .done(function (results) {
          search_data.search_songlist_results = results;
        })
    },
    clear_search_songlist: function (event) {
      search_data.search_songlist_results = [];
    },
    queue_song: function (song_id) {
      $.post('/api/queue/add', { song_id: song_id })
        .done(function () {
          queue_vm.refresh_queue();
        })
    },
    clear_search_for_queue: function () {
      search_data.search_for_queue = null;
    },
    set_queued_song: function (position, song_id) {
      if (position) {
        search_vm.clear_search_for_queue();
        $.post('/api/queue/' + position, { song_id: song_id })
          .done(function () {
            queue_vm.refresh_queue();
          })
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
        $.ajax({ url: '/api/songs/' + song_id, method: 'DELETE' })
          .done(function () {
            search_vm.search_songlist();
          })
      }
    }
  }
});
