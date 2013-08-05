#!/tvbin/tivosh
###############################################################################
#                               sortnp.tcl V0.57
# by mikerr@tivocommunity
#
# Overview
#       sortnp processes the Now Playing list and sorts it by title
#
#  Also adds episode details into title
#
# Requirements
#
# Make sure you have newtext2osd installed in /var/hack/bin
# Fix the MWSTATE bug if you haven't already (run ./fixmwstate.tcl and reboot)
#
# Installation
#	put sortnp.tcl in /var/hack and run it ;)
# 
# while in the now playing list on tivo:
#
# Press the following keys on the tivo peanut remote
#
# (0) to bring up the menu
#
# (replay) to sort alphabetically by title ( A-Z / Z-A )
#
# (skip to end) to sort by date (Tivo classic mode)
#
# (4) to add episode titles
#
# (8) to exit the program  
#
# History:
# 0.57
# changed a few sendkeys to go directly to nowplaying
# 
# 
# 0.54
# Remote shortcut keys, much faster folder operation.
# programmes in folders now show episode info 
# 0.53 
# 0.52 pause button - to make/expand folders
# 0.49
# 0.48
# - added transactionholdoff - speeds up all operations
# 0.47
# - bugfix when no films in np list
# - bugfix showing duration 0.00 for shows that cross midnight
# 0.46
# - added sort by duration (mainly for films)
# - background adding of episode titles
# - progress when sorting
# 0.45 
# - moved to a 3 menu system: sort / folder / advanced
# - so sorts are now individually selectable
# 0.44 
# - saves / updates a datafile for folders (compatible with tivoweb folders modules)
# 0.43 
# - Uses its own internal lists more, tivo database less, so should be faster
# - Films are put in folders too
#


# Set this to 0 if you don't want the menu to come up after a search
# e.g. if using autospace

set return_menu 1


# How long to cache now-playing (speeds up sorting, but ignores new recordings)
# Default is 60 (minutes)

set cacheTime 60

# delay after exiting now playing to give tivo time to flush the database
# - use higher number if you see lots of *'s  (delays) during sorting
#
# default is 0 (seconds)

set exit_delay 0

set folders 1
set folderdate [expr [clock seconds] / 86400]
set fakedate [expr [clock scan "01/01/00"] / 86400]
set lastchan 0
set lasttitleupdate [clock seconds]

# whether to add episode titles or not (on channel change)
set addtitles 0

set logchan [open "/var/log/sortnp.log" "w"]
set logchan "stdout"

set OSD "/var/hack/bin/newtext2osd"

global db 
source $tcl_library/tv/sendkey.tcl
set verboseSendKeyG 0

proc max {a b} { if {$a>$b } { return  $a } else { return $b} }
proc min {a b} { if {$a<$b } { return  $a } else { return $b} }

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
          after 500
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

