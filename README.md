# Erlang/OTP releases for Android

This repository contains Erlang/OTP releases built for Android using the
official instructions found in HOWTO/INSTALL-ANDROID.md with the following
additional steps:

    $ # At first, set the determnistic option to get builds as reproducible
    $ # as possible. It will remove most references to absolute paths.
    $
    $ export ERL_COMPILER_OPTIONS=deterministic
    $
    $ # Follow the regular build instructions then.

    $ # When running the final `Install` script, the following generic
    $ # target installation directory is used.
    $
    $ cd /path/to/release/erlang_for_arm
    $ ./Install -cross -minimal /data/data/your.package.name/files/erlang
    $
    $ # The above value doesn't actually matter as it will be overridden
    $ # at runtime using the ERL_ROOTDIR environment variable to set
    $ # dynamically the absolute path of the Erlang runtime, as it is
    $ # configured in a different location for multiple users on Android

    $ # Make a copy of epmd instead of having a symlink
    $ rm bin/epmd
    $ cp erts-X.Y.Z/bin/epmd bin/epmd

    $ # Finally edit the erl and start_erl scripts to remove the usage
    $ # of the `sed` command in the PROGNAME variable.

    $ # Remove a few more absolute paths manually as the Erlang/OTP build
    $ # system is not fully reproducible yet.
