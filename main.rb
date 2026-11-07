require 'rbconfig'
require 'cgi'

require 'gtk4'
require 'cairo'
require 'json'
require 'open3'
require 'shellwords'

begin
  require 'gtksourceview5'
  SOURCE_AVAILABLE =
    !!(defined?(GtkSource::View) && defined?(GtkSource::Buffer))
rescue LoadError
  SOURCE_AVAILABLE = false
end

# ==================================================
# SYSSCOPE CONFIGURATION
# ==================================================

APP_DIR = File.expand_path(__dir__)
ASSET_DIR = File.join(APP_DIR, 'sysscope_assets')
EXTENSION_DIR = File.join(APP_DIR, 'extensions')

LANGUAGES = begin
  JSON.parse(
    File.read(File.join(ASSET_DIR, 'languages.json'))
  )
rescue StandardError
  []
end

LANGUAGE_ICONS = LANGUAGES.each_with_object({}) do |lang, result|
  result[lang['name']] =
    File.join(ASSET_DIR, lang['icon'].to_s)
end

FILE_LANGUAGES = {
  '.py' => 'Python',
  '.rb' => 'Ruby',
  '.js' => 'JavaScript',
  '.mjs' => 'JavaScript',
  '.cjs' => 'JavaScript',
  '.ts' => 'TypeScript',
  '.tsx' => 'TSX',
  '.jsx' => 'JSX',
  '.java' => 'Java',
  '.c' => 'C',
  '.h' => 'C',
  '.cpp' => 'C++',
  '.cc' => 'C++',
  '.cxx' => 'C++',
  '.hpp' => 'C++',
  '.cs' => 'C#',
  '.go' => 'Go',
  '.rs' => 'Rust',
  '.swift' => 'Swift',
  '.kt' => 'Kotlin',
  '.dart' => 'Dart',
  '.php' => 'PHP',
  '.pl' => 'Perl',
  '.lua' => 'Lua',
  '.r' => 'R',
  '.jl' => 'Julia',
  '.zig' => 'Zig',
  '.nim' => 'Nim',
  '.hs' => 'Haskell',
  '.scala' => 'Scala',
  '.ex' => 'Elixir',
  '.erl' => 'Erlang',
  '.clj' => 'Clojure',
  '.fs' => 'F#',
  '.ml' => 'OCaml',
  '.f90' => 'Fortran',
  '.asm' => 'Assembly',
  '.s' => 'Assembly',
  '.sh' => 'Bash',
  '.bash' => 'Bash',
  '.zsh' => 'Zsh',
  '.fish' => 'Fish',
  '.ps1' => 'PowerShell',
  '.html' => 'HTML',
  '.htm' => 'HTML',
  '.css' => 'CSS',
  '.scss' => 'SCSS',
  '.sass' => 'Sass',
  '.less' => 'Less',
  '.sql' => 'SQL',
  '.json' => 'JSON',
  '.yaml' => 'YAML',
  '.yml' => 'YAML',
  '.toml' => 'TOML',
  '.xml' => 'XML',
  '.md' => 'Markdown',
  '.tex' => 'LaTeX',
  '.gd' => 'GDScript',
  '.vue' => 'Vue',
  '.svelte' => 'Svelte',
  '.astro' => 'Astro',
  '.svg' => 'SVG',
  '.ini' => 'INI',
  '.cfg' => 'INI',
  '.conf' => 'INI',
  '.diff' => 'Diff'
}

SOURCE_IDS = {
  'C++' => 'cpp',
  'C#' => 'c-sharp',
  'JavaScript' => 'js',
  'TypeScript' => 'typescript',
  'Bash' => 'sh',
  'Assembly' => 'asm',
  'Python' => 'python',
  'Ruby' => 'ruby',
  'HTML' => 'html',
  'CSS' => 'css',
  'Rust' => 'rust',
  'JSON' => 'json',
  'YAML' => 'yaml',
  'Markdown' => 'markdown',
  'XML' => 'xml',
  'GDScript' => 'gdscript'
}

RUNNERS = {
  'Python' => ['python3'],
  'Ruby' => ['ruby'],
  'JavaScript' => ['node'],
  'Perl' => ['perl'],
  'Lua' => ['lua'],
  'Bash' => ['bash'],
  'PHP' => ['php'],
  'R' => ['Rscript'],
  'Dart' => ['dart', 'run'],
  'Go' => ['go', 'run'],
  'Julia' => ['julia'],
  'Swift' => ['swift']
}

# ==================================================
# HELPERS
# ==================================================

def language_for(path)
  name = File.basename(path)
  return 'Dockerfile' if name == 'Dockerfile'
  return 'Makefile' if name == 'Makefile'

  FILE_LANGUAGES.fetch(
    File.extname(path).downcase,
    'Plain Text'
  )
end

def language_icon(name)
  path = LANGUAGE_ICONS[name]
  File.file?(path.to_s) ? path : nil
end

def append_text(view, message)
  buffer = view.buffer
  buffer.insert(buffer.end_iter, message.to_s)
end

def make_heading(text, size = 'large')
  label = Gtk::Label.new
  label.set_markup(
    "<span size=\"#{size}\" weight=\"bold\">#{CGI.escapeHTML(text)}</span>"
  )
  label.xalign = 0
  label
end

def make_icon(name, size = 24)
  image = Gtk::Image.new
  image.icon_name = name
  image.pixel_size = size
  image
