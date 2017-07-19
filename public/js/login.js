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
            var error = data.error || 'Login failed';
            login_vm.set_result_text(error);
          }
        })
        .fail(function () {
          login_vm.set_result_text('Login failed');
        })
    },
    set_result_text: function (text) {
      login_data.result_text = text;
      var result_text_timeout = window.setTimeout(function() {
        login_data.result_text = null;
      }, 5000);
    }
  }
});
