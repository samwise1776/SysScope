
require 'gtk4'
require 'cairo'
require 'json'
require 'open3'
require 'shellwords'

# ==========================================
# SYSTEM INFORMATION
# ==========================================

def system_ram_usage
  info = {}

  File.foreach('/proc/meminfo') do |line|
    if line =~ /^(MemTotal|MemAvailable|MemFree|Buffers|Cached):\s+(\d+)/
      info[$1] = $2.to_f / 1024.0
    end
  end

  total = info.fetch('MemTotal', 1.0)
  available = info['MemAvailable'] || (
    info.fetch('MemFree', 0) +
    info.fetch('Buffers', 0) +
    info.fetch('Cached', 0)
  )

  used = total - available

  {
    total_mb: total.round(2),
    used_mb: used.round(2),
    available_mb: available.round(2),
    percent: (used / total * 100).clamp(0, 100).round(2)
  }
end

def cpu_times
  values = File.open('/proc/stat', &:readline)
               .split.drop(1).map(&:to_i)

  idle = values[3] + values[4]
  [idle, values.sum]
end

def system_process_count
  Dir.children('/proc').count { |entry| entry.match?(/\A\d+\z/) }
end

# ==========================================
# APPLICATION DISCOVERY
# ==========================================

def sysscope_desktop_apps
  apps = {}

  directories = [
    '/usr/share/applications',
    '/usr/local/share/applications',
    File.expand_path('~/.local/share/applications')
  ]

  directories.each do |directory|
    Dir.glob(File.join(directory, '*.desktop')).each do |file|
      begin
        data = {}
        in_desktop_entry = false

        File.foreach(file) do |line|
          line = line.strip

          if line.start_with?('[')
            in_desktop_entry = line == '[Desktop Entry]'
            next
          end

          next unless in_desktop_entry

          if line =~ /^(Name|Icon|Exec|StartupWMClass)=(.*)$/
            data[$1] ||= $2.strip
          end
        end

        next if data['Name'].to_s.empty?

        executable = data['Exec'].to_s.split.first

        keys = [
          data['Name'],
          File.basename(file, '.desktop'),
          data['StartupWMClass'],
          executable
        ].compact

        info = {
          name: data['Name'],
          icon: data['Icon'] || 'application-x-executable'
        }

        keys.each do |key|
          apps[key.downcase] = info
        end
      rescue StandardError
        next
      end
    end
  end

  apps
end

def sysscope_running_apps(desktop_apps)
  results = []

  if ENV['HYPRLAND_INSTANCE_SIGNATURE']
    begin
      json = IO.popen(
        ['hyprctl', 'clients', '-j'],
        err: File::NULL,
        &:read
      )

      JSON.parse(json).each do |client|
        app_id = client['class'].to_s
        next if app_id.empty?

        info = desktop_apps[app_id.downcase] || {}

        results << {
          name: info[:name] || app_id,
          detail: client['title'].to_s,
          icon: info[:icon] || app_id.downcase,
          type: 'Application'
        }
      end
    rescue StandardError
      # Fall back to Linux process discovery.
    end
  end

  if results.empty?
    Dir.glob('/proc/[0-9]*/comm').each do |file|
      begin
        process_name = File.read(file).strip
        next if process_name.empty?

        info = desktop_apps[process_name.downcase] || {}

        results << {
          name: info[:name] || process_name,
          detail: 'Running process',
          icon: info[:icon] || 'application-x-executable',
          type: 'Process'
        }
      rescue StandardError
        next
      end
    end
  end

  results.uniq { |item| [item[:name], item[:detail]] }
end

# ==========================================
# TERMINAL COMPONENT
# ==========================================

