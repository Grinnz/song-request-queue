var import_data = { result_text: null };
var import_vm = new Vue({
  el: '#import_songlist',
  data: import_data,
  methods: {
    import_songlist: function (event) {
      $.ajax({
        url: '/api/songs/import',
        method: 'POST',
        data: new FormData($('#import_songlist_form')[0]),
        processData: false,
        contentType: false
      }).done(function () {
          srq_common.set_result_text(import_data, 'Import successful');
        })
        .fail(function () {
          srq_common.set_result_text(import_data, 'Failed to import songlist');
        });
    }
  }
});
