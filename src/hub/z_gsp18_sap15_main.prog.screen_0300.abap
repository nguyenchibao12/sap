PROCESS BEFORE OUTPUT.
  MODULE STATUS_0300.
  " Initialize default values on screen open
  MODULE INIT_FIELDS_0300.

PROCESS AFTER INPUT.
  " Handle exit/cancel buttons without field validation
  MODULE EXIT_COMMAND AT EXIT-COMMAND.

  FIELD GV_VARIANT MODULE CHECK_VARIANT_0300.

  " Handle user commands (Execute, Save, Back)
  MODULE USER_COMMAND_0300.
