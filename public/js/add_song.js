var add_song_data = {
  result_text: null,
  add_song_title: '',
  add_song_artist: '',
  add_song_album: '',
  add_song_track: '',
  add_song_genre: '',
  add_song_source: '',
  add_song_duration: '',
  add_song_url: '',
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
      add_song_body.set('genre', add_song_data.add_song_genre);
      if (add_song_data.add_song_source !== null) {
        add_song_body.set('source', add_song_data.add_song_source);
      }
      add_song_body.set('duration', add_song_data.add_song_duration);
      if (add_song_data.add_song_url !== null && add_song_data.add_song_url !== '') {
        add_song_body.set('url', add_song_data.add_song_url);
      }
      fetch('/api/songs', {
        method: 'POST',
        body: add_song_body,
        credentials: 'include'
      }).then(function(response) {
        if (response.ok) {
          return response.text();
        } else {
          throw new Error(response.status + ' ' + response.statusText);
        }
      }).then(function(data) {
        srq_common.set_result_text(add_song_data, data);
      }).catch(function(error) {
        srq_common.set_result_text(add_song_data, error.toString());
      });
    },
    clear_add_song: function (event) {
      add_song_data.add_song_title = '';
      add_song_data.add_song_artist = '';
      add_song_data.add_song_album = '';
      add_song_data.add_song_track = '';
      add_song_data.add_song_genre = '';
      add_song_data.add_song_source = '';
      add_song_data.add_song_duration = '';
      add_song_data.add_song_url = '';
    }
  }
});