proc bgerror errmessage {
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
		exec $OSD -e --fg white3 -bg 0 -x 5 -y $line -t "$string"
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

# show a percentage bar on screen
proc showbar {percent} {
global OSD showprogress


	     	if  { [expr $percent % 2 ] == 0} {
			if {$percent  > 0} {

				for {set x 0; set bar ""} {$x < [expr $percent / 3]} {incr x} {
					set bar "$bar " }
				# txtout $bar 2
				exec $OSD -e --bg white3 -x 5 -y 1 -t "$bar"

				# txtout "                              $percent%" 2
				}
			}

}
proc sortmenu {} {

	txtout "1) Sort A-Z        4) Add ep titles" 1
	txtout "2) Sort by Length  5) Del ep titles" 2
	txtout "3) Sort by Date    6) Folders menu " 3
}
proc foldersmenu {} {
	txtout "1) Make folders               " 1
	txtout "2) Remove Folders             " 2
	txtout "              6) Advanced menu" 3
}
proc advancedmenu {} {
	txtout "1) Restore all deleted shows   " 1
	txtout "2) Convert all suggs to normal " 2
	txtout "                   6) Main menu" 3
}
proc playmenu {} {
	txtout "1) Make a series folder " 1
	txtout "" 2
	txtout "2) Expand folder" 3
}


proc gotoTivoCentral {} {
global CurrentContext exit_delay
if {$CurrentContext != 2} { 
	SendKey "tivo" 
	vwait CurrentContext }
}
proc gotoNowPlaying {} {
SendKey "nowShowing" 
vwait CurrentContext 
}
proc strim {str} { return [string trim $str "\{\} "] }

proc printtime { timetaken } {
global titles errcount

set numshows [llength $titles]

set speed 0 
catch {set speed [expr $numshows / $timetaken]}

# Max speed: 20 shows/sec down to 3-4 shows/sec when tivo is busy

puts stdout "Done $numshows shows ( $speed shows/sec ) $timetaken seconds, $errcount delays"
}


#
# Restores deleted shows to suggestions, with an expiry date of today 
#

proc undeleteall {} {
global db

set today [expr [clock seconds] / 86400]

ForeachMfsFile fsid name "tyDb" "/Recording/Active" "" {
            RetryTransaction {
                	set rec [db $db openid $fsid]
			set state [dbobj $rec get State]

			if {$state==5} {
				# Restore deleted:
				dbobj $rec set State 4 

				# restore as suggestion
				dbobj $rec set SelectionType 6 
				dbobj $rec set ErrorString ""

				# Make it only hang around for 1 day
				dbobj $rec set ExpirationDate [expr $today +1]
				}
			}
		}
}


#
# Convert all suggestions into regular recordings
#

proc sugg2regular {} {
global db
set today [expr [clock seconds] / 86400]
ForeachMfsFile fsid name "tyDb" "/Recording/NowShowing" "" {
       RetryTransaction {
                	set rec [db $db openid $fsid]
                	set seltype [dbobj $rec get SelectionType]

			if {$seltype == 6} { dbobj $rec set SelectionType 9  

					# Set the to stay for at least a week
				             dbobj $rec set ExpirationDate [expr $today + 7]
					   }
			}
	}
}

proc sortTitles { az  } {

global sorttoggle return_menu titles

gotoTivoCentral
set menu $return_menu
if { $az == 0 } { 
	set sort "(A-Z)"
	} else { 
	set sort "(Z-A)" 
	}
pleasewait "Sorting by Title $sort"
gettitles
if {$az == 0 } {
	set titles [lsort -decreasing $titles] 
	} else {
	set titles [lsort -increasing $titles] 
	}
updatenowplaying 1
gotoNowPlaying
set sorttoggle [expr 1 - $sorttoggle]
}

#########################################
# FOLDERS CODE ######
#########################################

proc setupchannel {} {
global db
global folderchannel

	# setup dummy channel
  RetryTransaction {
    	      set station [db $db create Station]
    	      dbobj $station set Name     "Folder"
              dbobj $station set CallSign "Folder"

              set setup [db $db open /Setup]
              set sources [dbobj $setup get Source]
              set source [lindex $sources 0]

              set newchanobj [db $db createsub Channel $source]
 
              dbobj $newchanobj set Station $station
              dbobj $newchanobj set Number $folderchannel
              dbobj $source add Channel $newchanobj

	 }
}

proc getLogo {} {
global db
global logoId
global folderchannel

	RetryTransaction {
              set setup [db $db open /Setup]
              set sources [dbobj $setup get Source]
              set source [lindex $sources 0]

	      set channels [dbobj $source get Channel]
              
	      set index 0

	      foreach item $channels {
			
	 		set channel $item
	 		# set channel [lindex $channels $index]
              		set number [dbobj $channel get Number]  
              		if {$number == $folderchannel} {

				set station [dbobj $channel get Station]
              			set stationname [dbobj $station get Name]
              			set logoindex [dbobj $station get LogoIndex]

	      			set logoId $logoindex
				}

		}
	     }
}

# This proc is a much modified form of merge from
#
# merge 1.05
# (c)2002 embeem
#
# Merge a list of fsid's into one recording 
#


proc merge { recordings foldername} {
global db folder_titles folder_list nodelete logoId folderchannel fldrinfo lastcache nplist folderdate


  set today [expr [clock seconds] / 86400]
  set now   [expr [clock seconds] % 86400 + 10]


# Kill the titles cache, as we are adding entries
# set lastcache 0 

if { $recordings == "" } { return}
  RetryTransaction {
    set duration 0
    set newtitle ""
    set parttime 0
    set eps 0


    set multirec [db $db create Recording]
    dbobj $multirec set BitRate 0 ;# obsolete
    dbobj $multirec set ErrorString $recordings
    dbobj $multirec set RecordQuality 100
    dbobj $multirec set Score 0
    dbobj $multirec set SelectionType 3
    dbobj $multirec set State 4 # complete

      foreach id $recordings  {
       incr eps
       set sub "10"

       set recording [db $db openidconstruction $id $sub]
       set showing   [dbobj $recording get Showing]

       set parts     [dbobj $recording get Part]


       foreach part $parts {
         set multipart [db $db createsub RecordingPart $multirec]
         dbobj $multipart copyfrom $part
         dbobj $multipart set Begin $parttime
         set elapsed  [expr [dbobj $part get End] - [dbobj $part get Begin]]
         set parttime [expr $parttime + $elapsed]
         dbobj $multipart set End $parttime 
         dbobj $multirec add Part $multipart
       }
       set duration "$duration + [dbobj $showing get Duration]"

       set program [dbobj $showing get Program]
       set title [strim [dbobj $program get Title]]


	set seriesname ""
			# inserted recordings don't have a series object at all !

			# strip everything after the ":" in a title

					set end [string first ":" $title]
					if { $end > 0 } { 
						set end [expr $end -1] 
						set seriesname [string range $title 0 $end]
						} else { 
						set seriesname $title 
						} 


       set newtitle "$newtitle $seriesname : [strim [dbobj $program get EpisodeTitle]]\n"
     } 
     set duration [expr $duration]

    dbobj $multirec set StartDate $folderdate
    dbobj $multirec set StartTime [expr $now - $duration]
    dbobj $multirec set StopDate $folderdate
    dbobj $multirec set StopTime $now 
    dbobj $multirec set ExpirationDate [expr $today + 28]
    dbobj $multirec set ExpirationTime $now

    set series [db $db create Series]
    dbobj $series set Title $seriesname

    set program [db $db create Program]

    dbobj $program set Title "[string range $foldername 0 20] ($eps eps)" 
    dbobj $program set Description "$newtitle"
    dbobj $program set IsEpisode 0
    dbobj $program add Series $series

    set station [db $db create Station]


    	     dbobj $station set Name     "Folder"
             dbobj $station set CallSign "Folder"
             dbobj $station set LogoIndex  $logoId

    set showing [db $db createsub Showing $multirec]
    dbobj $showing  set Date $today
    dbobj $showing  set Duration $duration
    dbobj $showing  set Time [expr $now - $duration]
    dbobj $showing  set Program $program
    dbobj $showing  set Station $station
    dbobj $multirec set Showing $showing
    dbobj $multirec set ActualShowing $showing

  }

set nplist [linsert $nplist 1 "{$foldername}"]

# Successful merge, now move recordings

# For date mode, we don't need to do anything (we change dates ad hoc later)
if {$nodelete != 2} {
	foreach fsid $recordings {
		RetryTransaction {
                	set rec [db $db openid $fsid]
			dbobj $rec set ErrorString "InFolder $foldername"

			# Don't delete, just change to suggestion
			if {$nodelete == 1} { dbobj $rec set SelectionType 6 } 
			# delete
			if {$nodelete == 0} { dbobj $rec set State 5 }
			}
		}
}


set storedlist  [linsert $recordings 0 $foldername]

set dupe 0
foreach item $fldrinfo {
			set title [lindex $item 0]
			if {[string match $title $foldername] } {set dupe  1 } }

if {$dupe == 0 } {

	lappend fldrinfo $storedlist

	set npffile "/var/hack/npf"

	set npfhnd [open $npffile w]
	puts $npfhnd $fldrinfo
	close $npfhnd
	}
event send $TmkEvent::EVT_DATA_CHANGED 2 0
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
		after 2000
		set dots "$dots."
		pleasewait "Getting folder info $dots"
		}

return $fsid
}


