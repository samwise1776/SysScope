require 'open-uri'
require 'json'
require 'open3'
require 'fileutils'
require 'time'
require 'uri'

module SysScopeUpdater
  module_function

  DIR = File.join(Dir.home, '.sysscope')
  NOTIFICATIONS = File.join(DIR, 'notifications-missed.txt')
  INTERVAL = 300

  FileUtils.mkdir_p(DIR)

  def notify(title, message)
    entry = "[#{Time.now.iso8601}] #{title}: #{message}\n"
    File.open(NOTIFICATIONS, 'a', 0600) do |f|
      f.write(entry)
    end

    if system('which', 'notify-send',
              out: File::NULL, err: File::NULL)
      Process.spawn(
        'notify-send', title.to_s, message.to_s,
        out: File::NULL, err: File::NULL
      )
    end

    puts entry
    true
  end

  def git(*args)
    output, status = Open3.capture2e(
      'git', '-C', APP_DIR, *args
    )
    raise output.strip unless status.success?
    output.strip
  end

  def repository
    origin = git('remote', 'get-url', 'origin')

    match = origin.match(
      %r{\A(?:https://github\.com/|git@github\.com:)([\w.-]+/[\w.-]+?)(?:\.git)?/?\z}
    )

    raise 'GitHub origin not configured' unless match
    match[1]
  end

  def branch
    name = git('branch', '--show-current')
    raise 'Detached Git HEAD' if name.empty?
    name
  end

  def remote_sha
    repo = repository
    ref = URI.encode_www_form_component(branch)

    url = "https://api.github.com/repos/#{repo}/commits/#{ref}"

    response = URI.open(
      url,
      'User-Agent' => 'SysScope-Updater',
      'Accept' => 'application/vnd.github+json',
      open_timeout: 10,
      read_timeout: 15
    ) { |io| io.read }

    JSON.parse(response).fetch('sha')
  end

  def check
    local = git('rev-parse', 'HEAD')
    remote = remote_sha

    return :current if local == remote

    notify(
      'SysScope Update',
      "GitHub has a new update: #{remote[0, 8]}"
    )

    # Protect local modifications.
    unless git('status', '--porcelain', '--untracked-files=no').empty?
      notify(
        'SysScope Update Paused',
        'Local changes detected. Update skipped to protect your files.'
      )
      return :blocked
    end

    target = branch

    git('fetch', 'origin', target)
    git('merge', '--ff-only', 'FETCH_HEAD')

    :updated
  end

  def attach(window, app, header)
    generation = window.instance_variable_get(:@sysscope_generation)

    status = Gtk::Label.new('GitHub: Checking...')
    status.ellipsize = Pango::EllipsizeMode::END
    status.set_size_request(190, -1)
    status.tooltip_text = 'Automatic GitHub update status'

    header.append(status)

    checking = false

    perform_check = proc do
      unless checking
        checking = true

        Thread.new do
          begin
            result = check
            error = nil
          rescue StandardError => e
            result = :error
            error = e.message
          end

          GLib::Idle.add do
            active = window.instance_variable_get(
              :@sysscope_generation
            ) == generation

            if active
              case result
              when :current
                status.text = 'GitHub: Up to date'
              when :blocked
                status.text = 'Update: Local edits'
              when :updated
                status.text = 'Reloading SysScope...'

                begin
                  source = File.read(
                    File.join(APP_DIR, 'main.rb')
                  )

                  unless source.include?(
                    'SYSSCOPE_HOT_RELOAD_V1'
                  )
                    raise 'Updated main.rb lacks hot-reload support'
                  end

                  $sysscope_hot_load = true

                  begin
                    load File.join(APP_DIR, 'main.rb')
                  ensure
                    $sysscope_hot_load = false
                  end

                  # Rebuild UI inside the SAME GTK window.
                  sysscope_rebuild_ui(window, app)

                  notify(
                    'SysScope Updated',
                    'Update installed and window reloaded'
                  )
                rescue StandardError => e
                  notify('SysScope Reload Failed', e.message)
                  status.text = 'Reload failed'
                end
              else
                status.text = 'GitHub: Offline/Error'
                warn "Update check: #{error}"
              end
            end

            checking = false
            GLib::Source::REMOVE
          end
        end
      end
    end

    GLib::Timeout.add(1000) do
      if window.instance_variable_get(
        :@sysscope_generation
      ) != generation
        GLib::Source::REMOVE
      else
        perform_check.call
        GLib::Source::REMOVE
      end
    end

    GLib::Timeout.add(INTERVAL * 1000) do
      if window.instance_variable_get(
        :@sysscope_generation
      ) != generation
        GLib::Source::REMOVE
      else
        perform_check.call
        GLib::Source::CONTINUE
      end
    end
  end
end

def notify(title, message)
  SysScopeUpdater.notify(title, message)
end
