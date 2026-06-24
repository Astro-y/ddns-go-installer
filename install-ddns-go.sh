#!/usr/bin/env bash
set -Eeuo pipefail

REPO="jeessy2/ddns-go"
DEFAULT_PORT="9876"
DEFAULT_INTERVAL="300"
COMMAND=""
VERSION=""
PORT="$DEFAULT_PORT"
LISTEN_IP=""
LISTEN_ADDR=""
INTERVAL="$DEFAULT_INTERVAL"
CONFIG_PATH=""
INSTALL_DIR="/opt/ddns-go"
ASSET_NAME=""
COMMAND_PROVIDED=0
TMP_WORK_DIR=""

SUPPORTED_TARGETS=(
  "android_arm64"
  "darwin_arm64"
  "darwin_x86_64"
  "freebsd_arm64"
  "freebsd_armv5"
  "freebsd_armv6"
  "freebsd_armv7"
  "freebsd_i386"
  "freebsd_x86_64"
  "linux_arm64"
  "linux_armv5"
  "linux_armv6"
  "linux_armv7"
  "linux_i386"
  "linux_mips64le_hardfloat"
  "linux_mips64le_softfloat"
  "linux_mips64_hardfloat"
  "linux_mips64_softfloat"
  "linux_mipsle_hardfloat"
  "linux_mipsle_softfloat"
  "linux_mips_hardfloat"
  "linux_mips_softfloat"
  "linux_riscv64"
  "linux_x86_64"
  "windows_arm64"
  "windows_i386"
  "windows_x86_64"
)

usage() {
  cat <<'USAGE'
ddns-go one-click installer

Usage:
  ./install-ddns-go.sh [install|update|uninstall|status|list] [options]

Options:
  --version <vX.Y.Z>       Install a specific release. Defaults to GitHub latest.
  --port <port>            Web listen port. Default: 9876.
  --ip <ip>                Web listen IP, for example 127.0.0.1 or 0.0.0.0.
  --listen <ip:port>       Full listen address. Overrides --ip and --port.
  --interval <seconds>     Sync interval. Default: 300.
  --config <path>          Config file path. Default: <install-dir>/.ddns_go_config.yaml.
  --asset <asset-name>     Use an exact release asset, for example ddns-go_6.17.1_linux_x86_64.tar.gz.
  --install-dir <path>     Install directory. Default: /opt/ddns-go.
  -h, --help               Show this help.

During install/update, the script detects this device and asks you to confirm.
Answer m at the confirmation prompt to manually choose a supported official asset.
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

cleanup() {
  if [ -n "${TMP_WORK_DIR:-}" ] && [ -d "$TMP_WORK_DIR" ]; then
    rm -rf "$TMP_WORK_DIR"
  fi
}

trap cleanup EXIT

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

is_root() {
  [ "$(id -u)" -eq 0 ]
}

version_without_v() {
  printf '%s' "${1#v}"
}

get_listen_addr() {
  if [ -n "$LISTEN_ADDR" ]; then
    printf '%s' "$LISTEN_ADDR"
  elif [ -n "$LISTEN_IP" ]; then
    printf '%s:%s' "$LISTEN_IP" "$PORT"
  else
    printf ':%s' "$PORT"
  fi
}

get_public_ip() {
  local ip service
  command -v curl >/dev/null 2>&1 || return 1
  for service in \
    "https://api.ipify.org" \
    "https://ifconfig.me/ip" \
    "https://ipinfo.io/ip"; do
    ip="$(curl -fsSL --max-time 5 -H 'User-Agent: ddns-go-installer' "$service" 2>/dev/null | tr -d '[:space:]' || true)"
    case "$ip" in
      [0-9]*.[0-9]*.[0-9]*.[0-9]*)
        printf '%s' "$ip"
        return 0
        ;;
    esac
  done
  return 1
}

get_web_url() {
  local listen host port public_ip
  listen="$(get_listen_addr)"
  case "$listen" in
    :*) host="<server-ip>" ;;
    0.0.0.0:*|\[::\]:*) host="<server-ip>" ;;
    *:*) host="${listen%:*}" ;;
    *) host="<server-ip>" ;;
  esac
  host="${host#[}"
  host="${host%]}"
  case "$listen" in
    *:*) port="${listen##*:}" ;;
    *) port="$PORT" ;;
  esac
  port="${port%]}"

  case "$host" in
    "<server-ip>"|"0.0.0.0"|"::")
      public_ip="$(get_public_ip || true)"
      [ -n "$public_ip" ] && host="$public_ip"
      ;;
  esac

  printf 'http://%s:%s' "$host" "$port"
}

