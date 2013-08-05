#!/tvbin/tivosh
###############################################################################
#                               skip2time.tcl V1.1
# by mikerr@tivocommunity
#
# Overview
#       Skips to a specified number of hours:minutes into a programme
#
# Requirements
#
# Make sure you have newtext2osd installed in /var/hack/bin
# Fix the MWSTATE bug if you haven't already (run ./fixmwstate.tcl and reboot)
#
#
# Usage 
#
# When on the programme description screen:
# Press "skip" key to show menu
# type number of hours:mins to skip to
# press "skip" key again to jump into programme
# 
# (skip is the button under fast forward!)
# 
# Version history:
#
# 1.1: only shown/active after initial press of skip key

set OSD "/var/hack/bin/newtext2osd"

global db 
source $tcl_library/tv/sendkey.tcl
set verboseSendKeyG 0

proc RetryTransaction { body } {
  global errorInfo errorCode showerrors errcount logchan

set showerrors 0
  while { 1 } {
    set code [catch {transaction {uplevel $body}} string]
    if { $code == 0 } {
      return $string
    } elseif { $code == 1 } {
      if { $errorCode == "errTmActiveLockConflict" ||
        $errorCode == "errTmBackgroundHoldoff" ||
        $errorCode == "errFsLockConflict" } {
	 if {$showerrors == "true"} { txtout "                                  *" 2 }
          after 900
	 if {$showerrors == "true"} { txtout "" 2 }
	set errcount [expr $errcount +1]
        # retry the transaction
        continue
      }
      error $string $errorInfo $errorCode
    } elseif { $code == 2 } {
      return -code return $string
    } elseif { $code == 3 } {
      return -code break $string
    } elseif { $code == 4 } {
      return -code continue $string
    }
  }
}

#
# Extract a value from the /var/mwState logfile
# (needs the mwstate bug fixed on UK tivos)
#
# e.g. title of show currently in the GUI:
#
# GetVal "context.info.pRecordingM"
#

proc GetVal { fullpath } {
    global mwStateG
    set path [split $fullpath "."]
    set tree $mwStateG
    while { [llength $tree] > 0 && [llength $path] > 0 } {
      for { set i 0 } { $i < [llength $tree] && [lindex $tree $i] != [lindex $path 0]} { incr i 2 } {};
      if { [lindex $tree $i] != [lindex $path 0] } {
        error "/tmp/mwstate: $fullpath: [lindex $path 0] not found"
        return
      }
      set tree [lindex $tree [expr $i + 1]]
      set path [lrange $path 1 end]
    }
    return $tree
}

# Background error catcher

proc bgerroor errmessage {
global logchan

txtout "err: $errmessage" 3
puts $logchan "err: $errmessage"
}


# Print a menu
proc txtout { string line  }   {
global OSD showprogress
	set line [expr $line -2 ]
	# pad short strings
        set string "$string                                            " 
	# Clip long strings to screen
        set string [string range $string 0 34 ]
	if { $showprogress == 1} {
		exec $OSD -e --fg white3 --bg blue3  -x 5 -y $line -t "$string"
		}
}
proc blankmenu {} {
global OSD
	exec $OSD -y "-1" -t " "
	exec $OSD -y 0 -t " "
	exec $OSD -y 1 -t " "
}
proc pleasewait {message} {
global exit_delay

	txtout "$message" 1
	txtout "" 2
	txtout ".... please wait" 3

# after [expr $exit_delay * 1000]
}

set cursorpos 0
set s1 0
set s2 0
set s3 0
proc skipmenu {key} {
global cursorpos s1 s2 s3
if {$key == -1} {set cursorpos 0 }
if {$cursorpos == 1 } {set s1 $key }
if {$cursorpos == 2 } {set s2 $key }
if {$cursorpos == 3 } {set s3 $key ; set cursorpos 0 } 
incr cursorpos

	txtout "Skip to time: " 1
	txtout "" 2
	txtout "            $s1:$s2$s3" 3
}