proc EnterFolder { } {
global db 
global titles nodelete
global CurrentContext menu return_menu mwStateG 

# Get info on current programme in GUI:

set fsid [GetGUIdata]

# exit if user has navigated away already


if {$CurrentContext != 8 } {return}
            RetryTransaction {
                	set rec [db $db openid $fsid]

                	set showing [dbobj $rec get Showing]
                	set program [dbobj $showing get Program]
			set station [dbobj $showing get Station]

			set stationname [dbobj $station get Name]
                	set title [strim [dbobj $program get Title]]
			}

  if { $stationname == "Folder" } {

       		set foldername [string range $title 0 [expr  [string first "(" $title ] -2 ] ]
		pleasewait "Expanding Folder: $foldername"

		gettitles

		# don't need to rescan ?
		set airdate 0
		lappend folder_list  "{$foldername} $airdate $fsid"

		expandfolders "$foldername" 

		gotoNowPlaying 

		SendKey "down"
		# remove folder object:

            	RetryTransaction {
                	# set rec [db $db openid $fsid]

                	# dbobj $rec set State 5
			# dbobj $rec markasrubbish
			}

		# revert titles to normal (will show up a few mins later)
		after 10000
		resettitles "$foldername" 

		} else {
		# pleasewait "Not a folder !"


		# Get info on current programme in GUI:
		set shows ""

            	RetryTransaction {
                	set rec [db $db openid $fsid]
			# if this is a folder, then errorstring will contain a list of show fsids
			set shows [strim [ dbobj $rec get ErrorString]]

                	set showing [dbobj $rec get Showing]
                	set program [dbobj $showing get Program]
			set station [dbobj $showing get Station]
			set stationname [dbobj $station get Name]

                	set title [strim [dbobj $program get Title]]

			# inserted recordings don't have a series object at all !

			# strip everything after the ":" in a title

					set end [string first ":" $title]
					if { $end > 0 } { 
						set end [expr $end -1] 
						set seriesname [string range $title 0 $end]
						} else { 
						set seriesname $title 
						} 
			}


putlog "making folder $seriesname"
# gotoTivoCentral
set menu $return_menu
pleasewait "making folder $seriesname"
gettitles
set titles [lsort -decreasing $titles]
makefolders $seriesname
gotoNowPlaying
}


}
proc makefolders {theseries} {
global db titles folder_titles
global errcount nosuggs misc lastcache
global topoflist

set lasttitle ""
set numeps 1

set now [clock seconds]
putlog "Making folders"
set folder_titles ""
set errcount 0

set lasttitle ""
set lastfsid ""

if {$theseries == ""} { 

set recordings ""  
set allseriesrecordings ""  
foreach title $titles  {
	# Title format: <title> <oad> <year> <fsid>

	# Extract fsid (last field) from title string

   	set fsid [lindex $title end]
   	set title [lindex $title 0]

	if {$lasttitle == $title}  {
		set numeps [expr $numeps + 1]
		
		if {$numeps == 2} { 
			lappend allseriesrecordings $lastfsid
			lappend recordings $lastfsid }
		lappend recordings $fsid
		lappend allseriesrecordings $fsid
		}  else {  
		if {$numeps > 1} { putlog "$lasttitle ($numeps eps)"
			        txtout "      [string range $lasttitle 0 20] ($numeps eps)"  2
				catch { merge $recordings $lasttitle}
				set recordings "" 
				}
		set numeps 1
		}
	set lasttitle $title	
	set lastfsid $fsid	
	}
set films 1
set film_list ""
if { $films == 1 } { 
		foreach item $titles  {
   				set fsid [lindex $item end]
   				set title [lindex $item 0]
   				set year [lindex $item 2]

				if { $year > 0} {
					lappend film_list $fsid
					}
				}

		   if {[llength $film_list] > 1 } { catch { merge $film_list "Films"}}
		   }
if { $misc == 1 } { 
		foreach item $titles  {
   				set fsid [lindex $item end]
   				set title [lindex $item 0]
				if {[lsearch $allseriesrecordings $fsid] == -1 } {
					lappend nonseries $fsid }
				}
		  if { [catch { merge $nonseries "Misc"}] != 0 }  {putlog "gone wrong" }
		  }
} else {

# called with seriesfolder argument:
pleasewait "Making folder $theseries"
set serieslist ""
set count 0
foreach title $titles  {
   	set fsid [lindex $title end]
   	set title [lindex $title 0]
	if {$title == $theseries } { incr count ; lappend serieslist $fsid }
	}
if { $count > 1 } {
		  merge $serieslist "$theseries"
		  foreach fsid $serieslist  {
             		RetryTransaction {
                	 	set rec [db $db openid $fsid]
				set Newdate 361
				dbobj $rec set StartDate $Newdate
				dbobj $rec set StopDate $Newdate
				}
			}
		  } else { 
		  pleasewait "Single episode, folder not created"
		  after 2000
		  }
blankmenu
}

# kill the cache of shows, as we are adding more back in
# would be much quicker to append as we add folders, really

set lastcache 0
# gettitles
# updatenowplaying 1

set timetaken [expr [clock seconds] - $now]
printtime $timetaken 
}



