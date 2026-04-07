PROCESS BEFORE OUTPUT.
  MODULE status_0500.
  MODULE init_fields_0500.

PROCESS AFTER INPUT.
  MODULE exit_command AT EXIT-COMMAND.
  FIELD gv_variant MODULE f4_gv_variant ON REQUEST.
  MODULE user_command_0500.
