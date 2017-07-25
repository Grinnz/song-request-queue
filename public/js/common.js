var srq_common = {
  set_result_text: function (data, text, timeout) {
    timeout = (timeout == null) ? 5000 : timeout;
    data.result_text = text;
    window.clearTimeout(data.result_text_timeout);
    if (timeout >= 0) {
      data.result_text_timeout = window.setTimeout(function() {
        data.result_text = null;
      }, timeout);
    }
  }
};
