var now_playing_settings_data = {
  result_text: null,
  now_playing_text_color: '',
  now_playing_text_size: '',
  now_playing_shadow_color: '',
  now_playing_shadow_size: '',
  now_playing_font_family: '',
  now_playing_text_transform: '',
  now_playing_scroll_amount: '',
  now_playing_scroll_delay: '',
  now_playing_marquee_behavior: '',
};
var now_playing_settings_vm = new Vue({
  el: '#now_playing_settings',
  data: now_playing_settings_data,
  methods: {
    get_now_playing_settings: function (event) {
      fetch('/api/settings', {
        credentials: 'include'
      }).then(function(response) {
        if (response.ok) {
          return response.json();
        } else {
          throw new Error(response.status + ' ' + response.statusText);
        }
      }).then(function(data) {
        now_playing_settings_data.now_playing_text_color = data.now_playing_text_color;
        now_playing_settings_data.now_playing_text_size = data.now_playing_text_size;
        now_playing_settings_data.now_playing_shadow_color = data.now_playing_shadow_color;
        now_playing_settings_data.now_playing_shadow_size = data.now_playing_shadow_size;
        now_playing_settings_data.now_playing_font_family = data.now_playing_font_family;
        now_playing_settings_data.now_playing_text_transform = data.now_playing_text_transform;
        now_playing_settings_data.now_playing_scroll_amount = data.now_playing_scroll_amount;
        now_playing_settings_data.now_playing_scroll_delay = data.now_playing_scroll_delay;
        now_playing_settings_data.now_playing_marquee_behavior = data.now_playing_marquee_behavior;
      }).catch(function(error) {
        console.log('Error retrieving settings', error);
      });
    },
    update_now_playing_settings: function (event) {
      var update_settings_body = new URLSearchParams();
      var text_color = now_playing_settings_data.now_playing_text_color;
      if (text_color == null) { text_color = ''; }
      update_settings_body.set('now_playing_text_color', text_color);
      var text_size = now_playing_settings_data.now_playing_text_size;
      if (text_size == null) { text_size = ''; }
      update_settings_body.set('now_playing_text_size', text_size);
      var shadow_color = now_playing_settings_data.now_playing_shadow_color;
      if (shadow_color == null) { shadow_color = ''; }
      update_settings_body.set('now_playing_shadow_color', shadow_color);
      var shadow_size = now_playing_settings_data.now_playing_shadow_size;
      if (shadow_size == null) { shadow_size = ''; }
      update_settings_body.set('now_playing_shadow_size', shadow_size);
      var font_family = now_playing_settings_data.now_playing_font_family;
      if (font_family == null) { font_family = ''; }
      update_settings_body.set('now_playing_font_family', font_family);
      var text_transform = now_playing_settings_data.now_playing_text_transform;
      if (text_transform == null) { text_transform = ''; }
      update_settings_body.set('now_playing_text_transform', text_transform);
      var scroll_amount = now_playing_settings_data.now_playing_scroll_amount;
      if (scroll_amount == null) { scroll_amount = ''; }
      update_settings_body.set('now_playing_scroll_amount', scroll_amount);
      var scroll_delay = now_playing_settings_data.now_playing_scroll_delay;
      if (scroll_delay == null) { scroll_delay = ''; }
      update_settings_body.set('now_playing_scroll_delay', scroll_delay);
      var marquee_behavior = now_playing_settings_data.now_playing_marquee_behavior;
      if (marquee_behavior == null) { marquee_behavior = ''; }
      update_settings_body.set('now_playing_marquee_behavior', marquee_behavior);
      fetch('/api/settings', {
        method: 'POST',
        body: update_settings_body,
        credentials: 'include'
      }).then(function(response) {
        if (response.ok) {
          return response.text();
        } else {
          throw new Error(response.status + ' ' + response.statusText);
        }
      }).then(function(data) {
        now_playing_settings_vm.refresh_now_playing_preview();
        srq_common.set_result_text(now_playing_settings_data, data);
      }).catch(function(error) {
        srq_common.set_result_text(now_playing_settings_data, error.toString());
      });
    },
    refresh_now_playing_preview: function (event) {
      document.getElementById('now_playing_preview').contentWindow.location.reload();
    }
  }
});

now_playing_settings_vm.get_now_playing_settings();
