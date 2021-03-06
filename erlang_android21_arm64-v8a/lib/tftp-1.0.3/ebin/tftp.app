{application, tftp,
 [{description, "TFTP application"},
  {vsn, "1.0.3"},
  {registered, []},
  {mod, { tftp_app, []}},
  {applications,
   [kernel,
    stdlib
   ]},
  {env,[]},
  {modules, [
             tftp,
             tftp_app,
             tftp_binary,
             tftp_engine,
             tftp_file,
             tftp_lib,
             tftp_logger,
             tftp_sup
            ]},
  {runtime_dependencies, ["erts-6.0","stdlib-3.5","kernel-6.0"]}
 ]}.
