# Erlang/OTP releases for Android

This repository contains Erlang/OTP releases built for Android using the
official instructions found in HOWTO/INSTALL-ANDROID.md with the following
additional steps:

    $ # At first, set the deterministic option to get builds as reproducible
    $ # as possible. It will remove most references to absolute paths.
    $
    $ export ERL_COMPILER_OPTIONS=deterministic


    $ # For Erlang 23, apply the following patch from the root of the
    $ # source directory to support the ERL_ROOTDIR environment variable,
    $ # as supported upstream now with commits 28f2cc2 and 5475a9e.
    $ # patch -p 1 < /path/to/support_erl_rootdir_env.patch
    $ # This step is not needed anymore starting with Erlang 24.


    $ # Follow the regular build and release instructions then.


    $ # Edit the erl.src and start_erl.src scripts in the build directory
    $ # to remove the usage of the `sed` or `basename` commands in the
    $ # PROGNAME variable to keep compatibility with Android versions
    $ # older than Android 6.0 Marshmallow.


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


    $ # Remove a few more absolute paths manually as the Erlang/OTP build
    $ # system is not fully reproducible yet.
