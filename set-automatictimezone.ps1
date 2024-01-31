# set-automatictimezone.ps1 - one line script that sets registry entry for "Set automatic time zone". 
# This can also be done in Intune via configuration profile.
# by Chris Hewinson

Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate -Name Start -Value "3"