proc GetGUIdata { } {
#
# Gets details of the currently displayed show directly from the GUI
#
# MWSTATE bug:
# This function *will not work* unless the MW_STATE bug is fixed i
# on UK 2.5.5 Tivos
#

global titles
global db 
global CurrentContext menu return_menu mwStateG 


# Delete the previous report
  set f [open /tmp/mwstate w] ; close $f

# Ask for a status report
  SendKey dumpState

set dots ""
set count 0
  while {$count < 9 } {

  set f [open /tmp/mwstate r]
  set mwStateG [read $f]
  regsub -all "\"" $mwStateG "\\\&quot;" mwStateG
  close $f
  		catch {set recording [GetVal "context.info.pRecordingM"] }
		set fsid 0
  		regexp {([0-9]*)/(.*)} $recording junk fsid junk
		if { $fsid != 0 } { break}
		incr count
		after 500
		set dots "$dots."
		# pleasewait "Getting folder info $dots"
		}

return $fsid
}
proc skip2time { } {
global db s1 s2 s3

set skipsecs [expr $s1 * 60 + $s2 * 10 + $s3 ]

# omit this next line to work in mins:secs 
set skipsecs [expr $skipsecs * 60]


set fsid [GetGUIdata]

            RetryTransaction {
                	set rec [db $db openid $fsid]
			set nbm [db $db createsub Bookmark $rec]

                  	dbobj $nbm set TimeMs [expr $skipsecs * 1000]
                  	dbobj $rec set Bookmark $nbm
			}
			event send $TmkEvent::EVT_DATA_CHANGED $TmkDataChanged::RECORDINGS_ON_DISK 0

			# go off this screen and come back
			# so "play" menu changes to "resume playing"
			SendKey "livetv"
			SendKey "left"
			SendKey "right"

}

proc EventCallback { type subtype } {
global EventData CurrentContext
 if { $type == $TmkEvent::EVT_MW_STATUS } {
   if { $subtype == $TmkEventMwStatus::CONTEXT_CHANGE || \
        $subtype == $TmkEventMwStatus::CONTEXT_PING_ACK } {
    binary scan $EventData I CurrentContext
   }
  }
}
set menu 0
proc keycallback { type subtype } {
global EventData CurrentContext Serial mwStateG
global menu db titles return_menu 

binary scan $EventData II data Serial 

set nowplayinglist 7
set programdesc 8

if { $type == $TmkEvent::EVT_REMOTEEVENT && $subtype == 0 && $CurrentContext == $programdesc} {
			set numpress [expr $data - $::evrc(0)]

			if { $data == $::evrc(catchup) && $menu == 0 } {  set menu 1; skipmenu -1 ;return }
			if { $numpress >= 0 && $numpress < 10  && $menu == 1} {skipmenu $numpress }
			if { $data == $::evrc(catchup) && $menu == 1 } { 

				pleasewait "Setting start time"
				skip2time 
				set menu 0
				}
}
}

# MAIN CODE 

set bg false

for {set i 0} {$i < [llength $argv]} {incr i} {

  set arg [lindex $argv $i]

  switch -- $arg {
  -run { set bg true }
  }
}


# If running in foreground without -run option, then fork to background process
if { $bg == "false" } {
	eval exec {[info nameofexecutable] [info script]} $argv {-run > /var/log/sortnp.log &} 
	exit
	}
set CurrentContext 0

event register $TmkEvent::EVT_MW_STATUS   EventCallback
event register $TmkEvent::EVT_REMOTEEVENT keycallback

set verboseSendKeyG 0
SendKey ping
vwait CurrentContext

set dbPoolSize [expr 100 * 1024]

set nowplayinglist 7
set programdesc 8

set mwStateG ""

set menu 0
set showerrors false
set run true
set cursor 0

set db [dbopen]


catch { EnableTransactionHoldoff true}

set showprogress 1

# Screen numbers
set nowplaying 7
set progdesc 8
set livetv 6

while {$run} { 
vwait CurrentContext 
}
