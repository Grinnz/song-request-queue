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
