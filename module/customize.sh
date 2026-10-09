# Runs once, at install time. Nothing is copied outside the module folder and no boot
# scripts are installed, so the module cannot cause a bootloop.

ui_print "- Fastboot Studio Companion"

if [ "$KSU" = true ]; then
    ui_print "- KernelSU: open the module's WebUI from the Modules page"
elif [ "$APATCH" = true ]; then
    ui_print "- APatch: open the module's WebUI from the Modules page"
else
    ui_print "- Magisk has no WebUI of its own: open this module in MMRL or WebUI X,"
    ui_print "  or press Action in Magisk for a text report"
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/bin/fbs" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755

ui_print "- Backups and reports go to /sdcard/FastbootStudio"
