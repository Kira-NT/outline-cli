#!/bin/sh
#
# Install the Outline Client CLI.

#################################################
# The URL of the repo that contains this file.
#################################################
REPO="https://github.com/Kira-NT/outline-cli"

#################################################
# The default name for the __vpn_manager symlink.
#################################################
DEFAULT_VPN_MANAGER_NAME="vpn"

#################################################
# Indicates whether the user should be prompted
# for input or if default response values should
# be used instead.
#################################################
USE_DEFAULT_RESPONSE=false

#################################################
# Formats and prints the provided error message.
# Arguments:
#   $1. The error message to format and print.
# Outputs:
#   Writes the formatted error message to stderr.
# Returns:
#   Always returns 1.
#################################################
error() {
  echo "${0}: ${1}" >& 2
  return 1
}

#################################################
# Checks if the specified command exists.
# Arguments:
#   $1. The command to check.
# Returns:
#   0 if the specified command exists;
#   otherwise, a non-zero status.
#################################################
command_exists() {
  command -v "${1}" > /dev/null 2>& 1
}

#################################################
# Asks the user for confirmation.
# Arguments:
#   $1. The message to display.
#   $2. The default response.
# Inputs:
#   Reads user's input from stdin.
# Outputs:
#   Writes the message to stderr and prompts
#   the user for yes/no confirmation.
# Returns:
#   0 if the user confirmed the action.
#   1 if the user denied the action.
#################################################
confirm() {
  local confirm_response="${2}"
  if [ -z "${confirm_response}" ] || [ "${USE_DEFAULT_RESPONSE}" != "true" ]; then
    echo -n "${1} [Y/n]: " >& 2
    read -r confirm_response
  fi

  case "$(echo "${confirm_response}" | tr '[:upper:]' '[:lower:]')" in
    y|yes|yep) return 0 ;;
    n|no|nope) return 1 ;;
    *) confirm "${1}" ;;
  esac
}

#################################################
# Prompts the user for input.
# Arguments:
#   $1. The message to display.
#   $2. The default response.
# Inputs:
#   Reads user's input from stdin.
# Outputs:
#   Writes the message to stderr.
#   Writes the user's input to stdout.
# Returns:
#   0 if the response is not empty; otherwise, 1.
#################################################
prompt() {
  local prompt_response="${2}"
  if [ -z "${prompt_response}" ] || [ "${USE_DEFAULT_RESPONSE}" != "true" ]; then
    echo -n "${1}: " >& 2
    read -r prompt_response
  fi

  echo "${prompt_response}"
  [ -n "${prompt_response}" ]
}

#################################################
# Installs the specified package(s) using the
# appropriate package manager for the system.
# Arguments:
#   ... One or more package names to install.
# Returns:
#   0 if the operation succeeds;
#   otherwise, a non-zero status if no supported
#   package manager is found or the installation
#   fails.
#################################################
install_package() {
  if command_exists apt-get; then
    apt-get install -y "${@}"
  elif command_exists dnf; then
    dnf install -y "${@}"
  elif command_exists pacman; then
    pacman -S --noconfirm "${@}"
  else
    return 1
  fi
}

#################################################
# Gets the operating system name.
# Arguments:
#   None
# Outputs:
#   Writes the name of the OS to stdout.
#################################################
os_name() {
  uname -s | tr '[:upper:]' '[:lower:]'
}

#################################################
# Determines the operating system type combining
# OS name and architecture.
# Arguments:
#   None
# Outputs:
#   Writes the type of the OS to stdout,
#   formatted as <>-<>, e.g., "linux-amd64",
#   "darwin-arm64", etc.
#################################################
os_type() {
  case "$(uname -m)" in
    x86_64) echo "$(os_name)-amd64" ;;
    aarch64|armv8) echo "$(os_name)-arm64" ;;
    armv6|armv7l) echo "$(os_name)-armv6l" ;;
    i686|.*386.*) echo "$(os_name)-386" ;;
    *) echo "$(os_name)-$(uname -m)" ;;
  esac
}

