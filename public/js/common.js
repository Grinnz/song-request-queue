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
  },
  pretty_duration: function(duration) {
    return duration === null ? null : duration.replace(/^0(0:0?)?/, '');
  },
  toggle_dark_mode: function() {
    Array.from(document.getElementsByTagName('body')).forEach(function (elem) {
      elem.classList.toggle('bg-dark');
      elem.classList.toggle('text-light');
    });
    Array.from(document.getElementsByTagName('nav')).forEach(function (elem) {
      elem.classList.toggle('navbar-light');
      elem.classList.toggle('navbar-dark');
      elem.classList.toggle('bg-light');
      elem.classList.toggle('bg-dark');
    });
    Array.from(document.getElementsByTagName('table')).forEach(function (elem) {
      elem.classList.toggle('table-dark');
    });
    Array.from(document.getElementsByTagName('thead')).forEach(function (elem) {
      elem.classList.toggle('thead-light');
      elem.classList.toggle('thead-dark');
    });
  }
};
