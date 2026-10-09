# Changelog

## v0.1.0
- First release. Read-only: nothing runs at boot and no partition is ever written.
- Device: boot state read from the bootloader (catches hiding modules), kernel and KMI, battery and storage wear, live CPU.
- Black box: the previous boot's kernel log, with the panic lines picked out.
- Partitions: everything under by-name with sizes, and the inside of super.
- Logs: live kernel log and logcat with filters; tap an SELinux denial to get a sepolicy rule.
- Backup: critical, boot or full, with SHA256SUMS and backup-info.txt in the Fastboot Studio layout; verify on the phone.
- Tools: restart to bootloader, fastbootd, recovery or EDL; a support bundle with IMEI and serial masked.
- Arabic and English.