#################################################
# Downloads a file.
# Arguments:
#   $1. The URL of the file to download.
#   $2. The destination of the downloaded file.
#       If not provided, the file will be written
#       to stdout.
# Returns:
#   0 if the operation succeeds;
#   otherwise, a non-zero status.
#################################################
download() {
  if command_exists wget; then
    wget -O "${2:-"-"}" "${1}"
  elif command_exists curl; then
    curl -Lo "${2:-"-"}" "${1}"
  fi
}

#################################################
# Gets the latest version of Go.
# Arguments:
#   None
# Outputs:
#   Writes the version number of the latest
#   Go version (e.g., '1.20.0') to stdout.
# Returns:
#   0 if the operation succeeds;
#   otherwise, a non-zero status.
#################################################
go_version_latest() {
  download "https://go.dev/dl/?mode=json" | jq -r '.[0].version' | grep -o '[0-9\.]*' 2> /dev/null
}

#################################################
# Downloads the specified version of Go.
# Arguments:
#   $1. The destination of the downloaded file.
#       If not provided, defaults to "go.tar.gz".
#   $2. The version of Go to download.
#       If not provided, downloads the latest
#       version.
# Returns:
#   0 if the operation succeeds;
#   otherwise, a non-zero status.
#################################################
go_download() {
  download "https://go.dev/dl/go${2:-"$(go_version_latest)"}.$(os_type).tar.gz" "${1:-"go.tar.gz"}" >& 2
}

#################################################
# Installs the specified version of Go.
# Arguments:
#   $1. The Go installation directory.
#       If not provided, defaults to ".go".
#   $2. The version of Go to install.
#       If not provided, installs the latest
#       version.
# Outputs:
#   Writes the full path of the Go binary
#   to stdout.
# Returns:
#   0 if the operation succeeds;
#   otherwise, a non-zero status.
#################################################
go_install() {
  local go_cwd="${PWD}"
  local go_path="${1:-".go"}"
  local go_tmp="go@${2:-"latest"}.tmp${$}.tar.gz"

  if [ -d "${go_path}" ] && [ -n "$(ls -A "${go_path}")" ]; then
    error "failed to install Go: Already installed"
    return 1
  fi

  if ! go_download "${go_tmp}" "${2}"; then
    error "failed to install Go: Could not download the binary"
    return 1
  fi

  mkdir -p "${go_path}"
  tar xf "${go_tmp}" --directory="${go_path}" --strip=1
  if [ $? -ne 0 ] || [ ! -x "${go_path}/bin/go" ]; then
    error "failed to install Go: Could not extract the binary"
    rm "${go_tmp}"
    rm -rf "${go_path}"
    return 1
  fi

  rm "${go_tmp}"

  cd "${go_path}"
  echo "${PWD}/bin/go"
  cd "${go_cwd}"
}

#################################################
# Clones the 'outline-sdk' repo, applies patches
# to it (if provided), builds the 'outline-cli'
# Go binary, then cleans up the cloned repo.
# Arguments:
#   $1. The output file name for the binary.
#       Defaults to "outline".
#   $2. The location of the Go binary to use.
#       Defaults to "go".
#   ... The patches to be applied to the repo.
# Returns:
#   0 if the operation succeeds;
#   otherwise, a non-zero status.
#################################################
outline_install() {
  local go_build_output="${1:-"outline"}"
  local go_binary="${2:-"go"}"
  shift 2

  git clone "https://github.com/Jigsaw-Code/outline-sdk" && \
  cd "./outline-sdk/x/examples/"
  if [ $? -ne 0 ]; then
    error "failed to build outline-cli: 'Jigsaw-Code/outline-sdk' is unreachable"
    return 1
  fi

  while [ -n "${1}" ]; do
    echo "Applying a patch: '${1}'..." >& 2
    git apply "../../../${1}"
    shift
  done

  local go_cache="${PWD}/.cache/go"
  local go_build_status=0
  echo "Building 'outline-cli' as '${go_build_output}'..." >& 2
  GOPATH="${go_cache}" GOCACHE="${go_cache}" "${go_binary}" build -o "outline-cli" "./outline-cli" >& 2
  go_build_status=$?
  cd "../../../"

  if [ "${go_build_status}" -eq 0 ]; then
    cp "./outline-sdk/x/examples/outline-cli/outline-cli" "${go_build_output}"
    go_build_status=$?
  fi

  rm -rf "./outline-sdk"

  if [ $? -ne 0 ]; then
    error "failed to build outline-cli: Compilation failed"
  fi
  return "${go_build_status}"
}