end

def make_language_image(name, size = 24)
  image = Gtk::Image.new
  path = language_icon(name)

  if path
    image.file = path
  else
    image.icon_name = 'text-x-generic'
  end

  image.pixel_size = size
  image
end

def choose_file(window, action, title, &callback)
  dialog = Gtk::FileChooserNative.new(
    title,
    window,
    action,
    '_OK',
    '_Cancel'
  )

  dialog.signal_connect('response') do |chooser, response|
    if response == Gtk::ResponseType::ACCEPT
      path = chooser.file&.path
      callback.call(path) if path
    end

    chooser.destroy
  end

  dialog.show
end


# ==========================================
# SYSSCOPE PLATFORM SUPPORT v1.0.1
# ==========================================

module SysScopePlatform
  module_function

  def mac?
    RbConfig::CONFIG['host_os'] =~ /darwin/i
  end

  def linux?
    RbConfig::CONFIG['host_os'] =~ /linux/i
  end

  def name
    return 'macOS' if mac?

    if linux?
      if File.exist?('/dev/.cros_milestone')
        return 'ChromeOS Linux'
      end

      if File.exist?('/etc/os-release')
        info = File.read('/etc/os-release')
        match = info.match(/^PRETTY_NAME="?([^"\\n]+)"?$/)
        return match[1] if match
      end

      return 'Linux'
    end

    RbConfig::CONFIG['host_os']
  end

  def capture(*command)
    IO.popen(command, err: File::NULL, &:read)
  rescue StandardError
    ''
  end

  def cpu_percent
    if mac?
      output = capture('top', '-l', '1', '-n', '0')
      match = output.match(
        /CPU usage:.*?([\\d.]+)% idle/i
      )

      return (100.0 - match[1].to_f).clamp(0, 100) if match
    end

    0.0
  end

  def memory
    if mac?
      total = capture('sysctl', '-n', 'hw.memsize').to_i
      return nil if total <= 0

      page_size = capture('pagesize').to_i
      page_size = 4096 if page_size <= 0

      stats = {}

      capture('vm_stat').each_line do |line|
        if line =~ /^(.+?):\\s+([\\d.]+)\\./
          stats[$1.strip] = $2.to_i
        end
      end

      available_pages = [
        'Pages free',
        'Pages inactive',
        'Pages speculative'
      ].sum { |key| stats.fetch(key, 0) }

      available = [
        available_pages * page_size,
        total
      ].min

      used = total - available

      return {
        total_mb: (total / 1048576.0).round(2),
        used_mb: (used / 1048576.0).round(2),
        available_mb: (available / 1048576.0).round(2),
        percent: (used.to_f / total * 100).clamp(0, 100).round(2)
      }
    end

    nil
  end

  def process_count
    output = capture('ps', '-e', '-o', 'pid=')
    output.lines.count { |line| line.strip.match?(/\\A\\d+\\z/) }
  end

  def running_processes(desktop_apps)
    results = []

    capture('ps', '-A', '-o', 'comm=').each_line do |line|
      executable = line.strip
      next if executable.empty?

      process_name = File.basename(executable)
      info = desktop_apps[process_name.downcase] || {}

      results << {
        name: info[:name] || process_name,
        detail: 'Running process',
        icon: info[:icon] || 'application-x-executable',
        type: 'Process'
      }
    end

    results.uniq { |item| [item[:name], item[:type]] }
  end
end

# ==================================================
# SYSTEM INFORMATION
# ==================================================

def system_ram_usage
  platform_memory = SysScopePlatform.memory
  return platform_memory if platform_memory
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
  return [0, 0] unless File.file?('/proc/stat')
  values = File.open('/proc/stat', &:readline)
               .split.drop(1)
               .map(&:to_i)

  idle = values[3] + values[4]

  [idle, values.sum]
end

def system_process_count
  unless File.directory?('/proc')
    return SysScopePlatform.process_count
  end
  Dir.children('/proc').count do |entry|
    entry.match?(/\A\d+\z/)
  end
end

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
        inside_entry = false

        File.foreach(file) do |line|
          line = line.strip

          if line.start_with?('[')
            inside_entry = line == '[Desktop Entry]'
            next
          end

          next unless inside_entry

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
  unless File.directory?('/proc')
    return SysScopePlatform.running_processes(desktop_apps)
  end
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
      # Fall back to processes.
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

# ==================================================
# TERMINAL
# ==================================================

