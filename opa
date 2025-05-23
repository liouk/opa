#!/usr/bin/env bash

set -e

extras_file=${OPA_EXTRAS_FILE:-"$HOME/.zsh/conf.d/opa-extras.sh"}
session_file=${OPA_SESSION_FILE:-"$HOME/.config/op/.session-token"}

usage () {
  cat <<EOF
opa extends the functionality of 'op' (the 1Password CLI tool) by using fzf and
persistent sessions.

This tool requires:
  - op: https://1password.com/downloads/command-line/
  - fzf: https://github.com/junegunn/fzf

COMMANDS

  signin [-f|--force]
      Sign-in to 1password and store the session token in the file specified
      in \$OPA_SESSION_FILE. By default, this is '$HOME/.config/op/.session-token'.
      The token is valid for 30 minutes. Forcing signin will clear any existing
      session token and obtain a new one.

  list [-c|--choose]
      List all items available in the signed in account; sign-in if needed. Then, if
      the selected item contains only one secret, copy it to the clipboard and send
      a desktop notification. If there are multiple secrets, or '-c' has been used,
      prompt the user to select which field to copy.

  clear
      Delete the session token file.

  help, usage
      Print this help message.

OPTIONS

  -c, --choose
      Instead of automatically copying the secret to clipboard when there is only one
      in the selected item, prompt the user to choose which field to copy. Useful to
      copy 2FA fields such as OTP.

  -h, --help
    Same as 'help' or 'usage' command.

EXTRA COMMANDS
  This section documents any extra commands defined. See section 'EXTRAS DEFINITION'
  for more info.$(opa_usage_extras 2>/dev/null)

EXTRAS DEFINITION
  This script can be extended to run user defined commands, on top of the ones defined
  here. The commands must be defined as functions in a shell file; the location of the
  file can be set in \$OPA_EXTRAS_FILE (defaults to '$HOME/.zsh/conf.d/opa-extras.sh').

  Each command must be defined in a function called 'opa_extras_<cmd name>'; for example:

    opa_extras_test () {
      echo "You can invoke this command simply by typing 'opa test'."
    }

  The script first looks at its own commands, and then the extras; therefore you can't
  hijack any command names as they will be evaluated first.

  You can document your extras by writing a func called 'opa_usage_extras' which prints
  the docs within the 'EXTRA COMMANDS' section above. Follow the structure of this doc
  for the best results.

DESKTOP NOTIFICATIONS
  To enable desktop notifications, define a function in the extras file
  (\$OPA_EXTRAS_FILE):
  - opa_notify(msg): pass a single string argument to display in a desktop notification

CLIPBOARD
  opa needs clipboard integration to function. To adapt to your system, define two
  functions in the extras file (\$OPA_EXTRAS_FILE):
  - opa_copy(data): pass a single string argument to copy to clipboard
  - opa_paste(): returns a single string retrieved from the clipboard
EOF
}

# sign in to 1password and store the obtained session token
# in the configured session file
op_signin () {
	if [[ "$2" == "--force" || "$2" == "-f" ]]; then
		rm -f "$session_file"
		touch "$session_file"
	elif [ -f "$session_file" ]; then
    OP_SESSION=$(cat $session_file 2>/dev/null)
    op --session "$OP_SESSION" user list > /dev/null 2>&1 && return
  else
    touch "$session_file"
  fi

  OP_SESSION=$(op signin --account my --raw)
  chmod 600 "$session_file"
  echo -n "$OP_SESSION" > "$session_file"
}

# copy the selected data in the clipboard, send a desktop notification,
# and then wait 15s before proceeding
copy_and_wait () {
  data="$1"

  existing="$(opa_paste)"
  opa_copy "$data"

  local msg="secret copied to clipboard"
  [[ $(type -t "opa_notify") == function ]] && { opa_notify "$msg"; }
  echo "$msg"
  echo "will clear after 15s"

  sleep 15
}

# restore the existing contents of the clipboard and
# effectively clear the secret
restore () {
  exitcode=$?
  opa_copy "$existing"

  local msg="secret cleared from clipboard"
  [[ $(type -t "opa_notify") == function ]] && { opa_notify "$msg"; }
  echo "$msg"

  exit $exitcode
}

# list all items from 1password and select one using fzf
# if the selected item contains only one secret, copy it to clipboard
# immediately, unless -c is specified
# if -c is specified or more than one secrets exist, select a field
# using fzf
cmd_list () {
  echo "Choose item:"
  local selected=$(op --session "$OP_SESSION" item list | tail -n +2 | awk -F '    ' '{print $1"    "$2}' | fzf --height=~10)
  [ "$selected" = "" ] && { echo "no selection; bye"; exit; }
  echo -e "$selected\n"
  local selected_id=$(echo -n "$selected" | cut -d' ' -f1)
  all_field_names=()

  secret=$(op --session "$OP_SESSION" item get "$selected_id" --reveal --fields "type=concealed" --format=json | jq -r '.value' 2>/dev/null) || true
  if [[ "$secret" == "" || "$1" == "--choose" || "$1" == "-c" ]]; then
    while IFS= read -r field; do
      [ "$field" = "Fields:" ] && continue
      field_name=$(echo $field | cut -d':' -f1)
      [[ -z "${field_name// }" ]] || all_field_names+=("$field_name")
    done <<< $(op --session "$OP_SESSION" item get "$selected_id" --reveal | sed -n '/^Fields:$/,$p')

    echo "Choose field:"
    selected_field=$(printf "%s\n" "${all_field_names[@]}" | fzf --prompt "Field> " --height=~10)
    [ "$selected_field" = "" ] && { echo "no selection; bye"; exit; }
    echo -e "$selected_field\n"

    secret=$(op --session "$OP_SESSION" item get "$selected_id" --reveal --field "$selected_field")
    if [[ "$secret" == otpauth* ]]; then
      secret=$(op --session "$OP_SESSION" item get "$selected_id" --reveal --otp)
    fi
    secret=${secret#"\""}
    secret=${secret%"\""}
  fi

  copy_and_wait "$secret"
}

main () {
  cmd="$1"

  source $extras_file 2>/dev/null || true
  [[ $(type -t "opa_copy") == function ]] || { echo "error: opa_copy func undefined; see opa --help"; exit 1; }
  [[ $(type -t "opa_paste") == function ]] || { echo "error: opa_paste func undefined; see opa --help"; exit 1; }

  case "$cmd" in
    ""|list|--choose|-c)
      cmd="list"
      op_signin
      trap restore EXIT
      cmd_"$cmd" "$@"
      ;;

    signin)
      op_signin "$@"
      exit
      ;;

    clear)
      rm -f "$session_file"
      exit
      ;;

    -h|--help|help|usage)
      usage
      exit
      ;;
  esac

  # check any sourced extras
  if [[ $(type -t "opa_extras_$cmd") == function ]]; then
    op_signin
    trap restore EXIT
    opa_extras_"$cmd" "$@"
    exit
  fi

  echo "unknown command '$1'; type 'opa help' for more info"
  exit 1
}

main "$@"
