var add_song_data = { result_text: null };
var add_song_vm = new Vue({
  el: '#add_song',
  data: add_song_data,
  methods: {
    add_song: function (event) {
      $.post('/api/songs', $('#add_song_form').serialize())
        .done(function () {
          srq_common.set_result_text(add_song_data, 'Song successfully added');
        })
        .fail(function () {
          srq_common.set_result_text(add_song_data, 'Failed to add song');
        });
    }
  }
});
