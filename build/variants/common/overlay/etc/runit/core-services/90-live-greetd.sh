# /etc/runit/core-services/90-live-greetd.sh
#
# Live ISO only: configure greetd to log the live user straight into the
# session chosen by the build variant (LIVE_SESSION in its config file).
#
# This file is sourced by /etc/runit/1, not executed, so it must never
# call `exit` (that would abort runit's stage 1 and stall the boot).

live_config_file="/etc/default/live.conf"
live_session_file="/etc/default/live-session"
greetd_config_file="/etc/greetd/config.toml"

# Only run on the live image. adduser.sh in the initramfs creates
# live.conf, so an installed system will not have it.
if [ -r "$live_config_file" ]; then

    # build.sh only writes this file when the variant sets LIVE_SESSION.
    if [ -r "$live_session_file" ]; then

        # Make sure there is a greetd config we can append to.
        if [ -w "$greetd_config_file" ]; then

            # Booting with "live.greeter" on the kernel command line goes to
            # the greeter instead of logging in automatically.
            if ! grep -qw "live.greeter" /proc/cmdline; then

                # Do not add a second [initial_session] block if one exists.
                if ! grep -q "^\[initial_session\]" "$greetd_config_file"; then

                    # The session file holds the command on its first line.
                    session_command=$(head -n 1 "$live_session_file")

                    if [ -n "$session_command" ]; then

                        # live.conf contains a line like: USERNAME=anon
                        live_username=$(grep "^USERNAME=" "$live_config_file" | tail -n 1 | cut -d "=" -f 2)

                        if [ -z "$live_username" ]; then
                            live_username="anon"
                        fi

                        msg "Enabling greetd autologin for ${live_username} (${session_command})..."

                        echo "" >> "$greetd_config_file"
                        echo "[initial_session]" >> "$greetd_config_file"
                        echo "command = \"${session_command}\"" >> "$greetd_config_file"
                        echo "user = \"${live_username}\"" >> "$greetd_config_file"
                    fi
                fi
            fi
        fi
    fi
fi

# Clean up
unset live_config_file
unset live_session_file
unset greetd_config_file
unset session_command
unset live_username
