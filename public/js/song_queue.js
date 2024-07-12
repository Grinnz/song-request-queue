var queue_data = {
  queue_first: null,
  queue_remaining: [],
  search_for_queue: null,
  editing_requestor: null,
  edit_requestor_requested_by: '',
  confirming_clear_queue: false,
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
    unqueue_song: function (queue_id) {
      if (queue_id) {
        queue_vm.set_editing_requestor(null);
        queue_vm.set_search_for_queue(null);
        fetch('/api/queue/' + queue_id, {
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
    reorder_queue: function (queue_id, direction) {
      if (queue_id) {
        queue_vm.set_editing_requestor(null);
        queue_vm.set_search_for_queue(null);
        var queue_reorder_body = new URLSearchParams();
        queue_reorder_body.set('reorder', direction);
        fetch('/api/queue/' + queue_id, {
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
    queue_promote_song: function(queue_id) {
      queue_vm.set_editing_requestor(null);
      queue_vm.set_search_for_queue(null);
      var queue_promote_body = new URLSearchParams();
      queue_promote_body.set('promote', 1);
      fetch('/api/queue/' + queue_id, {
        method: 'POST',
        body: queue_promote_body,
        credentials: 'include'
      }).then(function(response) {
        if (response.ok) {
          queue_vm.refresh_queue();
        } else {
          throw new Error(response.status + ' ' + response.statusText);
        }
      }).catch(function(error) {
        console.log('Error promoting song', error);
      });
    },
    queue_promote_random: function () {
      queue_vm.set_editing_requestor(null);
      queue_vm.set_search_for_queue(null);
      fetch('/api/queue/promote_random', {
        method: 'POST',
        credentials: 'include'
      }).then(function(response) {
        if (response.ok) {
          queue_vm.refresh_queue();
        } else {
          throw new Error(response.status + ' ' + response.statusText);
        }
      }).catch(function(error) {
        console.log('Error promoting random song', error);
      });
    },
    set_search_for_queue: function (request) {
      queue_data.search_for_queue = request;
      search_data.search_for_queue = request;
    },
    is_search_for_queue: function (queue_id) {
      if (queue_data.search_for_queue == null) { return false; }
      return queue_data.search_for_queue.id == queue_id;
    },
    set_editing_requestor: function (queue_id, requested_by) {
      queue_data.editing_requestor = queue_id;
      queue_data.edit_requestor_requested_by = requested_by;
    },
    edit_requestor: function (queue_id) {
      if (queue_id) {
        var edit_requestor_body = new URLSearchParams();
        edit_requestor_body.set('requested_by', queue_data.edit_requestor_requested_by);
        queue_vm.set_editing_requestor(null);
        fetch('/api/queue/' + queue_id, {
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
    },
    confirm_clear_queue: function () {
      queue_data.confirming_clear_queue = true;
    },
    unconfirm_clear_queue: function () {
      queue_data.confirming_clear_queue = false;
    },
    clear_queue: function () {
      queue_data.confirming_clear_queue = false;
      fetch('/api/queue', {
        method: 'DELETE',
        credentials: 'include'
      }).then(function(response) {
        if (response.ok) {
          queue_vm.refresh_queue();
        } else {
          throw new Error(response.status + ' ' + response.statusText);
        }
      }).catch(function(error) {
        console.log('Error clearing song queue', error);
      });
    }
  }
});

queue_vm.refresh_queue();

var periodic_refresh = window.setInterval(function () {
  if (queue_data.editing_requestor == null) {
    queue_vm.refresh_queue();
  }
}, 5000);
