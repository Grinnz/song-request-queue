var clear_songlist_data = { confirming_clear_songlist: null, result_text: null };
var clear_songlist_vm = new Vue({
  el: '#clear_songlist',
  data: clear_songlist_data,
  methods: {
    confirm_clear_songlist: function () {
      clear_songlist_data.confirming_clear_songlist = true;
    },
    unconfirm_clear_songlist: function () {
      clear_songlist_data.confirming_clear_songlist = null;
    },
    clear_songlist: function () {
      clear_songlist_vm.unconfirm_clear_songlist();
      $.ajax({ url: '/api/songs', method: 'DELETE' })
        .done(function () {
          clear_songlist_vm.set_result_text('Songlist cleared');
        })
        .fail(function () {
          clear_songlist_vm.set_result_text('Failed to clear songlist');
        })
    },
    set_result_text: function (text) {
      clear_songlist_data.result_text = text;
      var result_text_timeout = window.setTimeout(function() {
        clear_songlist_data.result_text = null;
      }, 5000);
    }
  }
});
