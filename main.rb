require 'gtk4'
require 'cairo'

cpu_percent = 0.0
ram_percent = 0.0

# ==========================================
# RAM USAGE
# ==========================================

def system_ram_usage
  mem_info = {}

  File.foreach('/proc/meminfo') do |line|
    if line =~ /^(MemTotal|MemAvailable|MemFree|Buffers|Cached):\s+(\d+)\s+kB/
      mem_info[$1] = $2.to_f / 1024.0
    end
  end

  total = mem_info.fetch('MemTotal')

  available = mem_info['MemAvailable'] || (
    mem_info.fetch('MemFree', 0) +
    mem_info.fetch('Buffers', 0) +
    mem_info.fetch('Cached', 0)
  )

  used = total - available

  {
    total_mb: total.round(2),
    used_mb: used.round(2),
    available_mb: available.round(2),
    percent: (used / total * 100).clamp(0, 100).round(2)
  }
end

# ==========================================
# CPU USAGE
# ==========================================

def cpu_times
  values = File.open('/proc/stat', &:readline)
               .split.drop(1).map(&:to_i)

  idle = values[3] + values[4]
  total = values.sum

  [idle, total]
end

# ==========================================
# PROCESS COUNT
# ==========================================

def system_process_count
  Dir.children('/proc').count do |entry|
    entry.match?(/\A\d+\z/)
  end
end

# ==========================================
# GTK4 APPLICATION
# ==========================================


# SYSSCOPE_SEARCH_START
require 'json'

