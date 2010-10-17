module Redcar
  class ApplicationSWT
    class DialogAdapter
      def open_file(options)
        file_dialog(Swt::SWT::OPEN, options)
      end
      
      def open_directory(options)
        directory_dialog(options)
      end
      
      def save_file(options)
        file_dialog(Swt::SWT::SAVE, options)
      end
      
      MESSAGE_BOX_TYPES = {
        :info     => JFace::Dialogs::MessageDialog::INFORMATION,
        :error    => JFace::Dialogs::MessageDialog::ERROR,
        :question => JFace::Dialogs::MessageDialog::QUESTION,
        :warning  => JFace::Dialogs::MessageDialog::WARNING,
        :working  => JFace::Dialogs::MessageDialog::NONE
      }
      
      BUTTONS = Hash.new do |h,k|
        h[k] = case k
          when Array then k.collect(&:to_s)
          when Symbol then k.to_s.split("_")
          else nil
        end
      end
      
      def message_box(text, options)
        style = Swt::SWT::SHEET
        icon = MESSAGE_BOX_TYPES[options[:type] || :working]
        buttons = BUTTONS[options[:buttons] || [:ok]]
        
        dialog = JFace::Dialogs::MessageDialog.new(parent_shell, nil, nil, text, icon,
            buttons.collect(&:capitalize).to_java(:string), 0)
        result = nil
        Redcar.app.protect_application_focus do
          result = dialog.open
        end
        buttons[result].to_sym
      end
      
      def available_message_box_types
        MESSAGE_BOX_TYPES.keys
      end
      
      def input(title, message, initial_value, &block)
        dialog = Dialogs::InputDialog.new(
                   parent_shell,
                   title, message, :initial_text => initial_value) do |text|
          block ? block[text] : nil
        end
        code = dialog.open
        button = (code == 0 ? :ok : :cancel)
        {:button => button, :value => dialog.value}
      end
      
      def password_input(title, message)
        dialog = Dialogs::InputDialog.new(parent_shell, title, message, :password => true)
        code = dialog.open
        button = (code == 0 ? :ok : :cancel)
        {:button => button, :value => dialog.value}
      end
      
      def tool_tip(message, location)
        tool_tip = Swt::Widgets::ToolTip.new(parent_shell, Swt::SWT::ICON_INFORMATION)
        tool_tip.set_message(message)
        tool_tip.set_visible(true)
        tool_tip.set_location(*get_coordinates(location))
      end
      
      def popup_menu(menu, location)
        window = Redcar.app.focussed_window
        menu   = ApplicationSWT::Menu.new(window.controller, menu, nil, Swt::SWT::POP_UP)
        menu.move(*get_coordinates(location))
        menu.show
      end
      
      private
      
      def get_coordinates(location)
        edit_view = EditView.focussed_tab_edit_view
        if location == :cursor and not edit_view
          location = :pointer
        end
        case location
        when :cursor
          location = edit_view.controller.mate_text.viewer.get_text_widget.get_location_at_offset(edit_view.cursor_offset)
          x, y = location.x, location.y
          widget_offset = edit_view.controller.mate_text.viewer.get_text_widget.to_display(0,0)
          x += widget_offset.x
          y += widget_offset.y
        when :pointer
          location = ApplicationSWT.display.get_cursor_location
          x, y = location.x, location.y
        end
        [x, y]
      end
      
      def file_dialog(type, options)
        dialog = Swt::Widgets::FileDialog.new(parent_shell, type)
        dialog.setText("Save File");
        if options[:filter_path]
	  dialog.setText("Save File As") if type == Swt::SWT::SAVE
	  dialog.setText("Open File") if type == Swt::SWT::OPEN
          dialog.set_filter_path(options[:filter_path])
        end
        Redcar.app.protect_application_focus do
          dialog.open
        end
      end
      
      def directory_dialog(options)
        dialog = Swt::Widgets::DirectoryDialog.new(parent_shell)
	dialog.setText("Open Directory")
        if options[:filter_path]
          dialog.set_filter_path(options[:filter_path])
        end
        Redcar.app.protect_application_focus do
          dialog.open
        end
      end
      
      def parent_shell
        if focussed_window = Redcar.app.focussed_window
          focussed_window.controller.shell
        else
          Redcar.app.controller.fake_shell
        end
      end
    end
  end
end