class SysScopeTerminal
  attr_reader :panel

  def initialize
    @panel = Gtk::Box.new(:vertical, 8)
    @panel.hexpand = true
    @panel.vexpand = true

    @cwd = Dir.home
    @history = []
    @history_index = 0
    @busy = false

    @panel.append(make_heading('SysScope Terminal'))

    @output = Gtk::TextView.new
    @output.editable = false
    @output.cursor_visible = false
    @output.monospace = true
    @output.wrap_mode = :word_char

    @scroll = Gtk::ScrolledWindow.new
    @scroll.set_policy(:automatic, :automatic)
    @scroll.set_size_request(-1, 180)
    @scroll.hexpand = true
    @scroll.vexpand = true
    @scroll.set_child(@output)

    @panel.append(@scroll)

    row = Gtk::Box.new(:horizontal, 6)

    @entry = Gtk::Entry.new
    @entry.hexpand = true
    @entry.placeholder_text = 'Enter shell command...'

    @run_button = Gtk::Button.new(label: 'Run')
    clear_button = Gtk::Button.new(label: 'Clear')

    row.append(@entry)
    row.append(@run_button)
    row.append(clear_button)

    @panel.append(row)

    @status = Gtk::Label.new('Ready')
    @status.xalign = 0
    @panel.append(@status)

    write("SysScope Terminal\n#{@cwd}\n\n")

    @entry.signal_connect('activate') { execute }
    @run_button.signal_connect('clicked') { execute }

    clear_button.signal_connect('clicked') do
      @output.buffer.text = ''
    end

    keys = Gtk::EventControllerKey.new

    keys.signal_connect('key-pressed') do |_controller, key, _code, _state|
      case Gdk::Keyval.to_name(key)
      when 'Up'
        unless @history.empty?
          @history_index = [@history_index - 1, 0].max
          @entry.text = @history[@history_index]
          @entry.set_position(-1)
        end
        true

      when 'Down'
        unless @history.empty?
          @history_index = [
            @history_index + 1,
            @history.length
          ].min

          @entry.text =
            @history_index == @history.length ?
              '' : @history[@history_index]

          @entry.set_position(-1)
        end
        true

      else
        false
      end
    end

    @entry.add_controller(keys)
  end

  def write(message)
    append_text(@output, message)
  end

  def async_write(message)
    GLib::Idle.add do
      write(message)

      adjustment = @scroll.vadjustment
      adjustment.value = adjustment.upper

      GLib::Source::REMOVE
    end
  end

  def execute
    command = @entry.text.strip
    return if command.empty? || @busy

    @entry.text = ''
    @history << command
    @history_index = @history.length

    write("#{@cwd} $ #{command}\n")

    case command
    when 'clear'
      @output.buffer.text = ''
      return
    when 'pwd'
      write("#{@cwd}\n")
      return
    when 'history'
      @history.each_with_index do |item, index|
        write("#{index + 1}: #{item}\n")
      end
      return
    end

    if command == 'cd' || command.start_with?('cd ')
      begin
        args = Shellwords.split(command)
        raise ArgumentError, 'too many arguments' if args.length > 2

        target = args[1] || Dir.home
        target = Dir.home + target[1..] if target.start_with?('~')

        directory = File.expand_path(target, @cwd)

        if File.directory?(directory)
          @cwd = directory
          write("#{@cwd}\n")
        else
          write("cd: directory not found\n")
        end
      rescue StandardError => e
        write("cd: #{e.message}\n")
      end

      return
    end

    @busy = true
    @entry.sensitive = false
    @run_button.sensitive = false
    @status.text = 'Running...'

    cwd = @cwd.dup

    Thread.new do
      begin
        Open3.popen2e(
          '/bin/sh', '-c', command,
          chdir: cwd
        ) do |stdin, stdout, process|
          stdin.close

          stdout.each_line do |line|
            async_write(line)
          end

          status = process.value
          async_write("\nExit: #{status.exitstatus || 'signal'}\n")
        end
      rescue StandardError => e
        async_write("Error: #{e.message}\n")
      ensure
        GLib::Idle.add do
          @busy = false
          @entry.sensitive = true
          @run_button.sensitive = true
          @status.text = 'Ready'
          GLib::Source::REMOVE
        end
      end
    end
  end
end

# ==================================================
# SYSSCOPE IDE
# ==================================================

