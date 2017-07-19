var add_mod_data = { result_text: null };
var add_mod_vm = new Vue({
  el: '#add_mod',
  data: add_mod_data,
  methods: {
    add_mod: function (event) {
      $.post('/api/users', $('#add_mod_form').serialize(), 'json')
        .done(function (data) {
          if (data.success) {
            add_mod_data.result_text = 'Created moderator account ' + data.username + ' with reset code ' + data.reset_code;
          } else {
            var error = data.error || 'Failed to create moderator account';
            add_mod_vm.set_result_text(error);
          }
        })
        .fail(function () {
          add_mod_vm.set_result_text('Failed to create moderator account');
        })
    },
    set_result_text: function (text) {
      add_mod_data.result_text = text;
      var result_text_timeout = window.setTimeout(function() {
        add_mod_data.result_text = null;
      }, 5000);
    }
  }
});
