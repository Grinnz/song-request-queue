var queue_data = {
  queue_first: null,
  queue_remaining: [],
  search_for_queue: null,
  editing_requestor: null,
  edit_requestor_requested_by: '',
};
var queue_vm = new Vue({
  el: '#request_queue',
  data: queue_data,
  methods: {
    refresh_queue: function (event) {
      fetch('/api/queue').then(function(response) {
        if (response.ok) {
          return response.json();
        } else {
          throw new Error(response.status + ' ' + response.statusText);
        }
      }).then(function(entries) {
        queue_vm.set_editing_requestor(null);
        queue_data.queue_first = entries.shift();
        queue_data.queue_remaining = entries;
      }).catch(function(error) {
        console.log('Error retrieving song queue', error);
      });
    },
    unqueue_song: function (position) {
      if (position) {
        queue_vm.set_editing_requestor(null);
        queue_vm.set_search_for_queue(null);
        fetch('/api/queue/' + position, {
          method: 'DELETE',
          credentials: 'include'
        }).then(function(response) {
          if (response.ok) {
            queue_vm.refresh_queue();
          } else {
            throw new Error(response.status + ' ' + response.statusText);
          }
        }).catch(function(error) {
          console.log('Error removing song from queue', error);
        });
      }
    },
    reorder_queue: function (position, direction) {
      if (position) {
        queue_vm.set_editing_requestor(null);
        queue_vm.set_search_for_queue(null);
        var queue_reorder_body = new URLSearchParams();
        queue_reorder_body.set('reorder', direction);
        fetch('/api/queue/' + position, {
          method: 'POST',
          body: queue_reorder_body,
          credentials: 'include'
        }).then(function(response) {
          if (response.ok) {
            queue_vm.refresh_queue();
          } else {
            throw new Error(response.status + ' ' + response.statusText);
          }
        }).catch(function(error) {
          console.log('Error reordering song queue', error);
        });
      }
    },
    set_search_for_queue: function (position) {
      queue_data.search_for_queue = position;
      search_data.search_for_queue = position;
    },
    is_search_for_queue: function (position) {
      return queue_data.search_for_queue == position;
    },
    set_editing_requestor: function (position, requested_by) {
      queue_data.editing_requestor = position;
      queue_data.edit_requestor_requested_by = requested_by;
    },
    edit_requestor: function (position) {
      if (position) {
        var edit_requestor_body = new URLSearchParams();
        edit_requestor_body.set('requested_by', queue_data.edit_requestor_requested_by);
        queue_vm.set_editing_requestor(null);
        fetch('/api/queue/' + position, {
          method: 'POST',
          body: edit_requestor_body,
          credentials: 'include'
        }).then(function(response) {
          if (response.ok) {
            queue_vm.refresh_queue();
          } else {
            throw new Error(response.status + ' ' + response.statusText);
          }
        }).catch(function(error) {
          console.log('Error editing song requestor', error);
        });
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