#
# Expand selected folder(s) back into regular recordings
#
# Method: undeletes all recordings that have the tag of "put in folder"
#

proc expandfolders {foldername} {
global db errcount titles nodelete logchan folder_list fldrinfo lastcache topoflist folderdate

# Restore the shows matching "foldername" as seriestitle

set now [clock seconds]
set errcount 0

if {$foldername == "*" } {
	putlog "Hiding / expanding all folders" 
gettitles
# Delete all folder objects
set allshows ""
	foreach item $folder_list {
		set fsid [lindex $item end]
            	RetryTransaction {
	               		set rec [db $db openid $fsid]

				if { $nodelete == 0 } {
					# build a list of shows that were in folders
					set shows [strim [dbobj $rec get ErrorString]]
					set allshows [ concat $allshows $shows]
					}
				dbobj $rec set State 5
				dbobj $rec markasrubbish
				}	
	    }

        if { $nodelete == 0 } {

		# kill the cache of shows, as we are adding more back in
		set lastcache 0

		# restore / undelete shows
		foreach fsid $allshows {
            		RetryTransaction {
                			set rec [db $db openid $fsid]
					dbobj $rec set State 4
					}
			}
		 }
	} 

# end of expanding all folders

# If we were called with an actual single foldername
if { $foldername != "*" } {

	putlog "Expanding folder $foldername"

	# set the folder itself to be bottom of the folder list:

	set oldfolderdate $folderdate
	foreach item $folder_list {
		set fsid [lindex $item end]
   		set title [lindex $item 0]
             	RetryTransaction {
                	 	set rec [db $db openid $fsid]
				set Newdate $oldfolderdate
				# [string match "$foldername*" $title] 
				if { [string match "$foldername*" $title] == 1 } {


						set folderdate [expr $folderdate + 3]
						set Newdate $folderdate  

						set shows [strim [dbobj $rec get ErrorString]]
						} 
				dbobj $rec set StartDate $Newdate
				dbobj $rec set StopDate $Newdate
				}
		}

	# Now group all the episodes together at the top of the show list:
	# and set all other shows to the bottom

	set matched 0
	if { 0 } { 

	foreach item $titles {
		set fsid [lindex $item end]
   		set title [lindex $item 0]

             		RetryTransaction {
                	 	set rec [db $db openid $fsid]

				# Every other recording will be set to low date:
				set Newdate 0

				# Matching folder recordings are set to a high date:
				if { [string match "$foldername*" $title] == 1 } {
						set Newdate 360 
						incr matched }

				dbobj $rec set StartDate $Newdate
				dbobj $rec set StopDate $Newdate
			}
		}

	}
	# Set all shows inside this folder to top of list
	set topoflist  [expr $topoflist  + 1 ]
	foreach fsid $shows {
             		RetryTransaction {
                	 	set rec [db $db openid $fsid]

				# Matching folder recordings are set to a high date:
				# 359
				# show immediately underneath folder	

				set StartTime [dbobj $rec get StartTime]
				set StopTime [dbobj $rec get StopTime]

				set NewDate [expr $folderdate - 1 ] 
				set NewStopDate $NewDate


				# fix date if recording spans 12 midnight
				if {$StartTime > $StopTime} { incr NewStopDate }

				dbobj $rec set StopDate $NewStopDate
				dbobj $rec set StartDate $NewDate

				# change title to the episode title
				# and add indent spaces
				# e.g. Star Trek: The Menagerie 

				# Star Trek (3 eps)
				#     The Menagerie

                		set showing [dbobj $rec get Showing]
                		set program [dbobj $showing get Program]
                		set title [strim [dbobj $program get Title]]
                		set eptitle [strim [dbobj $program get EpisodeTitle]]
                		set seriestitle [strim [dbobj [dbobj $program get Series] get Title]]

				if { $title != $seriestitle } { 
					# reset back to normal
					dbobj $program set Title $seriestitle 
					} else {
						if { $eptitle != "" } { dbobj $program set Title "   $eptitle" }
						}
			}
		}

	} 

# undelete items
if { $nodelete == 0 } {
	foreach fsid $shows {
             		RetryTransaction {
                	 	set rec [db $db openid $fsid]
				set state [dbobj $rec get State]

				# restore deleted program
				dbobj $rec set State 4 
			}
		}

	}

set timetaken [expr [clock seconds] - $now]
printtime $timetaken 
event send $TmkEvent::EVT_DATA_CHANGED 2 0
}