choose_from_menu() {
  local title="$1"
  shift
  local options=("$@")
  local count="${#options[@]}"
  local selected=0
  local rendered=0
  local key i

  [ "$count" -gt 0 ] || return 1
  if [ ! -t 0 ]; then
    printf '%s' "${options[0]}"
    return
  fi

  while true; do
    if [ "$rendered" -eq 1 ]; then
      printf '\033[%sA' "$((count + 1))" >&2
    fi
    printf '%s\n' "$title" >&2
    for ((i = 0; i < count; i++)); do
      if [ "$i" -eq "$selected" ]; then
        printf '  \033[7m> %s\033[0m\n' "${options[$i]}" >&2
      else
        printf '    %s\n' "${options[$i]}" >&2
      fi
    done
    rendered=1

    IFS= read -rsn1 key || return 1
    if [ "$key" = $'\x1b' ]; then
      IFS= read -rsn2 -t 0.1 key || true
      case "$key" in
        '[A') selected=$(( (selected - 1 + count) % count )) ;;
        '[B') selected=$(( (selected + 1) % count )) ;;
      esac
    elif [ -z "$key" ]; then
      printf '\n' >&2
      printf '%s' "${options[$selected]}"
      return
    fi
  done
}

asset_for_target() {
  local version_no_v="$1"
  local target="$2"
  local ext="tar.gz"
  case "$target" in
    windows_*) ext="zip" ;;
  esac
  printf 'ddns-go_%s_%s.%s' "$version_no_v" "$target" "$ext"
}

target_from_asset() {
  local asset="$1"
  local version_no_v="$2"
  local target="${asset#ddns-go_${version_no_v}_}"
  target="${target%.tar.gz}"
  target="${target%.zip}"
  printf '%s' "$target"
}

is_supported_target() {
  local candidate="$1"
  local target
  for target in "${SUPPORTED_TARGETS[@]}"; do
    [ "$target" = "$candidate" ] && return 0
  done
  return 1
}

list_assets() {
  local version_no_v="${1:-6.17.1}"
  local target
  echo "Official ddns-go release assets covered by this script:"
  echo "  checksums.txt"
  for target in "${SUPPORTED_TARGETS[@]}"; do
    echo "  $(asset_for_target "$version_no_v" "$target")"
  done
}

latest_version() {
  need_command curl
  local effective_url tag body
  effective_url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' -H 'User-Agent: ddns-go-installer' "https://github.com/${REPO}/releases/latest" || true)"
  tag="${effective_url##*/}"
  case "$tag" in
    v[0-9]*.[0-9]*.[0-9]*)
      echo "$tag"
      return
      ;;
  esac

  body="$(curl -fsSL -H 'Accept: application/vnd.github+json' -H 'User-Agent: ddns-go-installer' "https://api.github.com/repos/${REPO}/releases/latest")" || return 1
  printf '%s
' "$body" | tr ',' '\n' | awk -F '"' '$2 == "tag_name" { print $4; exit }'
}

fetch_recent_versions() {
  need_command curl
  local body
  body="$(curl -fsSL -H 'Accept: application/vnd.github+json' -H 'User-Agent: ddns-go-installer' "https://api.github.com/repos/${REPO}/releases?per_page=5")" || return 1
  printf '%s
' "$body" | tr ',' '\n' | awk -F '"' '$2 == "tag_name" { print $4 }' | head -n 5
}

validate_version() {
  case "$1" in
    v[0-9]*.[0-9]*.[0-9]*|[0-9]*.[0-9]*.[0-9]*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_version() {
  local latest answer selected line found_latest
  local versions=()
  local options=()

  if [ -n "$VERSION" ]; then
    validate_version "$VERSION" || die "Invalid version: ${VERSION}. Expected format: v6.17.1"
    return
  fi

  latest="$(latest_version)" || die "Unable to query latest version. Retry with --version vX.Y.Z."
  validate_version "$latest" || die "GitHub latest returned an invalid version: ${latest}"

  if [ ! -t 0 ]; then
    VERSION="$latest"
    return
  fi

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    versions+=("$line")
  done < <(fetch_recent_versions || true)

  found_latest=0
  for line in "${versions[@]}"; do
    [ "$line" = "$latest" ] && found_latest=1
  done
  if [ "$found_latest" -eq 0 ]; then
    versions=("$latest" "${versions[@]}")
  fi

  options=()
  for line in "${versions[@]}"; do
    [ "${#options[@]}" -lt 5 ] || break
    options+=("$line")
  done
  options+=("Manual input version")

  selected="$(choose_from_menu "Select ddns-go version (Up/Down, Enter)" "${options[@]}")"
  if [ "$selected" = "Manual input version" ]; then
    printf 'Input version, for example v6.17.1: ' >&2
    read -r answer
    VERSION="$answer"
  else
    VERSION="$selected"
  fi

  validate_version "$VERSION" || die "Invalid version: ${VERSION}. Expected format: v6.17.1"
}
detect_os() {
  local kernel
  kernel="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  if [ -n "${ANDROID_ROOT:-}" ] || [ -d /system/app ] || [ "$kernel" = "android" ]; then
    echo "android"
    return
  fi
  case "$kernel" in
    linux) echo "linux" ;;
    darwin) echo "darwin" ;;
    freebsd) echo "freebsd" ;;
    *) echo "$kernel" ;;
  esac
}

