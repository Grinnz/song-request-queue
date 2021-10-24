var now_playing_data = {
  now_playing: null,
};
var now_playing_vm = new Vue({
  el: '#now_playing',
  data: now_playing_data,
  methods: {
    refresh_now_playing: function (event) {
      fetch('/api/queue').then(function(response) {
        if (response.ok) {
          return response.json();
        } else {
          throw new Error(response.status + ' ' + response.statusText);
        }
      }).then(function(entries) {
        now_playing_data.now_playing = entries.shift();
      }).catch(function(error) {
        console.log('Error retrieving song queue', error);
      });
    }
  }
});

now_playing_vm.refresh_now_playing();

var periodic_refresh = window.setInterval(function () {
  now_playing_vm.refresh_now_playing();
}, 5000);
