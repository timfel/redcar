
module Redcar
  module HtmlController
    include Redcar::Observable

    # Reload the index page
    def reload_index
      notify_listeners(:reload_index)
    end

    # Override this to return a message if the user should be prompted
    # before closing the tab.
    def ask_before_closing
      nil
    end

    # Override this to run code right before the tab is closed.
    def close
      nil
    end

    # Call execute with a string of javascript to execute the script
    # in the context of the browser widget.
    def execute(script)
      notify_listeners(:execute_script, script)
    end

    def javascript_controller_actions
      methods = self.methods - Object.methods
      <<-JS
        <script type="text/javascript">
          function makeController (methods) {
            var controller = {};
            methods.map(function (method) {
              var jsMethod = method.replace(/_(.)/g, function () {
                    return arguments[1].toUpperCase();
                  });
              controller[jsMethod] = function () {
                var args = Array.prototype.slice.call(arguments);
                return JSON.parse(rubyCall.apply(this, [method].concat(args)));
              };
            });
            return controller;
          }
          Controller = makeController(#{methods.inspect});
        </script>
      JS
    end
  end
end