normalize_arch() {
  local raw
  raw="$(uname -m 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    x86_64|amd64) echo "x86_64" ;;
    i386|i486|i586|i686|x86) echo "i386" ;;
    aarch64|arm64) echo "arm64" ;;
    armv5*|arm5*) echo "armv5" ;;
    armv6*|arm6*) echo "armv6" ;;
    armv7*|arm7*) echo "armv7" ;;
    riscv64) echo "riscv64" ;;
    mips64el|mips64le) echo "mips64le" ;;
    mips64) echo "mips64" ;;
    mipsel|mipsle) echo "mipsle" ;;
    mips) echo "mips" ;;
    *) echo "$raw" ;;
  esac
}

choose_mips_float() {
  local prompt="${1:-MIPS float ABI}"
  choose_from_menu "$prompt (Up/Down, Enter)" softfloat hardfloat
}

detect_target() {
  local os arch float target
  os="$(detect_os)"
  arch="$(normalize_arch)"

  case "$os" in
    android)
      [ "$arch" = "arm64" ] || return 1
      target="android_arm64"
      ;;
    darwin|freebsd|linux)
      case "$arch" in
        mips|mipsle|mips64|mips64le)
          float="$(choose_mips_float "Detected ${os}_${arch}; choose float ABI")"
          target="${os}_${arch}_${float}"
          ;;
        *)
          target="${os}_${arch}"
          ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac

  is_supported_target "$target" || return 1
  echo "$target"
}

manual_select_target() {
  local os_choice arch_choice float_choice target
  os_choice="$(choose_from_menu "Select OS (Up/Down, Enter)" android darwin freebsd linux windows)"

  case "$os_choice" in
    android)
      target="android_arm64"
      ;;
    darwin)
      arch_choice="$(choose_from_menu "Select macOS architecture (Up/Down, Enter)" arm64 x86_64)"
      target="darwin_${arch_choice}"
      ;;
    freebsd)
      arch_choice="$(choose_from_menu "Select FreeBSD architecture (Up/Down, Enter)" arm64 armv5 armv6 armv7 i386 x86_64)"
      target="freebsd_${arch_choice}"
      ;;
    linux)
      arch_choice="$(choose_from_menu "Select Linux architecture (Up/Down, Enter)" arm64 armv5 armv6 armv7 i386 mips mipsle mips64 mips64le riscv64 x86_64)"
      case "$arch_choice" in
        mips|mipsle|mips64|mips64le)
          float_choice="$(choose_mips_float "Choose Linux ${arch_choice} float ABI")"
          target="linux_${arch_choice}_${float_choice}"
          ;;
        *)
          target="linux_${arch_choice}"
          ;;
      esac
      ;;
    windows)
      arch_choice="$(choose_from_menu "Select Windows architecture (Up/Down, Enter)" arm64 i386 x86_64)"
      target="windows_${arch_choice}"
      ;;
  esac

  echo "$target"
}

confirm_or_select_target() {
  local detected_target="$1"
  local version_no_v="$2"
  local target="$detected_target"
  local answer

  while true; do
    local asset url
    asset="$(asset_for_target "$version_no_v" "$target")"
    url="https://github.com/${REPO}/releases/download/v${version_no_v}/${asset}"

    echo >&2
    echo "Detected system:" >&2
    echo "  OS:            $(detect_os)" >&2
    echo "  Architecture:  $(normalize_arch)" >&2
    echo "  Target:        $target" >&2
    echo "  Asset:         $asset" >&2
    echo "  Download URL:  $url" >&2
    echo "  Install dir:   $INSTALL_DIR" >&2
    echo "  Config path:   $CONFIG_PATH" >&2
    echo "  Listen:        $(get_listen_addr)" >&2
    echo >&2
    printf 'Use this detected result and continue? [Y/n/m]: ' >&2
    read -r answer
    answer="${answer:-Y}"
    case "$answer" in
      Y|y|yes|YES)
        echo "$target"
        return
        ;;
      N|n|no|NO)
        echo "Canceled." >&2
        exit 0
        ;;
      M|m)
        target="$(manual_select_target)"
        ;;
      *)
        echo "Please answer Y, n, or m." >&2
        ;;
    esac
  done
}

