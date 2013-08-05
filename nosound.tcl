#!/tvbin/tivosh
###############################################################################
#                               nosound.tcl 
# by mikerr@tivocommunity
#
# Overview
#
#	Reboots if the tivo starts up without sound
#
#	won't reboot if the tivo has been restarted more 
#	than 5 times in the current hour !


set maxboot 5

set logfile "/var/log/kernel"
set fp [open $logfile]


set booting "Starting rc.sysinit"
set soundOff "Unknown MSP product"


set boot 0
set ok 1


set now [clock format [clock seconds] -format "%a %b %d %H"]
set timeset "Time set to: $now"

while { [gets $fp line] != -1 } {
	if { [string first $timeset  $line] != -1 } { incr boot }
	if { [string first $booting  $line] != -1 } { set ok 1 }
	if { [string first $soundOff $line] != -1 } { set ok 0 }
     }

if { $boot >= $maxboot } { 
	puts "$boot reboots in one hour is too many, exiting"
	exit }

if { $ok } {
	puts "Last boot was with sound, all OK"
} else {
	puts "No sound !! Rebooting..."
	exec reboot
}