def create_terminal
  terminal_box = Gtk::Box.new(:vertical, 10)
  terminal_box.hexpand = true
  terminal_box.vexpand = true

  title = Gtk::Label.new
  title.set_markup(
    '<span size="large" weight="bold">SysScope Terminal</span>'
  )
  title.xalign = 0
  terminal_box.append(title)

  output = Gtk::TextView.new
  output.editable = false
  output.cursor_visible = false
  output.monospace = true
  output.wrap_mode = :word_char

  buffer = output.buffer

  scroll = Gtk::ScrolledWindow.new
  scroll.set_policy(:automatic, :automatic)
  scroll.set_size_request(380, 230)
  scroll.hexpand = true
  scroll.vexpand = true
  scroll.set_child(output)

  terminal_box.append(scroll)

  input_row = Gtk::Box.new(:horizontal, 6)

  command_entry = Gtk::Entry.new
  command_entry.placeholder_text = 'Enter command...'
  command_entry.hexpand = true

  run_button = Gtk::Button.new(label: 'Run')
  clear_button = Gtk::Button.new(label: 'Clear')

  input_row.append(command_entry)
  input_row.append(run_button)
  input_row.append(clear_button)

  terminal_box.append(input_row)

  status_label = Gtk::Label.new('Ready')
  status_label.xalign = 0
  terminal_box.append(status_label)

  history = []
  history_index = 0
  working_directory = Dir.home
  busy = false

  append_output = proc do |message|
    GLib::Idle.add do
      buffer.insert(buffer.end_iter, message.to_s)
      scroll.vadjustment.value = scroll.vadjustment.upper
      GLib::Source::REMOVE
    end
  end

  append_output.call(
    "SysScope Terminal\n" \
    "Working directory: #{working_directory}\n" \
    "Type help for terminal commands.\n\n"
  )

  run_command = proc do
    command = command_entry.text.to_s.strip
    next if command.empty? || busy

    history << command
    history_index = history.length

    command_entry.text = ''

    append_output.call(
      "\n#{working_directory} $ #{command}\n"
    )

    case command
    when 'clear'
      buffer.text = ''
      next

    when 'pwd'
      append_output.call("#{working_directory}\n")
      next

    when 'help'
      append_output.call(
        "SysScope Terminal Commands\n\n" \
        "help       Show this help\n" \
        "clear      Clear terminal output\n" \
        "pwd        Current directory\n" \
        "cd PATH    Change directory\n" \
        "history    Show command history\n" \
        "ls         List files\n" \
        "whoami     Current user\n" \
        "uname -a   System information\n" \
        "free -h    Memory information\n" \
        "df -h      Disk information\n" \
        "ps aux     Running processes\n\n" \
        "Other shell commands are supported.\n"
      )
      next

    when 'history'
      history.each_with_index do |entry, index|
        append_output.call("#{index + 1}  #{entry}\n")
      end
      next
    end

    if command == 'cd' || command.start_with?('cd ')
      begin
        arguments = Shellwords.split(command)
        target = arguments[1] || Dir.home
        target = Dir.home if target == '~'

        if target.start_with?('~/')
          target = File.join(Dir.home, target[2..])
        end

        directory = File.expand_path(
          target,
          working_directory
        )

        if File.directory?(directory)
          working_directory = directory
          append_output.call("#{working_directory}\n")
        else
          append_output.call("cd: no such directory: #{target}\n")
        end
      rescue ArgumentError => error
        append_output.call("cd: #{error.message}\n")
      end

      next
    end

    busy = true
    run_button.sensitive = false
    status_label.text = 'Running...'

    cwd = working_directory.dup

    Thread.new do
      begin
        Open3.popen2e(
          '/bin/sh', '-c', command,
          chdir: cwd
        ) do |stdin, stdout, process|
          stdin.close

          stdout.each_line do |line|
            append_output.call(line)
          end

          status = process.value

          append_output.call(
            "\nExit status: #{status.exitstatus || 'signal'}\n"
          )
        end
      rescue StandardError => error
        append_output.call(
          "Terminal error: #{error.message}\n"
        )
      ensure
        GLib::Idle.add do
          busy = false
          run_button.sensitive = true
          status_label.text = 'Ready'
          command_entry.grab_focus
          GLib::Source::REMOVE
        end
      end
    end
  end

  command_entry.signal_connect('activate') do
    run_command.call
  end

  run_button.signal_connect('clicked') do
    run_command.call
  end

  clear_button.signal_connect('clicked') do
    buffer.text = ''
  end

  key_controller = Gtk::EventControllerKey.new

  key_controller.signal_connect('key-pressed') do |_controller, keyval, _keycode, _state|
    case Gdk::Keyval.to_name(keyval)
    when 'Up'
      unless history.empty?
        history_index = [history_index - 1, 0].max
        command_entry.text = history[history_index]
        command_entry.set_position(-1)
      end
      true

    when 'Down'
      unless history.empty?
        history_index = [
          history_index + 1,
          history.length
        ].min

        command_entry.text =
          history_index == history.length ? '' : history[history_index]

        command_entry.set_position(-1)
      end
      true

    else
      false
    end
  end

  command_entry.add_controller(key_controller)

  terminal_box