download_release_asset() {
  local version_no_v="$1"
  local asset="$2"
  local work_dir="$3"
  local base_url="https://github.com/${REPO}/releases/download/v${version_no_v}"

  need_command curl
  echo "Downloading ${asset}..."
  curl -fL --retry 3 -o "${work_dir}/${asset}" "${base_url}/${asset}"
  echo "Downloading checksums.txt..."
  curl -fL --retry 3 -o "${work_dir}/checksums.txt" "${base_url}/checksums.txt"
}

verify_checksum() {
  local asset="$1"
  local work_dir="$2"
  local expected actual asset_path

  expected="$(awk -v asset="$asset" '$2 == asset { print $1; exit }' "${work_dir}/checksums.txt")"
  [ -n "$expected" ] || die "No checksum entry found for ${asset}."
  asset_path="${work_dir}/${asset}"

  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$asset_path" | awk '{ print $1 }')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$asset_path" | awk '{ print $1 }')"
  elif command -v sha256 >/dev/null 2>&1; then
    actual="$(sha256 -q "$asset_path")"
  else
    die "Missing checksum command: sha256sum, shasum, or sha256."
  fi

  [ "$expected" = "$actual" ] || die "Checksum mismatch for ${asset}. Expected ${expected}, got ${actual}."
  echo "Checksum OK: ${asset}"
}

extract_asset() {
  local asset="$1"
  local work_dir="$2"
  local output_dir="$3"

  mkdir -p "$output_dir"
  case "$asset" in
    *.tar.gz)
      need_command tar
      tar -xzf "${work_dir}/${asset}" -C "$output_dir"
      ;;
    *.zip)
      need_command unzip
      unzip -o "${work_dir}/${asset}" -d "$output_dir"
      ;;
    *)
      die "Unsupported archive format: $asset"
      ;;
  esac
}

binary_path_for_target() {
  local target="$1"
  case "$target" in
    windows_*) echo "${INSTALL_DIR}/ddns-go.exe" ;;
    *) echo "${INSTALL_DIR}/ddns-go" ;;
  esac
}

run_install_service() {
  local target="$1"
  local binary
  binary="$(binary_path_for_target "$target")"
  chmod +x "$binary" 2>/dev/null || true

  case "$target" in
    android_*)
      echo "Android target selected. Service installation is skipped."
      echo "Run manually: ${binary} -l $(get_listen_addr) -f ${INTERVAL} -c ${CONFIG_PATH}"
      ;;
    windows_*)
      echo "Windows asset selected from a Unix shell. Service installation is skipped."
      echo "Use install-ddns-go.ps1 on Windows to install the service."
      ;;
    *)
      "$binary" -s install -l "$(get_listen_addr)" -f "$INTERVAL" -c "$CONFIG_PATH"
      ;;
  esac
}

resolve_command() {
  if [ -n "$COMMAND" ]; then
    return
  fi
  if [ -t 0 ]; then
    COMMAND="$(choose_from_menu "Select operation mode (Up/Down, Enter)" install update uninstall status list)"
  else
    COMMAND="install"
  fi
}

resolve_listen_settings() {
  local mode answer
  if [ -n "$LISTEN_ADDR" ] || [ -n "$LISTEN_IP" ]; then
    return
  fi
  [ -t 0 ] || return

  mode="$(choose_from_menu "Select Web listen mode (Up/Down, Enter)" "Public IPv4 (0.0.0.0:${PORT})" "Localhost only (127.0.0.1:${PORT})" "Custom public port" "Custom local port" "Custom full listen address")"
  case "$mode" in
    "Public IPv4"*)
      LISTEN_IP="0.0.0.0"
      ;;
    "Localhost only"*)
      LISTEN_IP="127.0.0.1"
      ;;
    "Custom public port")
      printf 'Input public Web port, for example 9876: ' >&2
      read -r answer
      case "$answer" in
        ''|*[!0-9]*) die "Port must be a number." ;;
      esac
      [ "$answer" -ge 1 ] && [ "$answer" -le 65535 ] || die "Port must be between 1 and 65535."
      PORT="$answer"
      LISTEN_IP="0.0.0.0"
      ;;
    "Custom local port")
      printf 'Input local Web port, for example 9876: ' >&2
      read -r answer
      case "$answer" in
        ''|*[!0-9]*) die "Port must be a number." ;;
      esac
      [ "$answer" -ge 1 ] && [ "$answer" -le 65535 ] || die "Port must be between 1 and 65535."
      PORT="$answer"
      LISTEN_IP="127.0.0.1"
      ;;
    "Custom full listen address")
      printf 'Input listen address, for example 0.0.0.0:9876 or [::]:9876: ' >&2
      read -r answer
      [ -n "$answer" ] || die "Listen address cannot be empty."
      LISTEN_ADDR="$answer"
      ;;
  esac
}

