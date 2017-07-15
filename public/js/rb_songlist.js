var search_data = { search_songlist_results: [] };
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
    }
  }
});

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
    }
  }
});

queue_vm.refresh_queue();
