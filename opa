#!/usr/bin/env bash

set -e

usage () {
  source ${OPA_EXTRAS_FILE:-"$HOME/.zsh/conf.d/opa-extras.sh"} 2>/dev/null || true
  cat <<EOF
op + fzf = L.F.E. Extend the functionality of 'op' (the 1Password CLI tool) by using
fzf and persistent sessions.

This tool requires:
  - op: https://1password.com/downloads/command-line/
  - fzf: https://github.com/junegunn/fzf

COMMANDS

  signin
      Sign-in to 1password and store the session token in the file specified
      in \$OPA_SESSION_FILE. By default, this is '$HOME/.config/op/.session-token'.
      The token is valid for 30 minutes.

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
EOF
}

# sign in to 1password and store the obtained session token
# in the configured session file
op_signin () {
  local op_session_file="$HOME/.config/op/.session-token"
  if [ -f "$op_session_file" ]; then
    OP_SESSION=$(cat $op_session_file 2>/dev/null)
    op --session "$OP_SESSION" user list > /dev/null 2>&1 && return
  else
    touch "$op_session_file"
  fi

  OP_SESSION=$(op signin --account my --raw)
  chmod 600 "$op_session_file"
  echo -n "$OP_SESSION" > "$op_session_file"
}

# copy the selected data in the clipboard, send a desktop notification,
# and then wait 15s before proceeding
copy_and_wait () {
  data="$1"

  existing="$(wl-paste)"
  echo -n "$data" | wl-copy
  notify-send "secret copied to clipboard"
  echo "secret copied to clipboard"
  echo "will clear after 15s"

  sleep 15
}

# restore the existing contents of the clipboard and
# effectively clear the secret
restore () {
  exitcode=$?
  echo -n "$existing" | wl-copy
  notify-send "secret cleared from clipboard"
  echo "secret cleared from clipboard"
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

  # FIXME:
  # [ERROR] 2023/04/06 15:32:49 "website" isn't a field in the "irinis cluster console" item. This may be because you are trying to access an autofill url, using the `--fields` flag. In order to access urls, you can use `op item get ITEM --format json | jq .urls`
  secret=$(op --session "$OP_SESSION" item get "$selected_id" --fields "type=concealed" --format=json | jq -r '.value' 2>/dev/null) || true
  if [[ "$secret" == "" || "$1" == "--choose" || "$1" == "-c" ]]; then
    while IFS= read -r field; do
      [ "$field" = "Fields:" ] && continue
      field_name=$(echo $field | cut -d':' -f1)
      [[ -z "${field_name// }" ]] || all_field_names+=("$field_name")
    done <<< $(op --session "$OP_SESSION" item get "$selected_id" | sed -n '/^Fields:$/,$p')

    echo "Choose field:"
    selected_field=$(printf "%s\n" "${all_field_names[@]}" | fzf --prompt "Field> " --height=~10)
    [ "$selected_field" = "" ] && { echo "no selection; bye"; exit; }
    echo -e "$selected_field\n"

    secret=$(op --session "$OP_SESSION" item get "$selected_id" --field "$selected_field")
    if [[ "$secret" == otpauth* ]]; then
      secret=$(op --session "$OP_SESSION" item get "$selected_id" --otp)
    fi
    secret=${secret#"\""}
    secret=${secret%"\""}
  fi

  copy_and_wait "$secret"
}

main () {
  cmd="$1"

  case "$cmd" in
    ""|list|--choose|-c)
      cmd="list"
      op_signin
      trap restore EXIT
      cmd_"$cmd" "$@"
      ;;

    signin)
      op_signin
      exit
      ;;

    clear)
      rm -f "$HOME/.config/op/.session-token"
      exit
      ;;

    -h|--help|help|usage)
      usage
      exit
      ;;
  esac

  # check any sourced extras
  source ${OPA_EXTRAS_FILE:-"$HOME/.zsh/conf.d/opa-extras.sh"} 2>/dev/null || true
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
