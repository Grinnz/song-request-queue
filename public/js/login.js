var login_data = { result_text: null, login_username: '', login_password: '' };
var login_vm = new Vue({
  el: '#login',
  data: login_data,
  methods: {
    do_login: function (event) {
      var login_body = new URLSearchParams();
      login_body.set('username', login_data.login_username);
      login_body.set('password', login_data.login_password);
      fetch('/api/login', {
        method: 'POST',
        body: login_body,
        credentials: 'include'
      }).then(function(response) {
        if (response.ok) {
          return response.json();
        } else {
          throw new Error(response.status + ' ' + response.statusText);
        }
      }).then(function(data) {
        if (data.logged_in) {
          window.location.href = '/';
        } else {
          throw new Error(data.error || 'Login failed');
        }
      }).catch(function(error) {
        srq_common.set_result_text(login_data, error.toString());
      });
    }
  }
});
