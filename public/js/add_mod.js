var add_mod_data = { result_text: null };
var add_mod_vm = new Vue({
  el: '#add_mod',
  data: add_mod_data,
  methods: {
    add_mod: function (event) {
      $.post('/api/users', $('#add_mod_form').serialize(), 'json')
        .done(function (data) {
          if (data.success) {
            var success_text = 'Created moderator account ' + data.username + ' with reset code ' + data.reset_code;
            srq_common.set_result_text(add_mod_data, success_text, -1);
          } else {
            var error_text = data.error || 'Failed to create moderator account';
            srq_common.set_result_text(add_mod_data, error_text);
          }
        })
        .fail(function () {
          srq_common.set_result_text(add_mod_data, 'Failed to create moderator account');
        });
    }
  }
});
