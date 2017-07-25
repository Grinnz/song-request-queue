var login_data = { result_text: null };
var login_vm = new Vue({
  el: '#login',
  data: login_data,
  methods: {
    do_login: function (event) {
      $.post('/api/login', $('#login_form').serialize(), 'json')
        .done(function (data) {
          if (data.logged_in) {
            window.location.href = '/';
          } else {
            var error_text = data.error || 'Login failed';
            srq_common.set_result_text(login_data, error_text);
          }
        })
        .fail(function () {
          srq_common.set_result_text(login_data, 'Login failed');
        });
    }
  }
});