def sysscope_desktop_apps
  apps = {}
  paths = [
    '/usr/share/applications',
    '/usr/local/share/applications',
    File.expand_path('~/.local/share/applications')
  ]

  paths.each do |directory|
    Dir.glob(File.join(directory, '*.desktop')).each do |file|
      begin
        data = {}
        File.foreach(file) do |line|
          break if line.strip == '[Desktop Action'
          if line =~ /^(Name|Icon|Exec|StartupWMClass)=(.*)$/
            data[$1] ||= $2.strip
          end
        end

        next unless data['Name']

        keys = [
          data['Name'],
          File.basename(file, '.desktop'),
          data['StartupWMClass'],
          data['Exec'].to_s.split.first
        ].compact

        keys.each do |key|
          apps[key.downcase] = {
            name: data['Name'],
            icon: data['Icon']
          }
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

  # Hyprland: actual open application windows
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
      # Use process fallback below
    end
  end

  # Fallback: running Linux processes
  if results.empty?
    Dir.glob('/proc/[0-9]*/comm').each do |file|
      begin
        process_name = File.read(file).strip
        next if process_name.empty?

        info = desktop_apps[process_name.downcase] || {}

        results << {
          name: info[:name] || process_name,
          detail: "Running process",
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
# SYSSCOPE_SEARCH_END

app = Gtk::Application.new('com.sysscope.app')

app.signal_connect('activate') do

# SysScope window icon
icon_dir = File.expand_path(__dir__)
Gtk::IconTheme.get_for_display(Gdk::Display.default)
              .add_search_path(icon_dir)

  window = Gtk::ApplicationWindow.new(app)
  window.title = 'SysScope'
  window.set_default_size(1000, 650)

  box = Gtk::Box.new(:vertical, 15)
  box.halign = :center
  box.valign = :center


  # SYSSCOPE_SELECTION_STYLE
  css_provider = Gtk::CssProvider.new
  css_provider.load(data: <<~CSS)
    .sysscope-selected {
      outline: 2px solid #4d99ff;
      outline-offset: -2px;
      border-radius: 8px;
      background-color: alpha(#4d99ff, 0.12);
    }
  CSS

  Gtk::StyleContext.add_provider_for_display(
    Gdk::Display.default,
    css_provider,
    Gtk::StyleProvider::PRIORITY_APPLICATION
  )

  search_box = Gtk::Box.new(:vertical, 15)

  # ==========================================
  # CPU DIAL
  # ==========================================

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
  # RAM SECTION
  # ==========================================

  ram_label = Gtk::Label.new('RAM: 0.0%')
  ram_details = Gtk::Label.new('0 MB / 0 MB')

  ram_bar = Gtk::ProgressBar.new
  ram_bar.set_size_request(350, 20)
  ram_bar.fraction = 0.0
  ram_bar.show_text = true

  # ==========================================
  # PROCESS SECTION
  # ==========================================

  apps_label = Gtk::Label.new('Processes: 0')

  # ==========================================
  # LAYOUT
  # ==========================================

  box.append(Gtk::Label.new.tap { |l|
    l.set_markup('<span size="xx-large" weight="bold">SysScope</span>')
  })
  box.append(Gtk::Label.new.tap { |l|
    l.set_markup('<span size="large" weight="bold">CPU Usage</span>')
  })
  box.append(dial)
  box.append(cpu_label)

  box.append(Gtk::Separator.new(:horizontal))

  box.append(Gtk::Label.new.tap { |l|
    l.set_markup('<span size="large" weight="bold">Memory Usage</span>')
  })
  box.append(ram_label)
  box.append(ram_bar)
  box.append(ram_details)

  box.append(Gtk::Separator.new(:horizontal))

  box.append(Gtk::Label.new.tap { |l|
    l.set_markup('<span size="large" weight="bold">Running Processes</span>')
  })
  box.append(apps_label)

  
  # SYSSCOPE_SEARCH_PANEL_START
  search_box = Gtk::Box.new(:vertical, 15)
  search_box.set_size_request(350, -1)
  search_box.valign = :center

  search_title = Gtk::Label.new
  search_title.set_markup(
    '<span size="x-large" weight="bold">Search SysScope</span>'
  )
  search_box.append(search_title)

  search_entry = Gtk::SearchEntry.new
  search_entry.placeholder_text = 'Search apps, CPU, RAM...'
  search_box.append(search_entry)

  suggestions = Gtk::ListBox.new
  suggestions.selection_mode = :none

  scroll = Gtk::ScrolledWindow.new
  scroll.set_size_request(350, 300)
  scroll.set_child(suggestions)
  search_box.append(scroll)

  desktop_apps = sysscope_desktop_apps

  system_items = [
    {
      name: 'RAM Usage',
      detail: 'Memory usage and availability',
      icon: 'media-floppy',
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
      icon: 'drive-harddisk',
      type: 'System'
    },
    {
      name: 'Terminal',
      detail: 'Run terminal commands',
      icon: 'utilities-terminal'
    }
  ]

  selected_search_result = nil

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
        result_id = [item[:name], item[:type], item[:detail]]

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
          Gtk::Label.new('No matching applications or information')
        )
      end
    end
  end

  search_entry.signal_connect('search-changed') do
    refresh_search.call
  end

  # Refresh matching applications every 3 seconds
  GLib::Timeout.add(3000) do
    refresh_search.call unless search_entry.text.to_s.empty?
    GLib::Source::CONTINUE
  end

  main_layout = Gtk::Box.new(:horizontal, 35)
  main_layout.halign = :center
  main_layout.valign = :center
  main_layout.margin_start = 25
  main_layout.margin_end = 25


  # SYSSCOPE_INFO_SCROLL_START

  # Blue outline around the information panel
  info_css = Gtk::CssProvider.new
  info_css.load(data: <<~CSS)
    .sysscope-info-panel {
      border: 2px solid #4d99ff;
      border-radius: 12px;
      background-color: alpha(#4d99ff, 0.04);
    }
  CSS

  Gtk::StyleContext.add_provider_for_display(
    Gdk::Display.default,
    info_css,
    Gtk::StyleProvider::PRIORITY_APPLICATION
  )

  # Allow scrolling in both directions
  info_scroll = Gtk::ScrolledWindow.new
  info_scroll.set_policy(:always, :always)
  info_scroll.set_size_request(420, 450)
  info_scroll.hexpand = true
  info_scroll.vexpand = true

  # Minimum content dimensions make both axes scrollable
  box.set_size_request(600, 700)
  box.halign = :start
  box.valign = :start
  box.margin_top = 20
  box.margin_bottom = 20
  box.margin_start = 20
  box.margin_end = 20

  info_scroll.set_child(box)

  # Keep the outline visible while scrolling
  info_frame = Gtk::Frame.new
  info_frame.add_css_class('sysscope-info-panel')
  info_frame.set_child(info_scroll)

  main_layout.append(info_frame)

  # SYSSCOPE_INFO_SCROLL_END

  main_layout.append(search_box)
  # SYSSCOPE_SEARCH_PANEL_END


  # SYSSCOPE_APP_HEADER
  header = Gtk::Box.new(:horizontal, 12)
  header.margin_top = 15
  header.margin_start = 20
  header.margin_bottom = 10

  app_icon = Gtk::Image.new
  app_icon.file = File.expand_path("sysscope.svg", __dir__)
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

  previous_idle, previous_total = cpu_times

  # ==========================================
  # LIVE UPDATE
  # ==========================================

  update_stats = proc do
    # CPU
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

    # RAM
    ram = system_ram_usage
    ram_percent = ram[:percent]

    ram_label.text = "RAM: #{ram_percent}%"
    ram_bar.fraction = ram_percent / 100.0
    ram_bar.text = "#{ram_percent}%"

    ram_details.text =
      "#{ram[:used_mb].round} MB / #{ram[:total_mb].round} MB"

    # PROCESSES
    apps_label.text = "Processes: #{system_process_count}"
  end

  # Show initial stats immediately
  update_stats.call

  # Refresh every second
  GLib::Timeout.add(1000) do
    update_stats.call
    GLib::Source::CONTINUE
  end
end

app.run