install_or_update() {
  local action="$1"
  local version_no_v target asset

  is_root || die "Please run as root, for example: sudo ./install-ddns-go.sh ${action}"

  resolve_version
  resolve_listen_settings
  version_no_v="$(version_without_v "$VERSION")"
  [ -n "$CONFIG_PATH" ] || CONFIG_PATH="${INSTALL_DIR}/.ddns_go_config.yaml"

  if [ -n "$ASSET_NAME" ]; then
    target="$(target_from_asset "$ASSET_NAME" "$version_no_v")"
    is_supported_target "$target" || die "Unsupported asset target: $target"
    asset="$ASSET_NAME"
  else
    target="$(detect_target)" || {
      echo "Could not detect a supported official target. Please choose manually." >&2
      target="$(manual_select_target)"
    }
    target="$(confirm_or_select_target "$target" "$version_no_v")"
    asset="$(asset_for_target "$version_no_v" "$target")"
  fi

  TMP_WORK_DIR="$(mktemp -d)"

  if [ "$action" = "update" ] && command -v systemctl >/dev/null 2>&1; then
    systemctl stop ddns-go >/dev/null 2>&1 || true
  fi

  download_release_asset "$version_no_v" "$asset" "$TMP_WORK_DIR"
  verify_checksum "$asset" "$TMP_WORK_DIR"
  extract_asset "$asset" "$TMP_WORK_DIR" "$INSTALL_DIR"
  run_install_service "$target"

  echo
  echo "ddns-go ${action} finished."
  echo "Open: $(get_web_url)"
  echo "Config: ${CONFIG_PATH}"
}

uninstall_service() {
  local binary answer
  binary="${INSTALL_DIR}/ddns-go"
  is_root || die "Please run as root."
  if [ -x "$binary" ]; then
    "$binary" -s uninstall || true
  elif command -v systemctl >/dev/null 2>&1; then
    systemctl stop ddns-go >/dev/null 2>&1 || true
    systemctl disable ddns-go >/dev/null 2>&1 || true
  fi

  printf 'Remove install directory and config at %s? [y/N]: ' "$INSTALL_DIR"
  read -r answer
  case "$answer" in
    Y|y|yes|YES)
      rm -rf "$INSTALL_DIR"
      echo "Removed ${INSTALL_DIR}."
      ;;
    *)
      echo "Kept ${INSTALL_DIR}."
      ;;
  esac
}

show_status() {
  echo "Install dir: ${INSTALL_DIR}"
  if [ -n "$CONFIG_PATH" ]; then
    echo "Config path: ${CONFIG_PATH}"
  else
    echo "Config path: ${INSTALL_DIR}/.ddns_go_config.yaml"
  fi
  if [ -x "${INSTALL_DIR}/ddns-go" ]; then
    "${INSTALL_DIR}/ddns-go" -v 2>/dev/null || true
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl status ddns-go --no-pager || true
  fi
  echo "Web: $(get_web_url)"
}

parse_args() {
  if [ $# -gt 0 ]; then
    case "$1" in
      install|update|uninstall|status|list)
        COMMAND="$1"
        COMMAND_PROVIDED=1
        shift
        ;;
    esac
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      --version)
        VERSION="${2:-}"
        shift 2
        ;;
      --port)
        PORT="${2:-}"
        shift 2
        ;;
      --ip)
        LISTEN_IP="${2:-}"
        shift 2
        ;;
      --listen)
        LISTEN_ADDR="${2:-}"
        shift 2
        ;;
      --interval)
        INTERVAL="${2:-}"
        shift 2
        ;;
      --config)
        CONFIG_PATH="${2:-}"
        shift 2
        ;;
      --asset)
        ASSET_NAME="${2:-}"
        shift 2
        ;;
      --install-dir)
        INSTALL_DIR="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  resolve_command
  case "$COMMAND" in
    install|update) install_or_update "$COMMAND" ;;
    uninstall) uninstall_service ;;
    status) show_status ;;
    list) list_assets "$(version_without_v "${VERSION:-v6.17.1}")" ;;
    *) die "Unknown command: $COMMAND" ;;
  esac
}

main "$@"
