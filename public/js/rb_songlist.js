var queue_data = { queue_first: null, queue_remaining: [] };
var queue_vm = new Vue({
  el: '#request_queue',
  data: queue_data,
  methods: {
    refresh_queue: function (event) {
      $.getJSON('/api/queue')
        .done(function (entries) {
          queue_data.queue_first = entries.shift();
          queue_data.queue_remaining = entries;
        })
    },
    unqueue_song: function (position) {
      if (position) {
        search_vm.clear_search_for_queue();
        $.ajax({ url: '/api/queue/' + position, method: 'DELETE' })
          .done(function () {
            queue_vm.refresh_queue();
          })
      }
    },
    reorder_queue: function (position, direction) {
      if (position) {
        search_vm.clear_search_for_queue();
        $.post('/api/queue/' + position, { reorder: direction })
          .done(function () {
            queue_vm.refresh_queue();
          })
      }
    },
    set_search_for_queue: function (position) {
      search_data.search_for_queue = position;
    }
  }
});

var search_data = { search_songlist_results: [], search_for_queue: null };
var search_vm = new Vue({
  el: '#search_songlist',
  data: search_data,
  methods: {
    search_songlist: function (event) {
      $.getJSON('/api/songs/search', { query: $('#search_songlist_query').val() })
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
    }
  }
});

queue_vm.refresh_queue();

var periodic_refresh = window.setInterval(function () {
  queue_vm.refresh_queue();
}, 5000);
