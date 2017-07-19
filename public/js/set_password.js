var set_password_data = { result_text: null };
var set_password_vm = new Vue({
  el: '#set_password',
  data: set_password_data,
  methods: {
    set_password: function (event) {
      $.post('/api/set_password', $('#set_password_form').serialize(), 'json')
        .done(function (data) {
          if (data.success) {
            set_password_vm.set_result_text('Password successfully changed');
          } else {
            var error = data.error || 'Failed to set password';
            set_password_vm.set_result_text(error);
          }
        })
        .fail(function () {
          set_password_vm.set_result_text('Failed to set password');
        })
    },
    set_result_text: function (text) {
      set_password_data.result_text = text;
      var result_text_timeout = window.setTimeout(function() {
        set_password_data.result_text = null;
      }, 5000);
    }
  }
});
