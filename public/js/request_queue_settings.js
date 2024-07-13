var request_queue_settings_data = {
  result_text: null,
  queue_meta_column: '',
  disable_requests: false,
  reject_duplicate_requests: false,
  reject_multiple_requests: false,
  reject_unknown_requests: false,
  requests_disabled_message: '',
  update_command_text: '',
  unknown_request_text: '',
};
var request_queue_settings_vm = new Vue({
  el: '#request_queue_settings',
  data: request_queue_settings_data,
  methods: {
    get_request_queue_settings: function (event) {
      fetch('/api/settings', {
        credentials: 'include'
      }).then(function(response) {
        if (response.ok) {
          return response.json();
        } else {
          throw new Error(response.status + ' ' + response.statusText);
        }
      }).then(function(data) {
        request_queue_settings_data.queue_meta_column = data.queue_meta_column;
        request_queue_settings_data.disable_requests = !!+data.disable_requests;
        request_queue_settings_data.reject_duplicate_requests = !!+data.reject_duplicate_requests;
        request_queue_settings_data.reject_multiple_requests = !!+data.reject_multiple_requests;
        request_queue_settings_data.reject_unknown_requests = !!+data.reject_unknown_requests;
        request_queue_settings_data.requests_disabled_message = data.requests_disabled_message;
        request_queue_settings_data.update_command_text = data.update_command_text;
        request_queue_settings_data.unknown_request_text = data.unknown_request_text;
      }).catch(function(error) {
        console.log('Error retrieving settings', error);
      });
    },
    update_request_queue_settings: function (event) {
      var update_settings_body = new URLSearchParams();
      var queue_meta_column = request_queue_settings_data.queue_meta_column;
      if (queue_meta_column == null) { queue_meta_column = ''; }
      update_settings_body.set('queue_meta_column', queue_meta_column);
      var disable_requests = request_queue_settings_data.disable_requests ? 1 : 0;
      update_settings_body.set('disable_requests', disable_requests);
      var reject_duplicate_requests = request_queue_settings_data.reject_duplicate_requests ? 1 : 0;
      update_settings_body.set('reject_duplicate_requests', reject_duplicate_requests);
      var reject_multiple_requests = request_queue_settings_data.reject_multiple_requests ? 1 : 0;
      update_settings_body.set('reject_multiple_requests', reject_multiple_requests);
      var reject_unknown_requests = request_queue_settings_data.reject_unknown_requests ? 1 : 0;
      update_settings_body.set('reject_unknown_requests', reject_unknown_requests);
      var requests_disabled_message = request_queue_settings_data.requests_disabled_message;
      if (requests_disabled_message == null) { requests_disabled_message = ''; }
      update_settings_body.set('requests_disabled_message', requests_disabled_message);
      var update_command_text = request_queue_settings_data.update_command_text;
      if (update_command_text == null) { update_command_text = ''; }
      update_settings_body.set('update_command_text', update_command_text);
      var unknown_request_text = request_queue_settings_data.unknown_request_text;
      if (unknown_request_text == null) { unknown_request_text = ''; }
      update_settings_body.set('unknown_request_text', unknown_request_text);
      fetch('/api/settings', {
        method: 'POST',
        body: update_settings_body,
        credentials: 'include'
      }).then(function(response) {
        if (response.ok) {
          return response.text();
        } else {
          throw new Error(response.status + ' ' + response.statusText);
        }
      }).then(function(data) {
        srq_common.set_result_text(request_queue_settings_data, data);
      }).catch(function(error) {
        srq_common.set_result_text(request_queue_settings_data, error.toString());
      });
    }
  }
});

request_queue_settings_vm.get_request_queue_settings();