#################################################
# Modifies a given template file to replace
# the placeholder connect function with an actual
# command used to establish a VPN connection.
# The placeholder is denoted by a line containing
# "# CONNECT_TEMPLATE".
# Arguments:
#   $1. The path to the template file.
#   $2. The actual command used to establish
#       a connection, for example,
#       `__outline -transport "${1}"`.
# Returns:
#   0 if the operation succeeds;
#   otherwise, a non-zero status.
#################################################
outline_wrapper_install() {
  local template_line_number="$(sed -n '/# CONNECT_TEMPLATE/=' "${1}" 2> /dev/null)"

  [ -n "${template_line_number}" ] && \
  sed -i"" "${template_line_number} c\  ${2:-"__outline -transport \"\${1}\""} &" "${1}"
}

#################################################
# Copies the source file to the target location
# and sets the permissions on the copied file.
# Arguments:
#   $1. The source file path.
#   $2. The target file path.
#   $3. The permissions to apply on
#       the copied file (in octal notation).
# Returns:
#   0 if the cp and chmod operations succeed;
#   otherwise, a non-zero status.
#################################################
cpmod() {
  mkdir -m=${3} -p "$(dirname "${2}")"
  cp "${1}" "${2}" && chmod "${3}" "${2}"
}

#################################################
# Copies a file from the project's source
# directory to the corresponding location
# in the target system.
# The function retrieves the destination from
# the file's path by removing the initial
# directory part.
# Arguments:
#   $1. The source file path.
#   $2. The permissions to apply on
#       the copied file (in octal notation).
#       If not provided, defaults to 600.
# Returns:
#   0 if the operation succeeds;
#   otherwise, a non-zero status.
#################################################
unwrap() {
  cpmod "${1}" "$(echo "${1}" | sed 's/^[^/]*//')" "${2:-600}"
}

#################################################
# Asserts that the current user is "root" (i.e.,
# a superuser). Otherwise, terminates the current
# process.
# Arguments:
#   None
# Outputs:
#   Writes the error message, if any, to stderr.
# Returns:
#   0 if the current user is a superuser;
#   otherwise, never returns (exits the shell
#   with a status of 1).
#################################################
assert_is_root() {
  [ "${EUID:-"$(id -u)"}" -eq 0 ] && return

  error "cannot perform the installation: Permission denied"
  exit 1
}

#################################################
# Asserts that the current working directory
# contains the script being executed.
# Arguments:
#   None
# Outputs:
#   Writes the error message, if any, to stderr.
# Returns:
#   0 if the current working directory is valid;
#   otherwise, never returns (exits the shell
#   with a status of 1).
#################################################
assert_valid_cwd() {
  [ -f "./${0##*/}" ] && return

  error "cannot perform the installation: Invalid working directory"
  exit 1
}

#################################################
# Asserts that the provided command or one of its
# substitutions is available on the current
# system.
# Arguments:
#   $1. The command name to check.
#   ... The alternatives to check.
# Outputs:
#   Writes the error message, if any, to stderr.
# Returns:
#   0 if the provided command is available;
#   otherwise, never returns (exits the shell
#   with a status of 1).
#################################################
assert_installed() {
  local cmd_name=""
  for cmd_name in "${@}"; do
    command_exists "${cmd_name}" && return
  done

  if confirm "Do you want to install the missing dependency '${1}'?" "y"; then
    install_package "${1}" && return
  fi

  error "cannot perform the installation: ${1} is not installed"
  exit 1
}

