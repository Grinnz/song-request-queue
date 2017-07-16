var queue_data = { queue_first: null, queue_remaining: [], editing_requestor: null };
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
    },
    toggle_edit_requestor: function (position) {
      if (queue_data.editing_requestor == position) {
        queue_data.editing_requestor = null;
      } else {
        queue_data.editing_requestor = position;
      }
    },
    edit_requestor: function (position) {
      if (position) {
        var form_data = $('#edit_requestor_form').serialize();
        queue_vm.toggle_edit_requestor(position);
        $.post('/api/queue/' + position, form_data)
          .done(function () {
            queue_vm.refresh_queue();
          })
      }
    }
  }
});

queue_vm.refresh_queue();

var periodic_refresh = window.setInterval(function () {
  if (queue_data.editing_requestor == null) {
    queue_vm.refresh_queue();
  }
}, 5000);
