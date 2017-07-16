var add_song_data = { result_text: null };
var add_song_vm = new Vue({
  el: '#add_song',
  data: add_song_data,
  methods: {
    add_song: function (event) {
      $.post('/api/songs', $('#add_song_form').serialize())
        .done(function () {
          add_song_vm.set_result_text('Song successfully added');
        })
        .fail(function () {
          add_song_vm.set_result_text('Failed to add song');
        })
    },
    set_result_text: function (text) {
      add_song_data.result_text = text;
      var result_text_timeout = window.setTimeout(function() {
        add_song_data.result_text = null;
      }, 5000);
    }
  }
});