#################################################
# Prints a brief help message.
# Arguments:
#   None
# Outputs:
#   Writes the help message to stdout.
#################################################
help() {
  echo "Usage: ${0} [<options>]"
  echo
  echo "Install the Outline Client CLI."
  echo
  echo "Examples:"
  echo "  sudo ${0} --yes"
  echo "  sudo ${0} --undo"
  echo
  echo "Options:"
  echo "  -h, --help  Display this help text and exit"
  echo "  -y, --yes   Run the script without manual intervention"
  echo "  -u, --undo  Undo the changes made by this script"
}

#################################################
# Formats and prints the provided error message,
# displays the help page, and terminates the
# process.
# Arguments:
#   $1. The error message to format and print.
# Outputs:
#   Writes the formatted error message to stderr.
# Returns:
#   Never returns (exits with a status of 1).
#################################################
fatal_error() {
  error "${1}"
  help >& 2
  exit 1
}

#################################################
# Uninstalls outline-cli by removing all
# the files and directories it may have created,
# and undoing the network routing rule changes.
# Arguments:
#   $1=false. Indicates whether to also remove
#             local user data.
#################################################
uninstall() {
  assert_is_root

  # Previously, executables were located in `sbin` instead of `bin`.
  rm -f "/usr/local/sbin/__vpn_connect"
  rm -f "/usr/local/sbin/__vpn_manager"
  find "/usr/local/sbin/" -lname "/usr/local/sbin/__vpn_manager" -delete

  rm -f "/usr/local/bin/__vpn_connect"
  rm -f "/usr/local/bin/__vpn_manager"
  find "/usr/local/bin/" -lname "/usr/local/bin/__vpn_manager" -delete

  rm -f "/usr/share/polkit-1/actions/vpn-manager.policy"
  rm -f "/etc/NetworkManager/dispatcher.d/vpn-manager-refresh"

  if [ "${1}" = "true" ]; then
    rm -rf "/var/lib/outline"
    rm -f "/var/log/outline"
  fi
}

#################################################
# Cleans up the working directory by removing
# temporary files and directories that might have
# been created during the runtime of
# the installation script.
# Arguments:
#   None
#################################################
cleanup() {
  git checkout -- "src/usr/local/bin/__vpn_connect"
  rm -rf .go
}

