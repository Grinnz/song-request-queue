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
          srq_common.set_result_text(clear_songlist_data, 'Songlist cleared');
        })
        .fail(function () {
          srq_common.set_result_text(clear_songlist_data, 'Failed to clear songlist');
        });
    }
  }
});
