PROCESS BEFORE OUTPUT.
  MODULE status_0600.
  MODULE init_fields_0600.

PROCESS AFTER INPUT.
  MODULE exit_command AT EXIT-COMMAND.
  FIELD gv_variant MODULE f4_gv_variant ON REQUEST.
  MODULE user_command_0600.
