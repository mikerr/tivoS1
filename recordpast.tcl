#!/tvbin/tivosh
###############################################################################
#                               recordpast.tcl V1.3
# by mikerr@tivocommunity
#
# Overview
#       Enables you to setup a season pass 
#	directly from a recording in now playing.
#
# 1.4  Better duplicate checking 
# 1.3  Added on screen feedback
#      removed livetv functions
#      duplicate checking
# 1.2  added a fix for british summertime
# 1.1a bugfix
# 1.1  Also setup season pass by pressing record on any now-playing program description screen
# 1.0  setup season pass by pressing select on a past recording in live-tv guide

global db 
source $tcl_library/tv/sendkey.tcl
set verboseSendKeyG 0

proc max {a b} { if {$a>$b } { return  $a } else { return $b} }
proc strim {str} { return [string trim $str "\{\} "] }
proc defaultval {val1 val2} {
	if { $val2 != "" } {
		return $val2
	} else {
		return $val1
	}
}
proc bgerror errormessage { 
	 # puts $errormessage
 	}

proc RetryTransaction { body } {
  global errorInfo errorCode showerrors logchan

set showerrors "true"
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
set OSD "/var/hack/bin/newtext2osd"

# Print a menu
proc txtout { string line  }   {
global OSD
	set line [expr $line -2 ]
	# pad short strings
        set string "$string                                            " 
	# Clip long strings to screen
        set string [string range $string 0 34 ]
	exec $OSD -e --fg white3 --bg blue3  -x 5 -y $line -t "$string"
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

after [expr $exit_delay * 1000]
}

proc CreateSeasonPass { stationfsid seriesfsid } {
   global db

   set maxpri 0
   ForeachMfsFile fsid name type "/SeasonPass" "" {
	RetryTransaction {
		set sp [db $db openid $fsid]
		set type [defaultval 1 [dbobj $sp get Type]]
		set oldseriesfsid ""
		if { $type == 1 } {
		   set series [dbobj $sp get Series]
		   set oldseriesfsid [dbobj $series fsid]
		   }
         	if { [string compare $seriesfsid $oldseriesfsid] == 0 } {
	 		txtout "      duplicate season pass exists " 2 
	 		after 2000
			txtout "" 2 
			return 
			}
		}
      scan $name "%d~%d" num dummy
      if { $num > $maxpri } {
         set maxpri $num
      }
   }
   incr maxpri
	RetryTransaction {
      set sp [db $db create SeasonPass]
      dbobj $sp set Priority $maxpri
      set series [db $db openid $seriesfsid]
      dbobj $sp set Series $series
      set station [db $db openid $stationfsid]
      dbobj $sp set Station $station
      dbobj $sp set MaxRecordings 5
	}

      set spfsid [dbobj $sp fsid]
   return $spfsid
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

proc EventCallback { type subtype } {
global EventData CurrentContext
 if { $type == $TmkEvent::EVT_MW_STATUS } {
   if { $subtype == $TmkEventMwStatus::CONTEXT_CHANGE || \
        $subtype == $TmkEventMwStatus::CONTEXT_PING_ACK } {
    binary scan $EventData I CurrentContext
   }
  }
}

proc keycallback { type subtype } {
global EventData CurrentContext Serial mwStateG
global db toggle dlsval lastsp lasttime
binary scan $EventData II data Serial 

set progdesc 8
set livetv 6
if { $type == $TmkEvent::EVT_REMOTEEVENT } {
      	if { $data == $::evrc(save) && $CurrentContext == $progdesc} {

		# we're getting double keypresses.. 
		# so only respond to one every 10 seconds

		set lastpress [expr [clock seconds] - $lasttime]
		if {$lastpress < 10 } { return }
		set lasttime [clock seconds]

		pleasewait "Adding season pass.."
		# Delete the previous report
  		set f [open /tmp/mwstate w] ; close $f

		# Ask for a status report
  		SendKey dumpState

		set count 0
		while { $count < 10 } {
		after 1000

  		set f [open /tmp/mwstate r]
  		set mwStateG [read $f]
  		regsub -all "\"" $mwStateG "\\\&quot;" mwStateG
  		close $f

		if { [catch [set recording [strim [GetVal "context.info.pRecordingM"] ]]] } { 
			break }

		incr count
		}

		RetryTransaction { 
				regexp {([0-9]*)/(.*)} $recording junk fsid junk
				set rec [db $db openid $fsid]
				set showing [dbobj $rec get Showing]

				set program [dbobj $showing get Program]
				set foundtitle [dbobj $program get Title]

				set series [dbobj $program get Series]
				set seriesfsid [dbobj $series fsid]

				set station [dbobj $showing get Station]
   				set stationfsid [dbobj $station fsid]
				}

		if {[string compare $foundtitle $lastsp] != 0 } {
			pleasewait "Adding SP: $foundtitle"
			set lastsp $foundtitle
			after 1000
			blankmenu
			CreateSeasonPass $stationfsid $seriesfsid 
			event send $TmkEvent::EVT_DATA_CHANGED $TmkDataChanged::SEASON_PASS 
			}
		blankmenu
		return
	     }
	}
}


# MAIN CODE 
set toggle 0
set lasttime 0
set lastsp ""
set CurrentContext 0



set run true
set bg false


for {set i 0} {$i < [llength $argv]} {incr i} {

  set arg [lindex $argv $i]

  switch -- $arg {
  -run { set bg true }
  }
}


# If running in foreground without -run option, then fork to background process
if { $bg == "false" } {
	eval exec {[info nameofexecutable] [info script]} $argv {-run > /dev/null &} 
	exit
	}


event register $TmkEvent::EVT_MW_STATUS   EventCallback
event register $TmkEvent::EVT_REMOTEEVENT keycallback

if { $CurrentContext == 0 } {
 set verboseSendKeyG 0
 SendKey ping
 vwait CurrentContext
}


set mwStateG ""
set exit_delay 1

set dbPoolSize [expr 100 * 1024]
set db [dbopen $dbPoolSize]
RetryTransaction { set swsystem [db $db open /SwSystem/ACTIVE] }


while { 1 } {  
# UK only:
# set daylightsavingtime


      set date [clock format [clock seconds] -format "%1d %w %1m %1H %1M"]
      scan $date "%d %d %d %d %d" dom dow month hour min
      set dlsval 0
         if {$month > 3 && $month < 10} {
            set dlsval 1
         } elseif {$month == 3 && $dom >= 25 && $dow == 0 && $hour >= 1} {
            set dlsval 1
         } elseif {$month == 3 && $dom >= 25 && $dow != 0 && ($dom-24-$dow >= 1) } {
            set dlsval 1
         }

vwait CurrentContext  }