class SysScopeIDE
  attr_reader :panel

  def initialize(window, &exit_full_mode)
    @window = window
    @exit_full_mode = exit_full_mode

    @tabs = []
    @current = nil
    @changing_language = false
    @running = false

    @language_names = LANGUAGES.map { |l| l['name'] }

    @extension_runners = {}
    @extension_languages = {}

    load_extensions

    @panel = Gtk::Box.new(:vertical, 8)
    @panel.hexpand = true
    @panel.vexpand = true

    build_toolbar
    build_main_area
    build_output

    new_file
  end

  # ------------------------------------------
  # LOCAL EXTENSIONS
  # ------------------------------------------

  def load_extensions
    Dir.mkdir(EXTENSION_DIR) unless Dir.exist?(EXTENSION_DIR)

    @loaded_extensions = []

    Dir.glob(File.join(EXTENSION_DIR, '*.json')).each do |file|
      begin
        extension = JSON.parse(File.read(file))

        if extension['runners'].is_a?(Hash)
          extension['runners'].each do |language, command|
            next unless command.is_a?(Array)
            next unless command.all? { |part| part.is_a?(String) }

            @extension_runners[language] = command
          end
        end

        if extension['file_extensions'].is_a?(Hash)
          extension['file_extensions'].each do |suffix, language|
            @extension_languages[suffix.downcase] = language
          end
        end

        @loaded_extensions << (
          extension['name'] || File.basename(file)
        )
      rescue StandardError => e
        warn "Extension error in #{file}: #{e.message}"
      end
    end
  end

  def detect_language(path)
    suffix = File.extname(path).downcase

    @extension_languages[suffix] || language_for(path)
  end

  # ------------------------------------------
  # TOOLBAR
  # ------------------------------------------

  def add_button(row, label, &block)
    button = Gtk::Button.new(label: label)
    button.signal_connect('clicked', &block)
    row.append(button)
    button
  end

  def build_toolbar
    toolbar = Gtk::Box.new(:horizontal, 6)

    add_button(toolbar, 'New') { new_file }
    add_button(toolbar, 'Open') { open_file }
    add_button(toolbar, 'Save') { save_file }
    add_button(toolbar, 'Save As') { save_as }
    add_button(toolbar, 'Run') { run_file }
    add_button(toolbar, 'Close Tab') { close_tab }

    @panel.append(toolbar)

    language_row = Gtk::Box.new(:horizontal, 8)

    @selected_icon = Gtk::Image.new
    @selected_icon.pixel_size = 28
    language_row.append(@selected_icon)

    @language_selector = Gtk::DropDown.new(@language_names)
    @language_selector.set_size_request(220, -1)

    @language_selector.signal_connect('notify::selected') do
      next if @changing_language || !@current

      index = @language_selector.selected
      language = @language_names[index]

      next unless language

      @current[:language] = language
      apply_language(@current)
      update_language_icon
    end

    language_row.append(@language_selector)

    @language_count = Gtk::Label.new(
      "#{LANGUAGES.length} languages loaded"
    )

    language_row.append(@language_count)

    @panel.append(language_row)
  end

  # ------------------------------------------
  # EDITOR AREA
  # ------------------------------------------

  def build_main_area
    @notebook = Gtk::Notebook.new
    @notebook.hexpand = true
    @notebook.vexpand = true
    @notebook.scrollable = true

    @notebook.signal_connect('switch-page') do |_book, _page, index|
      @current = @tabs[index]
      update_language
    end

    @panel.append(@notebook)
  end

  def build_output
    @status = Gtk::Label.new('Ready')
    @status.xalign = 0

    @panel.append(@status)

    output_header = Gtk::Box.new(:horizontal, 6)

    output_header.append(make_heading('Program Output'))

    clear = Gtk::Button.new(label: 'Clear')

    clear.signal_connect('clicked') do
      @output.buffer.text = ''
    end

    output_header.append(clear)
    @panel.append(output_header)

    @output = Gtk::TextView.new
    @output.editable = false
    @output.cursor_visible = false
    @output.monospace = true
    @output.wrap_mode = :word_char

    @output_scroll = Gtk::ScrolledWindow.new
    @output_scroll.set_policy(:automatic, :automatic)
    @output_scroll.set_size_request(-1, 150)
    @output_scroll.set_child(@output)

    @panel.append(@output_scroll)
  end

  # ------------------------------------------
  # EDITOR BUFFER
  # ------------------------------------------

  def make_buffer
    if SOURCE_AVAILABLE
      GtkSource::Buffer.new
    else
      Gtk::TextBuffer.new
    end
  end

  def make_view(buffer)
    if SOURCE_AVAILABLE
      view = GtkSource::View.new_with_buffer(buffer)

      view.show_line_numbers = true
      view.highlight_current_line = true
      view.auto_indent = true
      view.insert_spaces_instead_of_tabs = true
      view.tab_width = 4
    else
      view = Gtk::TextView.new
      view.buffer = buffer
    end

    view.monospace = true
    view.wrap_mode = :none

    view
  end

  # ------------------------------------------
  # TABS
  # ------------------------------------------

  def tab_title(tab)
    tab[:path] ? File.basename(tab[:path]) : 'Untitled'
  end

  def refresh_tab_label(tab)
    tab[:title].text =
      (tab[:dirty] ? '* ' : '') + tab_title(tab)

    path = language_icon(tab[:language])

    if path
      tab[:icon].file = path
    else
      tab[:icon].icon_name = 'text-x-generic'
    end
  end

  def new_file(path = nil, content = '')
    buffer = make_buffer
    buffer.text = content

    view = make_view(buffer)

    scroll = Gtk::ScrolledWindow.new
    scroll.set_policy(:automatic, :automatic)
    scroll.hexpand = true
    scroll.vexpand = true
    scroll.set_child(view)

    tab_header = Gtk::Box.new(:horizontal, 5)

    icon = Gtk::Image.new
    icon.pixel_size = 18

    title = Gtk::Label.new('Untitled')

    tab_header.append(icon)
    tab_header.append(title)

    tab = {
      path: path,
      buffer: buffer,
      view: view,
      scroll: scroll,
      title: title,
      icon: icon,
      language: path ? detect_language(path) : 'Python',
      dirty: false
    }

    @tabs << tab

    @notebook.append_page(scroll, tab_header)
    @notebook.page = @tabs.length - 1

    @current = tab

    buffer.signal_connect('changed') do
      tab[:dirty] = true
      refresh_tab_label(tab)
    end

    refresh_tab_label(tab)
    apply_language(tab)
    update_language

    view.grab_focus
  end

  def close_tab
    return unless @current

    if @current[:dirty]
      @status.text = 'Save unsaved changes before closing'
      return
    end

    index = @tabs.index(@current)
    return unless index

    @notebook.remove_page(index)
    @tabs.delete_at(index)

    if @tabs.empty?
      @current = nil
      new_file
    else
      @current = @tabs[@notebook.page]
      update_language
    end
  end

  # ------------------------------------------
  # SYNTAX HIGHLIGHTING
  # ------------------------------------------

  def apply_language(tab)
    return unless SOURCE_AVAILABLE

    manager = GtkSource::LanguageManager.default

    id = SOURCE_IDS.fetch(
      tab[:language],
      tab[:language].downcase.gsub(/[^a-z0-9]+/, '-')
    )

    language = manager.get_language(id)

    if !language && tab[:path]
      language = manager.guess_language(tab[:path], nil)
    end

    tab[:buffer].language = language
    tab[:buffer].highlight_syntax = true
  rescue StandardError => e
    @status.text = "Highlight error: #{e.message}" if @status
  end

  def update_language_icon
    return unless @current

    path = language_icon(@current[:language])

    if path
      @selected_icon.file = path
    else
      @selected_icon.icon_name = 'text-x-generic'
    end

    refresh_tab_label(@current)
  end

  def update_language
    return unless @current

    @changing_language = true

    index = @language_names.index(@current[:language])
    @language_selector.selected = index if index

    @changing_language = false

    update_language_icon

    highlighter = SOURCE_AVAILABLE ?
      'GtkSourceView' : 'Plain text'

    @status.text =
      "#{tab_title(@current)} | #{@current[:language]} | #{highlighter}"
  end

  # ------------------------------------------
  # OPEN AND SAVE
  # ------------------------------------------

  def open_file
    choose_file(@window, :open, 'Open source file') do |path|
      begin
        content = File.read(path, encoding: 'UTF-8')

        existing = @tabs.find { |tab| tab[:path] == path }

        if existing
          @notebook.page = @tabs.index(existing)
        else
          new_file(path, content)
        end
      rescue StandardError => e
        @status.text = "Open error: #{e.message}"
      end
    end
  end

  def save_file
    return unless @current

    unless @current[:path]
      save_as
      return
    end

    write_file(@current, @current[:path])
  end

  def save_as
    return unless @current

    tab = @current

    choose_file(@window, :save, 'Save source file') do |path|
      write_file(tab, path)
    end
  end

  def write_file(tab, path)
    File.write(path, tab[:buffer].text)

    tab[:path] = path
    tab[:language] = detect_language(path)
    tab[:dirty] = false

    refresh_tab_label(tab)
    apply_language(tab)
    update_language if tab == @current

    @status.text = "Saved #{path}"
  rescue StandardError => e
    @status.text = "Save error: #{e.message}"
  end

  # ------------------------------------------
  # RUN PROGRAM
  # ------------------------------------------

  def run_file
    tab = @current
    return unless tab
    return if @running

    if tab[:dirty] || !tab[:path]
      @status.text = 'Save the file before running'
      return
    end

    interpreter =
      @extension_runners[tab[:language]] ||
      RUNNERS[tab[:language]]

    unless interpreter
      @status.text =
        "No runner configured for #{tab[:language]}"
      return
    end

    @running = true
    @status.text = 'Running...'
    @output.buffer.text = ''

    path = tab[:path].dup
    args = interpreter + [path]

    append_text(
      @output,
      "Running #{File.basename(path)}\n\n"
    )

    Thread.new do
      begin
        Open3.popen2e(
          *args,
          chdir: File.dirname(path)
        ) do |stdin, stdout, process|
          stdin.close

          stdout.each_line do |line|
            GLib::Idle.add do
              append_text(@output, line)
              GLib::Source::REMOVE
            end
          end

          result = process.value

          GLib::Idle.add do
            @status.text =
              "Exit status: #{result.exitstatus || 'signal'}"

            append_text(
              @output,
              "\nProcess finished.\n"
            )

            GLib::Source::REMOVE
          end
        end
      rescue StandardError => e
        GLib::Idle.add do
          @status.text = "Run error: #{e.message}"
          GLib::Source::REMOVE
        end
      ensure
        GLib::Idle.add do
          @running = false
          GLib::Source::REMOVE
        end
      end
    end
  end

  # ------------------------------------------
  # EXTENSION INFORMATION
  # ------------------------------------------

  def extension_count
    @loaded_extensions.length
  end
