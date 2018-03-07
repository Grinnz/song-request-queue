var add_song_data = {
  result_text: null,
  add_song_title: '',
  add_song_artist: '',
  add_song_album: '',
  add_song_track: '',
  add_song_source: '',
  add_song_duration: '',
};
var add_song_vm = new Vue({
  el: '#add_song',
  data: add_song_data,
  methods: {
    add_song: function (event) {
      var add_song_body = new URLSearchParams();
      add_song_body.set('title', add_song_data.add_song_title);
      add_song_body.set('artist', add_song_data.add_song_artist);
      add_song_body.set('album', add_song_data.add_song_album);
      if (add_song_data.add_song_track !== null && add_song_data.add_song_track !== '') {
        add_song_body.set('track', add_song_data.add_song_track);
      }
      add_song_body.set('source', add_song_data.add_song_source);
      add_song_body.set('duration', add_song_data.add_song_duration);
      fetch('/api/songs', {
        method: 'POST',
        body: add_song_body,
        credentials: 'include'
      }).then(function(response) {
        srq_common.set_result_text(add_song_data, 'Song successfully added');
      }).catch(function(error) {
        srq_common.set_result_text(add_song_data, 'Failed to add song');
      });
    }
  }
});
