# SysScope v1.0.1

## Supported environments

### Arch Linux / Omarchy
Install GTK4, Ruby GTK4 bindings, Cairo and optional GtkSourceView 5.
Use the existing install.sh.

### Ubuntu / Xubuntu / Debian
Install GTK4 introspection packages, Ruby GTK4 bindings,
Cairo and optional GtkSourceView 5.
Use install.sh if its installer supports the distribution,
or run main.rb directly.

### ChromeOS
Enable the Linux development environment (Crostini).
Install Linux GTK4 and Ruby dependencies inside the container.
Run SysScope inside the Linux environment.

### macOS
Supports Intel and Apple Silicon macOS with GTK4 and Ruby.
Run install-macos.sh to install dependencies and copy the app.

The macOS installer does not create a native .app bundle.

### Fedora and other Linux distributions
Install the distribution's GTK4 dependencies and Ruby bindings.
Run main.rb directly or adapt install.sh.

### Windows
Use WSLg with the Linux dependencies.
Native Windows support is not included.

## Features

- CPU monitor
- RAM monitor
- Process monitor
- Application search
- Built-in shell command runner
- Multi-tab IDE
- Language icons from sysscope_assets
- GtkSourceView highlighting where available
- JSON extension runners
- Full-screen IDE mode

## Limitations

GTK4 and Ruby dependencies must be installed on each system.
Not every listed language has a complete syntax grammar.
The terminal is a command runner rather than a PTY emulator.
Platform compatibility is not automatically verified by this release script.