end

# ==================================================
# GTK4 APPLICATION
# ==================================================


require 'openssl'
require 'securerandom'
require 'net/smtp'
require 'base64'
require 'fileutils'

module SysScopeAuth
  module_function

  DIR = File.join(Dir.home, '.config', 'sysscope')
  FILE = File.join(DIR, 'accounts.json')

  def accounts
    File.exist?(FILE) ? JSON.parse(File.read(FILE)) : {}
  end

  def save(data)
    FileUtils.mkdir_p(DIR)
    File.chmod(0700, DIR)
    File.open(FILE, File::WRONLY | File::CREAT | File::TRUNC, 0600) do |f|
      f.write(JSON.pretty_generate(data))
    end
  end

  def valid_email?(address)
    !!(address =~ /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
  end

  def register(address, password)
    address = address.strip.downcase
    raise 'Invalid email address' unless valid_email?(address)
    raise 'Password must have at least 8 characters' if password.length < 8

    data = accounts
    raise 'Account already exists' if data.key?(address)

    salt = SecureRandom.random_bytes(16)
    iterations = 300_000
    hash = OpenSSL::PKCS5.pbkdf2_hmac(
      password, salt, iterations, 32, 'sha256'
    )

    data[address] = {
      'salt' => salt.unpack1('H*'),
      'hash' => hash.unpack1('H*'),
      'iterations' => iterations
    }
    save(data)
    true
  end

  def login(address, password)
    record = accounts[address.strip.downcase]
    return false unless record

    salt = [record.fetch('salt')].pack('H*')
    expected = [record.fetch('hash')].pack('H*')

    actual = OpenSSL::PKCS5.pbkdf2_hmac(
      password, salt, record.fetch('iterations'), 32, 'sha256'
    )

    actual.bytesize == expected.bytesize &&
      OpenSSL.fixed_length_secure_compare(actual, expected)
  rescue KeyError, ArgumentError
    false
  end
end

# Send HTML email with a clickable button.
# Configure SMTP_HOST, SMTP_PORT, SMTP_USER,
# SMTP_PASSWORD and SMTP_FROM in your environment.
def email(address, button_url, content, btnText)
  raise 'Invalid recipient email' unless SysScopeAuth.valid_email?(address)
  raise 'Button URL must use HTTPS' unless button_url.start_with?('https://')

  require 'uri'
  uri = URI.parse(button_url)
  raise 'Invalid HTTPS URL' unless uri.is_a?(URI::HTTPS) && uri.host

  host = ENV.fetch('SMTP_HOST')
  port = Integer(ENV.fetch('SMTP_PORT', '587'))
  user = ENV.fetch('SMTP_USER')
  password = ENV.fetch('SMTP_PASSWORD')
  sender = ENV.fetch('SMTP_FROM', user)

  raise 'Invalid sender email' unless SysScopeAuth.valid_email?(sender)

  html = <<~HTML
    <html>
      <body style="font-family:sans-serif;padding:30px">
        <h1>SysScope</h1>
        <p>#{CGI.escapeHTML(content.to_s).gsub("\n", '<br>')}</p>
        <p>
          <a href="#{CGI.escapeHTML(button_url)}"
             style="background:#4d99ff;color:white;padding:14px 24px;
                    border-radius:8px;text-decoration:none;display:inline-block">
            #{CGI.escapeHTML(btnText.to_s)}
          </a>
        </p>
      </body>
    </html>
  HTML

  message = [
    "From: #{sender}",
    "To: #{address}",
    "Subject: SysScope",
    "MIME-Version: 1.0",
    "Content-Type: text/html; charset=UTF-8",
    "Content-Transfer-Encoding: base64",
    "",
    Base64.strict_encode64(html)
  ].join("\r\n")

  smtp = Net::SMTP.new(host, port)
  smtp.enable_starttls
  smtp.start('localhost', user, password, :login) do |connection|
    connection.send_message(message, sender, address)
  end

  true
end

app = Gtk::Application.new('com.sysscope.app')

app.signal_connect('activate') do
  window = Gtk::ApplicationWindow.new(app)

  window.title = "SysScope 1.0.1 — #{SysScopePlatform.name}"
  window.set_default_size(1250, 800)

  theme = Gtk::IconTheme.get_for_display(
    Gdk::Display.default
  )

  theme.add_search_path(APP_DIR)

  # ==================================================
  # STYLES
  # ==================================================

  css = Gtk::CssProvider.new

  css.load(data: <<~CSS)
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

    .sysscope-search-panel {
      padding: 10px;
    }
  CSS

  Gtk::StyleContext.add_provider_for_display(
    Gdk::Display.default,
    css,
    Gtk::StyleProvider::PRIORITY_APPLICATION
  )

  # ==================================================
  # ROOT AND HEADER
  # ==================================================

  root = Gtk::Box.new(:vertical, 0)

  header = Gtk::Box.new(:horizontal, 12)
  header.margin_top = 12
  header.margin_bottom = 12
  header.margin_start = 20
  header.margin_end = 20

  app_icon = Gtk::Image.new

  icon_path = File.join(APP_DIR, 'sysscope.svg')
  icon_path = File.join(APP_DIR, 'icon.png') unless File.file?(icon_path)

  if File.file?(icon_path)
    app_icon.file = icon_path
  else
    app_icon.icon_name = 'utilities-system-monitor'
  end

  app_icon.pixel_size = 42

  header.append(app_icon)
  header.append(make_heading('SysScope', 'xx-large'))

  root.append(header)

  # ==================================================
  # MAIN TABS
  # ==================================================

  main_tabs = Gtk::Notebook.new
  main_tabs.hexpand = true
  main_tabs.vexpand = true
  main_tabs.scrollable = true

  root.append(main_tabs)

  # ==================================================
  # SYSTEM MONITOR PAGE
  # ==================================================

  monitor_page = Gtk::Box.new(:vertical, 8)
  monitor_page.hexpand = true
  monitor_page.vexpand = true

  monitor_layout = Gtk::Box.new(:horizontal, 25)
  monitor_layout.hexpand = true
  monitor_layout.vexpand = true

  monitor_layout.margin_start = 20
  monitor_layout.margin_end = 20
  monitor_layout.margin_top = 12
  monitor_layout.margin_bottom = 15

  # ==================================================
  # ORIGINAL SYSTEM INFORMATION PANEL
  # ==================================================

  info_box = Gtk::Box.new(:vertical, 15)

  info_box.set_size_request(600, 750)
  info_box.halign = :center
  info_box.valign = :start

  info_box.margin_top = 20
  info_box.margin_bottom = 20
  info_box.margin_start = 20
  info_box.margin_end = 20

  info_box.append(make_heading('SysScope System Information', 'x-large'))

  # ==================================================
  # CPU DIAL
  # ==================================================

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
        cx,
        cy,
        radius,
        -Math::PI / 2,
        -Math::PI / 2 +
          2 * Math::PI * cpu_percent / 100.0
      )

      cr.stroke
    end
  end

  cpu_label = Gtk::Label.new('CPU: 0.0%')

  cpu_bar = Gtk::ProgressBar.new
  cpu_bar.set_size_request(350, 20)
  cpu_bar.show_text = true

  info_box.append(make_heading('CPU Usage'))
  info_box.append(dial)
  info_box.append(cpu_label)
  info_box.append(cpu_bar)

  info_box.append(Gtk::Separator.new(:horizontal))

  # ==================================================
  # RAM INFORMATION
  # ==================================================

  ram_label = Gtk::Label.new('RAM: 0.0%')
  ram_details = Gtk::Label.new('0 MB / 0 MB')

  ram_bar = Gtk::ProgressBar.new
  ram_bar.set_size_request(350, 20)
  ram_bar.show_text = true

  info_box.append(make_heading('Memory Usage'))
  info_box.append(ram_label)
  info_box.append(ram_bar)
  info_box.append(ram_details)

  info_box.append(Gtk::Separator.new(:horizontal))

  # ==================================================
  # PROCESS INFORMATION
  # ==================================================

  process_label = Gtk::Label.new('Processes: 0')

  info_box.append(make_heading('Running Processes'))
  info_box.append(process_label)

  # ==================================================
  # TWO-WAY SCROLLING AND OUTLINE
  # ==================================================

  info_scroll = Gtk::ScrolledWindow.new

  info_scroll.set_policy(:always, :always)
  info_scroll.set_size_request(420, 450)

  info_scroll.hexpand = true
  info_scroll.vexpand = true

  info_scroll.set_child(info_box)

  info_frame = Gtk::Frame.new
  info_frame.add_css_class('sysscope-info-panel')
  info_frame.set_child(info_scroll)

  monitor_layout.append(info_frame)

  # ==================================================
  # SEARCH AND TERMINAL PANEL
  # ==================================================

  side_panel = Gtk::Box.new(:vertical, 12)
  side_panel.hexpand = true
  side_panel.vexpand = true

  side_panel.set_size_request(350, -1)

  side_panel.append(
    make_heading('Search SysScope', 'x-large')
  )

  search = Gtk::SearchEntry.new

  search.placeholder_text =
    'Search apps, CPU, RAM, Terminal, IDE...'

  side_panel.append(search)

  results = Gtk::ListBox.new
  results.selection_mode = :none

  results_scroll = Gtk::ScrolledWindow.new
  results_scroll.set_policy(:automatic, :automatic)
  results_scroll.set_size_request(350, 250)
  results_scroll.set_child(results)

  side_panel.append(results_scroll)

  # ==================================================
  # TERMINAL IN MONITOR PAGE
  # ==================================================

  terminal = SysScopeTerminal.new

  terminal_frame = Gtk::Frame.new
  terminal_frame.add_css_class('sysscope-terminal-panel')
  terminal_frame.set_child(terminal.panel)

  terminal_frame.vexpand = true

  side_panel.append(terminal_frame)

  monitor_layout.append(side_panel)
  monitor_page.append(monitor_layout)

  main_tabs.append_page(
    monitor_page,
    Gtk::Label.new('System Information')
  )

  # ==================================================
  # FULL IDE PAGE
  # ==================================================

  ide_page = Gtk::Box.new(:vertical, 8)
  ide_page.hexpand = true
  ide_page.vexpand = true

  ide_page.margin_start = 12
  ide_page.margin_end = 12
  ide_page.margin_top = 10
  ide_page.margin_bottom = 10

  ide_header = Gtk::Box.new(:horizontal, 10)

  ide_header.append(make_heading('SysScope IDE', 'x-large'))

  full_ide = false

  full_button = Gtk::Button.new(label: 'Full IDE Mode')
  back_button = Gtk::Button.new(label: 'System Information')

  ide_header.append(full_button)
  ide_header.append(back_button)

  ide_page.append(ide_header)

  ide = SysScopeIDE.new(window)

  ide_page.append(ide.panel)

  main_tabs.append_page(
    ide_page,
    Gtk::Label.new('IDE')
  )

  full_button.signal_connect('clicked') do
    full_ide = !full_ide

    if full_ide
      window.fullscreen
      header.visible = false
      main_tabs.show_tabs = false
      full_button.label = 'Exit Full IDE Mode'
    else
      window.unfullscreen
      header.visible = true
      main_tabs.show_tabs = true
      full_button.label = 'Full IDE Mode'
    end
  end

  back_button.signal_connect('clicked') do
    if full_ide
      full_ide = false
      window.unfullscreen
      header.visible = true
      main_tabs.show_tabs = true
      full_button.label = 'Full IDE Mode'
    end

    main_tabs.page = 0
  end

  # ==================================================
  # SEARCH RESULTS
  # ==================================================

  desktop_apps = sysscope_desktop_apps

  system_items = [
    {
      name: 'CPU Usage',
      detail: 'Live processor utilization',
      icon: 'computer',
      type: 'System'
    },
    {
      name: 'RAM Usage',
      detail: 'Memory usage and availability',
      icon: 'drive-harddisk',
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
      detail: 'Built-in Linux shell',
      icon: 'utilities-terminal',
      type: 'System'
    },
    {
      name: 'SysScope IDE',
      detail: "#{LANGUAGES.length} language icons, editor, extensions",
      icon: 'applications-development',
      type: 'IDE'
    }
  ]

  selected_search_result = nil

  refresh_search = nil

  refresh_search = proc do
    query = search.text.to_s.strip.downcase

    while (child = results.first_child)
      results.remove(child)
    end

    unless query.empty?
      items = system_items +
        sysscope_running_apps(desktop_apps)

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

        image = make_icon(
          item[:icon].to_s.empty? ?
            'application-x-executable' : item[:icon],
          32
        )

        row.append(image)

        details = Gtk::Box.new(:vertical, 3)

        name_label = Gtk::Label.new(item[:name])
        name_label.xalign = 0

        detail_label = Gtk::Label.new(item[:detail])
        detail_label.xalign = 0
        detail_label.ellipsize = Pango::EllipsizeMode::END

        details.append(name_label)
        details.append(detail_label)

        row.append(details)

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

          if item[:name] == 'SysScope IDE'
            main_tabs.page = 1
          end

          refresh_search.call
        end

        row.add_controller(click)

        results.append(row)
      end

      if matches.empty?
        results.append(
          Gtk::Label.new(
            'No matching applications or information'
          )
        )
      end
    end
  end

  search.signal_connect('search-changed') do
    refresh_search.call
  end

  GLib::Timeout.add(3000) do
    refresh_search.call unless search.text.to_s.empty?
    GLib::Source::CONTINUE
  end

  # ==================================================
  # LIVE SYSTEM MONITOR
  # ==================================================

  previous_idle, previous_total = cpu_times

  update_stats = proc do
    idle, total = cpu_times

    idle_diff = idle - previous_idle
    total_diff = total - previous_total

    if SysScopePlatform.mac?
      cpu_percent = SysScopePlatform.cpu_percent
    elsif total_diff > 0
      cpu_percent = (
        100.0 * (
          1.0 - idle_diff.to_f / total_diff
        )
      ).clamp(0, 100)
    end

    previous_idle = idle
    previous_total = total

    cpu_label.text =
      "CPU: #{cpu_percent.round(1)}%"

    cpu_bar.fraction = cpu_percent / 100.0
    cpu_bar.text = "#{cpu_percent.round(1)}%"

    dial.queue_draw

    ram = system_ram_usage
    ram_percent = ram[:percent]

    ram_label.text = "RAM: #{ram_percent}%"
    ram_bar.fraction = ram_percent / 100.0
    ram_bar.text = "#{ram_percent}%"

    ram_details.text =
      "#{ram[:used_mb].round} MB / #{ram[:total_mb].round} MB"

    process_label.text =
      "Processes: #{system_process_count}"
  end

  update_stats.call

  GLib::Timeout.add(1000) do
    update_stats.call
    GLib::Source::CONTINUE
  end

  # ==================================================
  # SHOW WINDOW
  # ==================================================

  
