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
          import_vm.set_result_text('Import successful');
        })
    },
    set_result_text: function (text) {
      import_data.result_text = text;
      var result_text_timeout = window.setTimeout(function() {
        import_data.result_text = null;
      }, 5000);
    }
  }
});