#################################################
# Installs the current version of Outline CLI.
# Arguments:
#   None
# Returns:
#   0 if the operation succeeds;
#   otherwise, a non-zero status.
#################################################
install_local() {
  # Ensure that prerequisites for the script are met.
  assert_is_root
  assert_valid_cwd
  assert_installed jq
  assert_installed git
  assert_installed tar
  assert_installed curl wget
  assert_installed gcc clang # Go needs a C/C++ compiler.

  # Clean up stuff from the previous installations.
  uninstall > /dev/null 2>& 1

  # Automatic cleanup on the process termination.
  trap cleanup EXIT

  # Prepare __vpn_connect.
  # It should either be replaced with outline-cli, or
  # modified to contain the actual logic necessary
  # for connecting to a VPN server.
  if confirm "Install 'outline-cli' by Jigsaw LLC?" "y"; then
    local outline_go_binary="go"
    local outline_go_version="$(prompt "Select a Go version to compile 'outline-cli' with [latest/local/1.22.0/...]" "latest")"
    if [ "${outline_go_version}" = "latest" ]; then
      outline_go_version=""
    fi
    if [ "${outline_go_version}" != "local" ]; then
      outline_go_binary="$(go_install ".go" "${outline_go_version}")"
      [ -n "${outline_go_binary}" ] || return
    fi

    if confirm "Apply patches from the 'patches/' directory?" "y"; then
      outline_install "src/usr/local/bin/__vpn_connect" "${outline_go_binary}" patches/* || return
    else
      outline_install "src/usr/local/bin/__vpn_connect" "${outline_go_binary}" || return
    fi
  else
    local outline_wrapper_cmd="$(prompt "Enter a command used to connect to a VPN server")"
    if [ -z "${outline_wrapper_cmd}" ]; then
      error "failed to create a wrapper: Invalid command"
      return
    fi

    outline_wrapper_install "src/usr/local/bin/__vpn_connect" "${outline_wrapper_cmd}" || return
  fi

  # Prompt for a name to symlink the __vpn_manager command.
  local vpn_manager_symlink_name="$(prompt "Enter a short name for the vpn-manager command [${DEFAULT_VPN_MANAGER_NAME}]" "${DEFAULT_VPN_MANAGER_NAME}")"

  # Unwrap the __vpn_connect and __vpn_manager commands, and
  # create a symlink for __vpn_manager with the user-specified name.
  unwrap "src/usr/local/bin/__vpn_connect" 500 && \
  unwrap "src/usr/local/bin/__vpn_manager" 500 && \
  ln -s "/usr/local/bin/__vpn_manager" "/usr/local/bin/${vpn_manager_symlink_name:-"${DEFAULT_VPN_MANAGER_NAME}"}"
  if [ $? -ne 0 ]; then
    uninstall
    return
  fi

  # Allow calls to __vpn_manager via pkexec.
  if command_exists pkexec; then
    unwrap "src/usr/share/polkit-1/actions/vpn-manager.policy" 644
  fi

  # NetworkManager integration.
  if command_exists NetworkManager && confirm "Enable NetworkManager integration?" "y"; then
    unwrap "src/etc/NetworkManager/dispatcher.d/vpn-manager-refresh" 500
  fi
}

#################################################
# Installs the latest version of Outline CLI.
# Arguments:
#   None
# Returns:
#   0 if the operation succeeds;
#   otherwise, a non-zero status.
#################################################
install_remote() {
  # Ensure that prerequisites for the script are met.
  assert_is_root
  assert_installed git

  # Clone the latest available tag and cd into it.
  git clone "${REPO}" --depth 1 --branch \
    "$(git ls-remote --tags --sort="-v:refname" "${REPO}" | head -n 1 | cut -d/ -f3)" && \
    [ -n "${REPO##*/}" ] && \
    [ -f "./${REPO##*/}/install.sh" ] && \
    cd "./${REPO##*/}" || \
    return

  # Rebuild the arguments.
  local inline_args=""
  if [ "${USE_DEFAULT_RESPONSE}" = "true" ]; then
    inline_args="${inline_args} -y"
  fi

  # Perform the installation.
  ./install.sh ${inline_args}

  # Delete the cloned repo.
  rm -rf -- "../${REPO##*/}"
}

#################################################
# The main entry point for the script.
# Arguments:
#   ... A list of the command line arguments.
# Returns:
#   0 if the operation succeeds;
#   otherwise, a non-zero status.
#################################################
main() {
  # Parse the arguments and options.
  while [ -n "${1}" ]; do
    case "${1}" in
      -h|--help) help; exit 0 ;;
      -y|--yes) USE_DEFAULT_RESPONSE=true ;;
      -u|--undo|--uninstall) uninstall true; exit 0 ;;
      -*) fatal_error "invalid option: ${1}" ;;
      *) fatal_error "invalid argument: ${1}" ;;
    esac
    shift 2> /dev/null
  done

  if [ "${0##*/}" = "install.sh" ]; then
    # The script is being executed from a local file,
    # i.e., the repository has already been cloned.
    # Proceed to the main entry point.
    install_local
  else
    # The script has been piped into whatever is executing it now.
    # Proceed to the stub that will clone the repository and
    # run the script properly.
    install_remote <& 1
  fi
}

main "${@}"