end

# ==========================================
# GTK4 APPLICATION
# ==========================================

app = Gtk::Application.new('com.sysscope.app')

app.signal_connect('activate') do

  icon_dir = File.expand_path(__dir__)

  Gtk::IconTheme.get_for_display(Gdk::Display.default)
                .add_search_path(icon_dir)

  window = Gtk::ApplicationWindow.new(app)
  window.title = 'SysScope'
  window.set_default_size(1200, 750)

  # ==========================================
  # CSS
  # ==========================================

  css_provider = Gtk::CssProvider.new

  css_provider.load(data: <<~CSS)
    .sysscope-selected {
      outline: 2px solid #4d99ff;
      outline-offset: -2px;
      border-radius: 8px;
      background-color: alpha(#4d99ff, 0.12);
    }

    .sysscope-info-panel {
      border: 2px solid #4d99ff;
      border-radius: 12px;
      background-color: alpha(#4d99ff, 0.04);
    }

    .sysscope-terminal-panel {
      border: 2px solid #4d99ff;
      border-radius: 10px;
      padding: 12px;
    }
  CSS

  Gtk::StyleContext.add_provider_for_display(
    Gdk::Display.default,
    css_provider,
    Gtk::StyleProvider::PRIORITY_APPLICATION
  )

  # ==========================================
  # MAIN INFORMATION BOX
  # ==========================================

  box = Gtk::Box.new(:vertical, 15)
  box.set_size_request(550, 700)
  box.halign = :center
  box.valign = :start

  box.margin_top = 20
  box.margin_bottom = 20
  box.margin_start = 20
  box.margin_end = 20

  # ==========================================
  # CPU DIAL
  # ==========================================

  cpu_percent = 0.0

  dial = Gtk::DrawingArea.new
  dial.set_content_width(200)
  dial.set_content_height(200)

  dial.set_draw_func do |_area, cr, width, height|
    cx = width / 2.0
    cy = height / 2.0
    radius = 75

    cr.set_line_width(12)
    cr.set_source_rgb(0.2, 0.2, 0.2)
    cr.arc(cx, cy, radius, 0, 2 * Math::PI)
    cr.stroke

    if cpu_percent > 0
      cr.set_source_rgb(0.3, 0.6, 1.0)
      cr.set_line_width(12)
      cr.set_line_cap(Cairo::LINE_CAP_ROUND)

      cr.arc(
        cx, cy, radius,
        -Math::PI / 2,
        -Math::PI / 2 + 2 * Math::PI * cpu_percent / 100.0
      )

      cr.stroke
    end
  end

  cpu_label = Gtk::Label.new('CPU: 0.0%')

  # ==========================================
  # RAM
  # ==========================================

  ram_label = Gtk::Label.new('RAM: 0.0%')
  ram_details = Gtk::Label.new('0 MB / 0 MB')

  ram_bar = Gtk::ProgressBar.new
  ram_bar.set_size_request(350, 20)
  ram_bar.fraction = 0.0
  ram_bar.show_text = true

  # ==========================================
  # PROCESSES
  # ==========================================

  apps_label = Gtk::Label.new('Processes: 0')

  # ==========================================
  # SYSTEM INFORMATION LAYOUT
  # ==========================================

  heading = proc do |text|
    label = Gtk::Label.new
    label.set_markup(
      "<span size=\"large\" weight=\"bold\">#{text}</span>"
    )
    label
  end

  box.append(heading.call('SysScope'))
  box.append(heading.call('CPU Usage'))
  box.append(dial)
  box.append(cpu_label)

  box.append(Gtk::Separator.new(:horizontal))

  box.append(heading.call('Memory Usage'))
  box.append(ram_label)
  box.append(ram_bar)
  box.append(ram_details)

  box.append(Gtk::Separator.new(:horizontal))

  box.append(heading.call('Running Processes'))
  box.append(apps_label)

  # ==========================================
  # SEARCH PANEL
  # ==========================================

  search_box = Gtk::Box.new(:vertical, 12)
  search_box.set_size_request(380, -1)
  search_box.valign = :start
  search_box.hexpand = true

  search_title = heading.call('Search SysScope')
  search_title.xalign = 0
  search_box.append(search_title)

  search_entry = Gtk::SearchEntry.new
  search_entry.placeholder_text = 'Search apps, CPU, RAM, Terminal...'
  search_box.append(search_entry)

  suggestions = Gtk::ListBox.new
  suggestions.selection_mode = :none

  search_scroll = Gtk::ScrolledWindow.new
  search_scroll.set_policy(:automatic, :automatic)
  search_scroll.set_size_request(380, 230)
  search_scroll.set_child(suggestions)

  search_box.append(search_scroll)

  # ==========================================
  # TERMINAL PANEL
  # ==========================================

  terminal_frame = Gtk::Frame.new
  terminal_frame.add_css_class('sysscope-terminal-panel')
  terminal_frame.set_child(create_terminal)
  terminal_frame.vexpand = true

  search_box.append(terminal_frame)

  # ==========================================
  # SEARCH DATA
  # ==========================================

  desktop_apps = sysscope_desktop_apps

  system_items = [
    {
      name: 'RAM Usage',
      detail: 'Memory usage and availability',
      icon: 'drive-harddisk',
      type: 'System'
    },
    {
      name: 'CPU Usage',
      detail: 'Processor utilization',
      icon: 'computer',
      type: 'System'
    },
    {
      name: 'Running Processes',
      detail: 'Active Linux processes',
      icon: 'utilities-system-monitor',
      type: 'System'
    },
    {
      name: 'Memory',
      detail: 'Total and available RAM',
      icon: 'media-floppy',
      type: 'System'
    },
    {
      name: 'Terminal',
      detail: 'Built-in Linux command runner',
      icon: 'utilities-terminal',
      type: 'System'
    }
  ]

  selected_search_result = nil

  refresh_search = nil

  refresh_search = proc do
    query = search_entry.text.to_s.strip.downcase

    while (child = suggestions.first_child)
      suggestions.remove(child)
    end

    unless query.empty?
      items = system_items + sysscope_running_apps(desktop_apps)

      matches = items.select do |item|
        item[:name].downcase.include?(query) ||
          item[:detail].downcase.include?(query) ||
          item[:type].downcase.include?(query)
      end

      matches = matches.uniq do |item|
        [item[:name], item[:type]]
      end

      matches.sort_by! do |item|
        name = item[:name].downcase

        [
          name.start_with?(query) ? 0 : 1,
          name.include?(query) ? 0 : 1,
          name
        ]
      end

      matches.first(30).each do |item|
        row = Gtk::Box.new(:horizontal, 12)

        row.margin_top = 8
        row.margin_bottom = 8
        row.margin_start = 10
        row.margin_end = 10

        icon = Gtk::Image.new
        icon.pixel_size = 32

        icon_name = item[:icon].to_s

        if File.file?(icon_name)
          icon.file = icon_name
        else
          icon.icon_name = icon_name.empty? ?
            'application-x-executable' : icon_name
        end

        row.append(icon)

        info = Gtk::Box.new(:vertical, 3)

        name_label = Gtk::Label.new(item[:name])
        name_label.xalign = 0

        detail_label = Gtk::Label.new(item[:detail])
        detail_label.xalign = 0
        detail_label.ellipsize = Pango::EllipsizeMode::END

        info.append(name_label)
        info.append(detail_label)

        row.append(info)

        result_id = [
          item[:name],
          item[:type],
          item[:detail]
        ]

        if selected_search_result == result_id
          row.add_css_class('sysscope-selected')
        end

        click = Gtk::GestureClick.new

        click.signal_connect('released') do
          if selected_search_result == result_id
            selected_search_result = nil
          else
            selected_search_result = result_id
          end

          refresh_search.call
        end

        row.add_controller(click)
        suggestions.append(row)
      end

      if matches.empty?
        suggestions.append(
          Gtk::Label.new(
            'No matching applications or information'
          )
        )
      end
    end
  end

  search_entry.signal_connect('search-changed') do
    refresh_search.call
  end

  GLib::Timeout.add(3000) do
    refresh_search.call unless search_entry.text.to_s.empty?
    GLib::Source::CONTINUE
  end

  # ==========================================
  # INFO PANEL WITH TWO-WAY SCROLLING
  # ==========================================

  info_scroll = Gtk::ScrolledWindow.new
  info_scroll.set_policy(:always, :always)
  info_scroll.set_size_request(420, 450)
  info_scroll.hexpand = true
  info_scroll.vexpand = true

  info_scroll.set_child(box)

  info_frame = Gtk::Frame.new
  info_frame.add_css_class('sysscope-info-panel')
  info_frame.set_child(info_scroll)

  # ==========================================
  # MAIN LAYOUT
  # ==========================================

  main_layout = Gtk::Box.new(:horizontal, 25)
  main_layout.hexpand = true
  main_layout.vexpand = true

  main_layout.margin_start = 20
  main_layout.margin_end = 20
  main_layout.margin_bottom = 20

  main_layout.append(info_frame)
  main_layout.append(search_box)

  # ==========================================
  # HEADER AND ICON
  # ==========================================

  header = Gtk::Box.new(:horizontal, 12)

  header.margin_top = 15
  header.margin_start = 20
  header.margin_bottom = 10

  icon_path = File.expand_path('sysscope.svg', __dir__)
  icon_path = File.expand_path('icon.png', __dir__) unless File.file?(icon_path)

  app_icon = Gtk::Image.new

  if File.file?(icon_path)
    app_icon.file = icon_path
  else
    app_icon.icon_name = 'utilities-system-monitor'
  end

  app_icon.set_pixel_size(48)

  app_title = Gtk::Label.new

  app_title.set_markup(
    '<span size="xx-large" weight="bold">SysScope</span>'
  )

  header.append(app_icon)
  header.append(app_title)

  root = Gtk::Box.new(:vertical, 0)
  root.append(header)
  root.append(main_layout)

  window.set_child(root)
  window.present

  # ==========================================
  # LIVE SYSTEM UPDATES
  # ==========================================

  previous_idle, previous_total = cpu_times

  update_stats = proc do
    idle, total = cpu_times

    idle_diff = idle - previous_idle
    total_diff = total - previous_total

    if total_diff > 0
      cpu_percent = (
        100.0 * (1.0 - idle_diff.to_f / total_diff)
      ).clamp(0, 100)
    end

    previous_idle = idle
    previous_total = total

    cpu_label.text = "CPU: #{cpu_percent.round(1)}%"
    dial.queue_draw

    ram = system_ram_usage
    ram_percent = ram[:percent]

    ram_label.text = "RAM: #{ram_percent}%"
    ram_bar.fraction = ram_percent / 100.0
    ram_bar.text = "#{ram_percent}%"

    ram_details.text =
      "#{ram[:used_mb].round} MB / #{ram[:total_mb].round} MB"

    apps_label.text =
      "Processes: #{system_process_count}"
  end

  update_stats.call

  GLib::Timeout.add(1000) do
    update_stats.call
    GLib::Source::CONTINUE
  end
end

app.run
