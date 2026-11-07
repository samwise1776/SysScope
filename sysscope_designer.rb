require 'gtk4'
require 'json'
require 'fileutils'

module SysScopeDesigner
  TYPES = %w[Button Label Entry CheckButton Switch Separator ProgressBar].freeze

  class Editor
    def initialize
      @items = []
      @selected = nil
      @next_id = 0
      @loading = false
      @window_title = 'My Desktop App'
      @project_path = File.expand_path('~/DesktopApp.json')
    end

    def build
      @root = Gtk::Box.new(:vertical, 6)
      @root.hexpand = true
      @root.vexpand = true

      toolbar = Gtk::Box.new(:horizontal, 6)
      toolbar.margin_start = 8
      toolbar.margin_top = 8
      toolbar.margin_end = 8

      [
        ['New', proc { new_project }],
        ['Save', proc { save_project }],
        ['Open', proc { open_project }],
        ['Code', proc { show_code }],
        ['Preview', proc { show_preview }],
        ['Refresh', proc { refresh_canvas }]
      ].each do |name, action|
        button = Gtk::Button.new(label: name)
        button.signal_connect('clicked') { action.call }
        toolbar.append(button)
      end

      @root.append(toolbar)

      paned = Gtk::Paned.new(:horizontal)
      paned.hexpand = true
      paned.vexpand = true
      @root.append(paned)

      left = Gtk::Box.new(:vertical, 8)
      left.margin_start = 8
      left.margin_end = 8
      left.margin_top = 8

      left.append(Gtk::Label.new('WIDGET PALETTE'))

      TYPES.each do |type|
        button = Gtk::Button.new(label: "+ #{type}")
        button.signal_connect('clicked') { add_item(type) }

        source = Gtk::DragSource.new
        source.actions = Gdk::DragAction::COPY
        source.signal_connect('prepare') do
          Gdk::ContentProvider.new_for_value(type)
        end
        button.add_controller(source)

        left.append(button)
      end

      left_scroll = Gtk::ScrolledWindow.new
      left_scroll.set_size_request(180, -1)
      left_scroll.set_child(left)
      paned.set_start_child(left_scroll)

      center_right = Gtk::Paned.new(:horizontal)
      center_right.hexpand = true
      center_right.vexpand = true
      paned.set_end_child(center_right)

      canvas_outer = Gtk::Box.new(:vertical, 8)
      canvas_outer.margin_start = 8
      canvas_outer.margin_end = 8
      canvas_outer.margin_top = 8

      @title_entry = Gtk::Entry.new
      @title_entry.text = @window_title
      @title_entry.signal_connect('changed') do
        @window_title = @title_entry.text
      end
      canvas_outer.append(@title_entry)

      @canvas = Gtk::Box.new(:vertical, 8)
      @canvas.margin_start = 15
      @canvas.margin_end = 15
      @canvas.margin_top = 15
      @canvas.margin_bottom = 15
      @canvas.hexpand = true
      @canvas.vexpand = true

      drop = Gtk::DropTarget.new(String, Gdk::DragAction::COPY)
      drop.signal_connect('drop') do |_target, value, _x, _y|
        if TYPES.include?(value.to_s)
          add_item(value.to_s)
          true
        else
          false
        end
      end
      @canvas.add_controller(drop)

      frame = Gtk::Frame.new
      frame.set_child(@canvas)

      scroll = Gtk::ScrolledWindow.new
      scroll.hexpand = true
      scroll.vexpand = true
      scroll.set_child(frame)

      canvas_outer.append(scroll)
      center_right.set_start_child(canvas_outer)

      @properties = Gtk::Box.new(:vertical, 8)
      @properties.margin_start = 10
      @properties.margin_end = 10
      @properties.margin_top = 10

      property_scroll = Gtk::ScrolledWindow.new
      property_scroll.set_size_request(230, -1)
      property_scroll.set_child(@properties)
      center_right.set_end_child(property_scroll)

      paned.position = 190
      center_right.position = 450

      refresh_canvas
      refresh_properties
      @root
    end

    def add_item(type)
      @next_id += 1
      item = {
        'id' => @next_id,
        'type' => type,
        'text' => type == 'Label' ? 'New Label' : type,
        'width' => 200,
        'height' => 40,
        'visible' => true
      }
      @items << item
      @selected = item
      refresh_canvas
      refresh_properties
    end

    def widget_for(item)
      case item['type']
      when 'Button'
        Gtk::Button.new(label: item['text'])
      when 'Label'
        Gtk::Label.new(item['text'])
      when 'Entry'
        w = Gtk::Entry.new
        w.placeholder_text = item['text']
        w
      when 'CheckButton'
        Gtk::CheckButton.new(label: item['text'])
      when 'Switch'
        Gtk::Switch.new
      when 'Separator'
        Gtk::Separator.new(:horizontal)
      when 'ProgressBar'
        w = Gtk::ProgressBar.new
        w.fraction = 0.5
        w
      else
        Gtk::Label.new(item['text'])
      end
    end

    def clear_box(box)
      while (child = box.first_child)
        box.remove(child)
      end
    end

    def refresh_canvas
      return unless @canvas

      clear_box(@canvas)

      if @items.empty?
        hint = Gtk::Label.new(
          'Drag widgets here or click + in the palette'
        )
        hint.margin_top = 45
        @canvas.append(hint)
      end

      @items.each do |item|
        next unless item['visible']

        wrapper = Gtk::Box.new(:horizontal, 5)
        widget = widget_for(item)
        widget.set_size_request(
          item['width'].to_i,
          item['height'].to_i
        )

        select = Gtk::Button.new(
          label: @selected && @selected['id'] == item['id'] ? '●' : '○'
        )
        select.tooltip_text = 'Select widget'
        select.signal_connect('clicked') do
          @selected = item
          refresh_canvas
          refresh_properties
        end

        wrapper.append(select)
        wrapper.append(widget)

        drag = Gtk::DragSource.new
        drag.actions = Gdk::DragAction::MOVE
        drag.signal_connect('prepare') do
          Gdk::ContentProvider.new_for_value(
            "move:#{item['id']}"
          )
        end
        wrapper.add_controller(drag)

        target = Gtk::DropTarget.new(
          String, Gdk::DragAction::MOVE
        )
        target.signal_connect('drop') do |_t, value, _x, _y|
          if value.to_s.start_with?('move:')
            move_item(value.to_s.split(':')[1].to_i, item['id'])
            true
          else
            false
          end
        end
        wrapper.add_controller(target)

        @canvas.append(wrapper)
      end
    end

    def move_item(source_id, target_id)
      source = @items.find { |i| i['id'] == source_id }
      target_index = @items.index { |i| i['id'] == target_id }
      return unless source && target_index

      @items.delete(source)
      target_index = @items.index { |i| i['id'] == target_id }
      @items.insert(target_index, source)
      refresh_canvas
    end

    def property_entry(name, value, &callback)
      @properties.append(Gtk::Label.new(name))
      entry = Gtk::Entry.new
      entry.text = value.to_s
      entry.signal_connect('changed') do
        callback.call(entry.text) unless @loading
      end
      @properties.append(entry)
    end

    def refresh_properties
      return unless @properties
      clear_box(@properties)

      @properties.append(Gtk::Label.new('PROPERTIES'))

      unless @selected
        @properties.append(Gtk::Label.new('Select a widget'))
        return
      end

      item = @selected
      @properties.append(
        Gtk::Label.new("#{item['type']} ##{item['id']}")
      )

      property_entry('Text', item['text']) do |value|
        item['text'] = value
        refresh_canvas
      end

      property_entry('Width', item['width']) do |value|
        item['width'] = [[value.to_i, 20].max, 2000].min
        refresh_canvas
      end

      property_entry('Height', item['height']) do |value|
        item['height'] = [[value.to_i, 20].max, 2000].min
        refresh_canvas
      end

      up = Gtk::Button.new(label: 'Move Up')
      up.signal_connect('clicked') do
        index = @items.index(item)
        if index && index > 0
          @items[index], @items[index - 1] =
            @items[index - 1], @items[index]
          refresh_canvas
        end
      end
      @properties.append(up)

      down = Gtk::Button.new(label: 'Move Down')
      down.signal_connect('clicked') do
        index = @items.index(item)
        if index && index < @items.length - 1
          @items[index], @items[index + 1] =
            @items[index + 1], @items[index]
          refresh_canvas
        end
      end
      @properties.append(down)

      delete = Gtk::Button.new(label: 'Delete Widget')
      delete.signal_connect('clicked') do
        @items.delete(item)
        @selected = nil
        refresh_canvas
        refresh_properties
      end
      @properties.append(delete)
    end

    def new_project
      @items.clear
      @selected = nil
      @next_id = 0
      refresh_canvas
      refresh_properties
    end

    def save_project
      File.write(
        @project_path,
        JSON.pretty_generate({
          'title' => @window_title,
          'items' => @items
        })
      )
      puts "Designer saved: #{@project_path}"
    end

    def open_project
      return unless File.file?(@project_path)
      data = JSON.parse(File.read(@project_path))
      @window_title = data.fetch('title', 'My Desktop App')
      @items = data.fetch('items', [])
      @next_id = @items.map { |i| i['id'].to_i }.max || 0
      @selected = nil
      @title_entry.text = @window_title
      refresh_canvas
      refresh_properties
    end

    def generated_code
      lines = [
        "require 'gtk4'",
        '',
        "app = Gtk::Application.new('com.example.designed')",
        "app.signal_connect('activate') do",
        '  window = Gtk::ApplicationWindow.new(app)',
        "  window.title = #{@window_title.dump}",
        '  window.set_default_size(600, 450)',
        '  box = Gtk::Box.new(:vertical, 8)',
        '  box.margin_start = 15',
        '  box.margin_end = 15',
        '  box.margin_top = 15',
        '  box.margin_bottom = 15'
      ]

      @items.each_with_index do |item, i|
        var = "widget_#{i}"
        text = item['text'].to_s.dump

        expression = case item['type']
        when 'Button'
          "Gtk::Button.new(label: #{text})"
        when 'Label'
          "Gtk::Label.new(#{text})"
        when 'Entry'
          'Gtk::Entry.new'
        when 'CheckButton'
          "Gtk::CheckButton.new(label: #{text})"
        when 'Switch'
          'Gtk::Switch.new'
        when 'Separator'
          'Gtk::Separator.new(:horizontal)'
        when 'ProgressBar'
          'Gtk::ProgressBar.new'
        end

        next unless expression
        lines << "  #{var} = #{expression}"
        if item['type'] == 'Entry'
          lines << "  #{var}.placeholder_text = #{text}"
        end
        if item['type'] == 'ProgressBar'
          lines << "  #{var}.fraction = 0.5"
        end
        lines << "  #{var}.set_size_request(#{item['width'].to_i}, #{item['height'].to_i})"
        lines << "  box.append(#{var})"
      end

      lines += [
        '  window.set_child(box)',
        '  window.present',
        'end',
        'app.run'
      ]

      lines.join("\n") + "\n"
    end

    def show_code
      code_window = Gtk::Window.new
      code_window.title = 'Generated GTK4 Ruby Code'
      code_window.set_default_size(850, 650)

      outer = Gtk::Box.new(:vertical, 6)

      view = Gtk::TextView.new
      view.monospace = true
      view.buffer.text = generated_code

      scroll = Gtk::ScrolledWindow.new
      scroll.vexpand = true
      scroll.set_child(view)
      outer.append(scroll)

      save = Gtk::Button.new(label: 'Save Code as app.rb')
      save.signal_connect('clicked') do
        File.write('app.rb', view.buffer.text)
        puts 'Saved app.rb'
      end
      outer.append(save)

      code_window.set_child(outer)
      code_window.present
    end

    def show_preview
      preview = Gtk::Window.new
      preview.title = @window_title
      preview.set_default_size(600, 450)

      box = Gtk::Box.new(:vertical, 8)
      box.margin_start = 15
      box.margin_end = 15
      box.margin_top = 15
      box.margin_bottom = 15

      @items.each do |item|
        next unless item['visible']
        widget = widget_for(item)
        widget.set_size_request(
          item['width'].to_i,
          item['height'].to_i
        )
        box.append(widget)
      end

      preview.set_child(box)
      preview.present
    end
  end

  def self.add(window)
    root = window.child
    return unless root.is_a?(Gtk::Box)

    editor = Editor.new
    page = editor.build

    if defined?(SysScopeExtraTabs) &&
       root.last_child.is_a?(Gtk::Notebook)
      root.last_child.append_page(
        page, Gtk::Label.new('App Designer')
      )
    else
      expander = Gtk::Expander.new('Desktop App Designer')
      expander.set_child(page)
      root.append(expander)
    end
  end
end