# ==========================================
# ACCOUNT INTERFACE
# ==========================================

auth_page = Gtk::Box.new(:vertical, 14)
auth_page.halign = :center
auth_page.valign = :center
auth_page.set_size_request(370, -1)

auth_page.append(make_heading('SysScope Account', 'xx-large'))
auth_page.append(Gtk::Label.new('Sign in to continue'))

email_entry = Gtk::Entry.new
email_entry.placeholder_text = 'Email address'
auth_page.append(email_entry)

password_entry = Gtk::PasswordEntry.new
password_entry.placeholder_text = 'Password (8+ characters)'
auth_page.append(password_entry)

status_label = Gtk::Label.new('')
status_label.wrap = true

signin_button = Gtk::Button.new(label: 'Sign In')
signup_button = Gtk::Button.new(label: 'Create Account')

auth_page.append(signin_button)
auth_page.append(signup_button)
auth_page.append(status_label)

account_label = Gtk::Label.new('')

signout_button = Gtk::Button.new(label: 'Sign Out')
header.append(account_label)
header.append(signout_button)

signed_in = proc do |address|
  require 'fileutils'

  dir = File.join(Dir.home, '.sysscope')
  FileUtils.mkdir_p(dir)
  File.chmod(0700, dir)

  account = SysScopeAuth.accounts[address.strip.downcase]
  raise 'Account not found' unless account

  email_path = File.join(dir, 'email.txt')
  password_path = File.join(dir, 'usr-sys-password.txt')

  File.write(email_path, address)
  File.write(password_path, account.fetch('hash'))

  File.chmod(0600, email_path)
  File.chmod(0600, password_path)

  account_label.text = address
  password_entry.text = ''
  window.set_child(root)
end

signin_button.signal_connect('clicked') do
  address = email_entry.text.strip.downcase
  password = password_entry.text

  if SysScopeAuth.login(address, password)
    signed_in.call(address)
  else
    status_label.text = 'Incorrect email or password'
  end
end

signup_button.signal_connect('clicked') do
  begin
    address = email_entry.text.strip.downcase
    SysScopeAuth.register(address, password_entry.text)
    signed_in.call(address)
  rescue StandardError => e
    status_label.text = e.message
  end
end

password_entry.signal_connect('activate') do
  signin_button.emit('clicked')
end

signout_button.signal_connect('clicked') do
  account_label.text = ''
  email_entry.text = ''
  password_entry.text = ''
  status_label.text = ''
  window.set_child(auth_page)
end

window.set_child(auth_page)
window.present
end

app.run
