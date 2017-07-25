var set_password_data = { result_text: null };
var set_password_vm = new Vue({
  el: '#set_password',
  data: set_password_data,
  methods: {
    set_password: function (event) {
      $.post('/api/set_password', $('#set_password_form').serialize(), 'json')
        .done(function (data) {
          if (data.success) {
            srq_common.set_result_text(set_password_data, 'Password successfully changed');
          } else {
            var error_text = data.error || 'Failed to set password';
            srq_common.set_result_text(set_password_data, error_text);
          }
        })
        .fail(function () {
          srq_common.set_result_text(set_password_data, 'Failed to set password');
        });
    }
  }
});
