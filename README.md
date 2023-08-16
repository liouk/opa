# :shell: opa
```
opa extends the functionality of 'op' (the 1Password CLI tool) by using fzf and
persistent sessions.

This tool requires:
  - op: https://1password.com/downloads/command-line/
  - fzf: https://github.com/junegunn/fzf

COMMANDS

  signin
      Sign-in to 1password and store the session token in the file specified
      in $OPA_SESSION_FILE. By default, this is '/home/ilias/.config/op/.session-token'.
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
  for more info.

  test
      A user defined extra command :)

EXTRAS DEFINITION
  This script can be extended to run user defined commands, on top of the ones defined
  here. The commands must be defined as functions in a shell file; the location of the
  file can be set in $OPA_EXTRAS_FILE (defaults to '/home/ilias/.zsh/conf.d/opa-extras.sh').

  Each command must be defined in a function called 'opa_extras_<cmd name>'; for example:

    opa_extras_test () {
      echo "You can invoke this command simply by typing 'opa test'."
    }

  The script first looks at its own commands, and then the extras; therefore you can't
  hijack any command names as they will be evaluated first.

  You can document your extras by writing a func called 'opa_usage_extras' which prints
  the docs within the 'EXTRA COMMANDS' section above. Follow the structure of this doc
  for the best results.
```
