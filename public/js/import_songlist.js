var import_data = { result_text: null };
var import_vm = new Vue({
  el: '#import_songlist',
  data: import_data,
  methods: {
    import_songlist: function (event) {
      var import_formdata = new FormData();
      import_formdata.append('songlist', document.getElementById('import_songlist_file').files[0]);
      srq_common.set_result_text(import_data, 'Importing songs...', -1);
      fetch('/api/songs/import', {
        method: 'POST',
        body: import_formdata,
        credentials: 'include'
      }).then(function(response) {
        if (response.ok) {
          srq_common.set_result_text(import_data, 'Import successful');
        } else {
          throw new Error(response.status + ' ' + response.statusText);
        }
      }).catch(function(error) {
        srq_common.set_result_text(import_data, error.toString());
      });
    }
  }
});