proc resettitles { foldername } {

global db folder_list


	foreach item $folder_list {
		set fsid [lindex $item end]
   		set title [lindex $item 0]
             	RetryTransaction {
				# [string match "$foldername*" $title] 
				if { [string match "$foldername*" $title] == 1 } {
                	 			set rec [db $db openid $fsid]
						set shows [strim [dbobj $rec get ErrorString]]
						} 
				}
		}


	foreach fsid $shows {
             		RetryTransaction {
                	 	set rec [db $db openid $fsid]

                		set showing [dbobj $rec get Showing]
                		set program [dbobj $showing get Program]
                		set seriestitle [strim [dbobj [dbobj $program get Series] get Title]]

				if { $title != $seriestitle } { 
					# reset back to normal
					dbobj $program set Title $seriestitle 
					} 
			}
	}
}
#############################
# End of Folders code
#############################

proc EventCallback { type subtype } {
global EventData CurrentContext bonk


 if { $type == $TmkEvent::EVT_MW_STATUS } {

   # BONK = noise when at the top of now playing list.
   if {$subtype == $TmkEventMwStatus::BONKED} { incr bonk }
   if { $subtype == $TmkEventMwStatus::CONTEXT_CHANGE || \
        $subtype == $TmkEventMwStatus::CONTEXT_PING_ACK } {
    binary scan $EventData I CurrentContext
   }
  }
}

