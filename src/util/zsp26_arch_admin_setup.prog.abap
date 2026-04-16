*&---------------------------------------------------------------------*
*& Report ZSP26_ARCH_ADMIN_SETUP
*&---------------------------------------------------------------------*
*& Bootstrap one-time utility: run from SE38 when ZSP26_ARCH_ADMIN is empty
*& to add the first admin. After that, use Hub → [Admin] (screen 0700).
*&---------------------------------------------------------------------*
*& Utility to add/remove admin users for the archive hub
*& Run from SE38 after activating table ZSP26_ARCH_ADMIN
*&---------------------------------------------------------------------*
REPORT zsp26_arch_admin_setup.

PARAMETERS:
  p_uname TYPE syuname DEFAULT sy-uname OBLIGATORY,
  p_del   TYPE char1  AS CHECKBOX DEFAULT ' '.  " Tick = REMOVE from admin

START-OF-SELECTION.

  DATA: ls_adm    TYPE zsp26_arch_admin,
        lt_admins TYPE TABLE OF zsp26_arch_admin,
        ls_u      TYPE zsp26_arch_admin.

  ls_adm-mandt = sy-mandt.
  ls_adm-uname = p_uname.

  IF p_del = 'X'.
    " Remove from admin list
    DELETE FROM zsp26_arch_admin
      WHERE uname = @p_uname.
    IF sy-subrc = 0.
      WRITE: / |User { p_uname } has been REMOVED from admin list.|.
    ELSE.
      WRITE: / |User { p_uname } is not in the admin list.|.
    ENDIF.
  ELSE.
    " Add to admin list
    INSERT zsp26_arch_admin FROM ls_adm.
    IF sy-subrc = 0.
      WRITE: / |User { p_uname } has been added as ADMIN.|.
    ELSEIF sy-subrc = 4.
      WRITE: / |User { p_uname } is already an ADMIN (no change).|.
    ELSE.
      WRITE: / |Error adding user { p_uname } (sy-subrc={ sy-subrc }).|.
    ENDIF.
  ENDIF.

  COMMIT WORK.

  " Display current admin list
  SKIP.
  WRITE: / '--- Current Admin List ---'.
  SELECT * FROM zsp26_arch_admin
    INTO TABLE lt_admins
    ORDER BY uname.
  IF lt_admins IS INITIAL.
    WRITE: / '(No admins found)'.
  ELSE.
    LOOP AT lt_admins INTO ls_u.
      WRITE: / ls_u-uname.
    ENDLOOP.
  ENDIF.
