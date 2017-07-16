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

queue_vm.refresh_queue();

var periodic_refresh = window.setInterval(function () {
  queue_vm.refresh_queue();
}, 5000);