proc keycallback { type subtype } {
global EventData CurrentContext Serial mwStateG bonk
global menu db titles return_menu 
global titletoggle foldertoggle sorttoggle
global folders addeps cursor nplist lastcache

binary scan $EventData II data Serial 

set nowplayinglist 7
set programdesc 8

if { $type == $TmkEvent::EVT_REMOTEEVENT && $subtype == 0 && $CurrentContext == $programdesc} {
      		if { $data == $::evrc(pause) && $folders } { pleasewait "Getting info";EnterFolder}

} else {
if { $type == $TmkEvent::EVT_REMOTEEVENT && $subtype == 0 && $CurrentContext == $nowplayinglist} {

      	if { $data == $::evrc(pause) && $folders } { 

			SendKey "select" 
		     	vwait CurrentContext 

      		        pleasewait "Getting info"
			EnterFolder
			}

	# ThumbUp / ThumbDown goes to the top / bottom of nowplaying:
	set totshows [llength $nplist]
      	if { $data == $::evrc(thumbsup) } { 
			set bonk 0
			while { $bonk < 2 } { SendKey "surfup" 	
						after 100
						# allow TCL to process the bonk event
						update
						}
			# we are at the top now
			set cursor 0 
		}
      	if { $data == $::evrc(thumbsdown) } { 
			set bonk 0
			while { $bonk < 2 } { SendKey "surfdown" 	
						after 100
						# allow TCL to process the bonk event
						update
						}
		}
# one day the following might speed things up:
# track keypresses up/down to work out which item is selected:

      	if { $data == $::evrc(up) } {       set cursor [max 0 [expr $cursor - 1] ] }
      	if { $data == $::evrc(surfup) } {   set cursor [max 0 [expr $cursor - 7] ] }
      	if { $data == $::evrc(down) } {     set cursor [min $totshows [expr $cursor + 1] ] }
      	if { $data == $::evrc(surfdown) } { set cursor [min $totshows [expr $cursor + 7] ] }

   		set title [lindex $nplist $cursor]
   		set title [lindex $title 0]
		# puts $title
      	if { $data == $::evrc(pause) } { 
		# gotoTivoCentral
		# makefolders $title
		# expandfolders $title
		# gotoNowPlaying
		}
	# Only look for "0" key to activate menu:
      if { $menu == 0 } { 
      		if { $data == $::evrc(0) } { 
			set menu 1
			sortmenu 
			return
			}
		}  

	# Look for 8 button (exit) in all menus
      if { $menu > 0  && $data == $::evrc(8) } { 
		# Quit when 8 pressed
		blankmenu
		dbclose $db
      		exit }

      if { $data == $::evrc(0) } { 
		# Show/remove OSD menu
		set menu [expr 1- $menu]
		if {$menu} { sortmenu } else { blankmenu }
		}
      	if { $data == $::evrc(replay) } {  

		# Sort by A-Z
		sortTitles $sorttoggle
		}
      	if { $data == $::evrc(catchup) } {  
		# Sort by Date
		gotoTivoCentral
		set menu $return_menu
		pleasewait "Sorting by Date"
		gettitles
		updatenowplaying 0
		gotoNowPlaying
		}
#
# Menu 1 - sort menu
#
      if { $menu == 1} {
	# We are already showing a menu and running:
	
      if { $data == $::evrc(1) } { 
		# Sort by A-Z
		sortTitles 0
		}

		# [removed menu item]
		# Sort by Z-A
		# sortTitles 1

      if { $data == $::evrc(2) } { 
		gotoTivoCentral
		set menu $return_menu
		pleasewait "Sorting by duration"
		gettitles

		set byduration [list]
		foreach item $titles {
			set fsid [lindex $item end]
			set seriesname [lindex $item 0]
			set oad  [lindex $item 1]
			set year [lindex $item 2]
			set duration [lindex $item 3]

			lappend byduration  "$duration {$seriesname} $oad $year $fsid"
			}

		set origtitles $titles
		set titles [lsort -decreasing $byduration] 
		
		updatenowplaying 1
		set titles $origtitles

		gotoNowPlaying
		}
      if { $data == $::evrc(3) } { 
		# Sort by Date
		gotoTivoCentral
		set menu $return_menu
		pleasewait "Sorting by Date"
		gettitles
		updatenowplaying 0
		gotoNowPlaying
		}
      if { $data == $::evrc(4) } { 
		# Add episodetitles
		gotoTivoCentral
		set menu $return_menu
		pleasewait "Adding episode titles"

		set addeps 1 
		doepisodetitles 1

# force a title search to update now playing:

		gettitles
		if {$sorttoggle == 0 } {
			set titles [lsort -decreasing $titles]
			} else {
			set titles [lsort -increasing $titles] }
		updatenowplaying 1
		set sorttoggle [expr 1 - $sorttoggle]
		gotoNowPlaying
		}
      if { $data == $::evrc(5) } { 
		# Remove episodetitles
		gotoTivoCentral
		set menu $return_menu
		pleasewait "Removing episode titles" 

		set addeps 0
		doepisodetitles 0

# force a title search to update now playing:

		gettitles
		if {$sorttoggle == 0 } {
			set titles [lsort -decreasing $titles]
			} else {
			set titles [lsort -increasing $titles] }
		updatenowplaying 1
		set sorttoggle [expr 1 - $sorttoggle]
		gotoNowPlaying
		}

      if { $data == $::evrc(6) } { set menu 2
				foldersmenu 
				return}

     } 
#
# Menu 2 - Folders Menu
#

if { $menu == 2 } {

      if { $data == $::evrc(1) && $folders} { 
		# Put into folders

	set foldertoggle [expr 1 - $foldertoggle]

		gotoTivoCentral
		set menu $return_menu
		pleasewait "Making Folders" 
		gettitles
		set titles [lsort -decreasing $titles]

		# for now we remove all old folders to prevent duplicates being created
		# should really check while making folders instead
		expandfolders "*"

		makefolders ""
		updatenowplaying 1
		gotoNowPlaying
		}

      if { $data == $::evrc(3) && $folders} { 
	set npffile "/var/hack/npf"
	if { [file exists $npffile] } {
		set npfhnd [open $npffile r]
		gets $npfhnd fldrinfo
		close $npfhnd

		gotoTivoCentral
		pleasewait "Making folders from tivoweb"
		foreach folder $fldrinfo {
			set foldertitle [lindex $folder 0]
			set recordings_list [lrange $folder 1 end]
			txtout "              $foldertitle " 2
			after 500
			merge $recordings_list $foldertitle 
			}
		gotoNowPlaying
		} 
	}

      if { $data == $::evrc(2) && $folders} { 
		gotoTivoCentral
		set menu $return_menu
		pleasewait "Hiding / expanding all Folders "
		expandfolders "*"
		gotoNowPlaying
		}
      if { $data == $::evrc(6) } { set menu 3
				advancedmenu
				return }
}
#
# Menu 3 - Advanced Menu
#

 if { $menu == 3 } {
      if { $data == $::evrc(1) } { 
		gotoTivoCentral
		set menu $return_menu
		pleasewait "Restoring deleted programmes"
		undeleteall
		gotoNowPlaying
		}
      if { $data == $::evrc(2) } { 
		gotoTivoCentral
		set menu $return_menu
		pleasewait "Converting suggestions to regular"
		sugg2regular

		# trash the cache since we've added more items
		set lastcache 0 

		gotoNowPlaying
		}
      if { $data == $::evrc(6) } { set menu 1
				sortmenu
				}
      } 

}
}

}
proc gettitles {} {
global db titles cacheTime lastcache errcount logchan folder_list nosuggs addeps nplist

# cache list - only get new titles every 60 mins (or whatever cacheTime is set to)
#              this can cut the processing time in half 
#

# setup cache of now-playing list

set now [clock seconds]
set age [expr $now - $lastcache]
set errcount 0

if { $age > [expr $cacheTime * 60] } {

# reset title-list and set time


# list of titles & details excluding recording in progress and folders
set titles []
# full copy of now playing list
set nplist []
# just the folders
set folder_list []
set lastcache $now
set i 0

# get all the titles

    ForeachMfsFile fsid name "tyDb" "/Recording/NowShowing" "" {
            # For each recording in the Now Showing list:
            RetryTransaction {
                	set rec [db $db openid $fsid]
                	set seltype [dbobj $rec get SelectionType]
			set state [dbobj $rec get State]

			set ok 1

			# Ignore suggestions if required
			if { $seltype == 6 && $nosuggs == 1 } { set ok 0 }


			if { $ok} {

			incr i
			# show a progress in the gui - update it every 5%
	     		if  { [expr $i % 10 ] == 0} {
				txtout "                       $i shows" 2
				}


                	set showing [dbobj $rec get Showing]
                	set program [dbobj $showing get Program]
                	set duration [dbobj $showing get -noerror Duration]
			set title [strim [dbobj $program get Title]]
			set year [dbobj $program get MovieYear] 

			# Only films have MovieYear set...
			if { $year == "" } { set year 0 }
			
			# -noerror option doesn't halt program if the field doesn't exist
			 catch { set airdate [dbobj $program get -noerror OriginalAirDate]  }

			# Films have no OriginalAirDate !
			if { $airdate == "" } { set airdate 0 }

			set inserted [catch {
				set series [dbobj $program get Series]
				set seriesname [strim [dbobj $series get Title]]
				}]

			if { $inserted != 0 } {	
					putlog "item has no series object: $title"
					# inserted shows do not have series objects at all,
					# so create our own based on title
					# strip everything after the ":" in a title

					set end [string first ":" $title]
					if { $end > 0 } { 
						set end [expr $end -1] 
						set seriesname [string range $title 0 $end]
						} else { 
						set seriesname $title 
						} 
					}
			
			lappend nplist  "{$seriesname} $airdate $year $duration $fsid"

			# Don't mess with a recording in progress
			if { $state != 3 } {  

				if { [string first " eps)" $title] == -1 } {
						lappend titles  "{$seriesname} $airdate $year $duration $fsid"
						} else {
						lappend folder_list  "{$title} $airdate $fsid"
						}

				}

			}
			}
		}

	puts $logchan "Getting list of shows"
	set timetaken [expr [clock seconds] - $now]
	printtime $timetaken 
	}  else { #puts $logchan "(cached)" }
}

proc doepisodetitles {addeps} {
global db lastcache errcount logchan titles addtitles

set addtitles $addeps
# Add or remove episode titles
gettitles
puts $logchan "Setting show titles"
set now [clock seconds]
set errcount 0

	foreach item $titles {
		set fsid [lindex $item end]
		set seriesname [lindex $item 0]
		set oad  [lindex $item 1]
		set year [lindex $item 2]

             	RetryTransaction {
                		set rec [db $db openid $fsid]
                		set showing [dbobj $rec get Showing]
                		set program [dbobj $showing get Program]
                		set description [strim [dbobj $program get Description]]
				set episode [strim [dbobj $program get EpisodeTitle]]

			if {$addeps == 0} {
					# Restore titles to series name
					set title $seriesname
					}
			if {$addeps == 1} {

					set title $seriesname
					# add episodetitle
					if {$episode != ""} { 
							set title "$seriesname: $episode"
							} else {
							set desc [string range $description 0 25]
							if {$desc !=""} {set title "$seriesname: $desc" }
							}
					if {$year > 0 } { set title "$seriesname ($year)"}
					}
			dbobj $program set Title $title
			}	
	    }
set timetaken [expr [clock seconds] - $now]
printtime $timetaken 
event send $TmkEvent::EVT_DATA_CHANGED $TmkDataChanged::RECORDINGS_ON_DISK 0
}


proc updatenowplaying {mode} {
global db titles errcount logchan CurrentContext fakedate

# update now playing with fake or real dates

# Optimised function... this is where we wait most of the time


puts $logchan "Sorting now playing list"

set now [clock seconds]
set errcount 0

set i 0
set totshows [llength $titles]

	foreach item $titles {

		# quit if the user goes to NowPlaying list
		# as it would slow processing down 100x 

		if { $CurrentContext != 7 } {
	     	incr i

		# show a progress percentage in the gui - update it every 5%
	        set percent [expr $i * 100  / $totshows ]
		showbar $percent

		set NewDate [expr $fakedate + $i]
		set fsid [lindex $item end]

             	RetryTransaction {
                	 	set rec [db $db openid $fsid]
				if {$mode == 0} {
					# reset to normal (sort by date)

                			set showing [dbobj $rec get Showing]
					set realdate [dbobj $showing get Date]
					set NewDate $realdate
					} 
				dbobj $rec set StartDate $NewDate

				# check if recording spans 2 days (at midnight)
				# if so, set enddate as next day, otherwise duration would show as 0.00

				set StartTime [dbobj $rec get StartTime]
				set StopTime [dbobj $rec get StopTime]
				set NewStopDate $NewDate

				if {$StartTime > $StopTime} {  incr NewStopDate }
				dbobj $rec set StopDate $NewStopDate
			}
		}
	}
set timetaken [expr [clock seconds] - $now]
printtime $timetaken
event send $TmkEvent::EVT_DATA_CHANGED $TmkDataChanged::RECORDINGS_ON_DISK 0
}

proc BackhaulEvent {type subtype } {
global EventData CurrentContext lastchan lasttitleupdate showprogress addtitles

# play/pause buttons
# puts "Backhaul event $subtype"
if { $subtype == 3} {
	binary scan $EventData SSIIIaa2cI  flag played chan datetime x y prefix highbits show

	if { $chan != $lastchan } { 

		# puts "channel change"

		set howlong [expr [clock seconds] - $lasttitleupdate]

		# ( update titles if we haven't done so within 30 minutes)
		if { $howlong > 1800 } {

			after 10000
			set showprogress 0
			doepisodetitles $addtitles
			set showprogress 1

			set lasttitleupdate [clock seconds]
			}
		}
	set lastchan $chan
	}

}


proc NPchange {type subtype } {
global CurrentContext addeps lastrecording

# Called when a new recording is added/finished

# gets subtype 1 and 6 when a new recording starts,
# but nothing when a recording finishes, or is deleted ?

# puts "NPchange event $subtype"

}

# MAIN ENTRY CODE 

set CurrentContext 0
set bonk 0

event register $TmkEvent::EVT_MW_STATUS   EventCallback
event register $TmkEvent::EVT_REMOTEEVENT keycallback
event register $TmkEvent::EVT_BACKHAUL     BackhaulEvent
event register $TmkEvent::EVT_DATA_CHANGED NPchange


set verboseSendKeyG 0
SendKey ping
vwait CurrentContext

set dbPoolSize [expr 100 * 1024]
set nplist [list]
set titles [list]

set nowplayinglist 7
set programdesc 8

set evnum 0
set context 0
set StillWaiting 1
set recordings ""
set lastfsid ""
set mwStateG ""
set lastrecording 0

set titletoggle 0
set foldertoggle 0
set sorttoggle 0

# ignore suggestions in sorting and folders
set nosuggs 1

# Automatically expand folders on entering
set auto 0

# Add all orphaned (non-series) shows into a Misc folder
set misc 0

# Handle shows when in folders
# set to 2 if you want shows moved to the bottom of the np list when in folders
# set to 1 if you want shows moved to suggestions when in folders
# set to 0 if you want them deleted (temporarily)

set nodelete 2

set addeps 0

set errcount 0
set menu 0
set lastcache 0
set showerrors false
set run true
set bg false
set cursor 0

# Enable folder functonality

set enable_folders 0
set folderchannel 1001
set logoId 0
set fldrinfo ""
set topoflist 361
setpri fifo 1

set db [dbopen]


# speed up (solaise)
#
#  Copied from TivoWeb - speeds things up - havent seen any
#  problems - What this means is that the Transaction will Holdoff
#  without returning an error - i.e no retry txn is necessary
#

catch {EnableTransactionHoldoff true}

# dont show GUI progress in scripts:
set showprogress 0

proc usage {} {

puts stdout "Usage:"
puts stdout " -showerrors:  print minor errors to console"
puts stdout " -addtitles: add episode titles to now-playing list"
puts stdout " -addeps: keep adding episode titles to now-playing list"
puts stdout " -deltitles: remove episode titles from now-playing list"

puts stdout " -reset:"
puts stdout " -sortdate: Sort by Date (normal tivo view)"
puts stdout " -sortaz: Sort alphabetically"
puts stdout " -sortza: Sort reverse alphabetically"

puts stdout " -folders: show folder options in the gui"
puts stdout " -npf: use info from LJ's tivoweb module to make folders"

puts stdout " -makefolders: Put shows into folders by series"
puts stdout " -delfolders: Remove folders, and return to normal view"
puts stdout " -undeleteall: restore all deleted shows (as suggestions)"
puts stdout " -sugg2regular: convert all suggestions into normal recordings"

puts stdout " -noauto:  do not automatically expand folders on entry"
puts stdout " -clean: temporarily deletes shows instead of using suggestions"

puts stdout " -nogui:"
puts stdout " -quit: exit script immediately after doing above actions"
puts stdout " -help: show this page "
}


for {set i 0} {$i < [llength $argv]} {incr i} {

  set arg [lindex $argv $i]

  switch -- $arg {
  -showerrors { set showerrors true}
  -addtitles { doepisodetitles 1
		set addeps 1 }
  -deltitles { doepisodetitles 0}
  -addeps { set addeps 1 }
  -setupchannel { setupchannel }

  -reset -
  -sortdate {gettitles; updatenowplaying 0}
  -sortaz { gettitles
	set titles [lsort -decreasing $titles]
	updatenowplaying 1}
  -sortza { gettitles
	set titles [lsort -increasing $titles]
	updatenowplaying 1}
  -nogui -
  -quit {set run false }
  -h -
  -help { usage
	 set run false }
  -wait {incr i; set exit_delay [lindex $argv $i]}

  -debug -
  -run { set bg true }

  -makefolders { gettitles
	set titles [lsort -decreasing $titles]
	makefolders ""
	updatenowplaying 1}

  -misc { set misc 1}
  -delfolders {expandfolders "*"}
  -undeleteall {undeleteall}
  -sugg2regular {sugg2regular}

  -noauto { set auto 0 }
  -folders { set folders 1 }
  -clean {set nodelete 0}
  }
}

# If running in foreground without -run option, then fork to background process
if { $bg == "false" } {
	eval exec {[info nameofexecutable] [info script]} $argv {-run > /var/log/sortnp.log &} 
	exit
	}

puts "Started"
puts "Press 0 on tivo remote in now-playing to show GUI"


if ($folders) {
	getLogo 
	set npffile "/var/hack/npf"

	if { [file exists $npffile] } {
		set npfhnd [open $npffile r]
		gets $npfhnd fldrinfo
		close $npfhnd
		foreach folder $fldrinfo {
			set foldertitle [lindex $folder 0]
			set recordings_list [lrange $folder 1 end]
			#  merge $recordings_list $foldertitle 
			}
		} 
	}


set showerrors true
set lastcache 0

# Not in a script, so show progress now
set showprogress 1

# Screen numbers
set nowplaying 7
set progdesc 8
set livetv 6



# speeds up processing - from tivoweb
catch {EnableTransactionHoldoff true}


while {$run} { 

if {$CurrentContext == $nowplaying && $menu} {sortmenu}
if {$CurrentContext == $progdesc && $folders} {
 	if {$menu > 0} { # playmenu }
	if {$auto == 1} { EnterFolder}
	}
vwait CurrentContext 
# puts $CurrentContext

}
