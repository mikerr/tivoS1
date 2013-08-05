#!/tvbin/tivosh
######################################################################
#  suggs.tcl 1.04
#
#  The new suggestion engine!
#
#  Records suggestions based on thumbs data 
#
# mikerr@tivocommunity                www.tivocentral.co.uk
######################################################################
# 1.04 
# 1.02 Only scans the schedule once per day, uses cache otherwise
#      More error checking  
#      
# 1.01 Uses tivo's database of genre thumbs
#      bug fix for duplicate recordings
#      delays added to ease cpu load
# 1.00 Prioritises recordings based on thumbs across all channels
#       (instead of FIFO when scanning channels)
#	internal predicted-thumbs based on genres in your now-playing list


#  minThumbs is the threshold for setting a suggestion, 
#
# -128 = 1 thumb down
# 0 = neutral
# 128 = 1 thumb up
# 256 = 2 thumbs up
# 512 = 3 thumbs up
# predicted interest is anywhere from 1 - 200

set minThumbs 0


# Set process priority  - stops picture stuttering!
setpri fifo 1

proc strim {str} {  return [string trim $str "\{\}"]  }
proc bgerror errmessage {
global debug
putlog "error: $errmessage"
}

proc putlog { log } {
global logchan
	set format "%A %H:%M:%S"
	puts $logchan "[clock format [clock seconds] -format $format]: $log"
	flush $logchan
	}

# lcount - return the number of matching elements in a list
proc lcount { list match } {
set count 0
	set list [lsort -increasing $list]
 	set index [lsearch -exact $list $match]
	if { $index == -1 } { return 0 }

	while { 1 } {
		incr count 
		set next [lindex $list [expr $index + $count]] 
		if { $next != $match } {return $count}
		}
}
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
          after 900
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
proc get_fsidbyprefix {dirname prefix} {
	if { [catch {mfs scan $dirname -start $prefix -count 1} batch] } {
		global errorCode errorInfo
		if { $errorCode == "errNmNameNotFound" } {
			return
		} else {
			error $batch $errorInfo $errorCode
		}
	}
	set item [lindex $batch 0]
	set name [lindex $item 1]
	if { [PrefixMatches $prefix $name] } {
		return $item
	} else {
		return ""
	}

}

proc defaultval {val1 val2} {
	if { $val2 != "" } { 
		return $val2
	} else { 
		return $val1 }
}

# load a list from a file, one item per line
proc load_list {filename} {
	if {![file exists $filename]} {
		set openfile [open $filename w]
		close $openfile
	}
	set openfile [open $filename r]
	set ret [read $openfile]
	close $openfile
	return $ret
}

# Generate a list of all genre codes and names

proc GetGenres { } {
    global db

    set keys ""
    RetryTransaction {
        set dataset [db $db open /DataSet/GenreVersion]
        set genres [dbobj $dataset gettarget Data]
    }
    set incrsize 50
    foreach genrefsid $genres {
        regsub {/-1$} $genrefsid {} fsid
        set done 0
        set idx 0
        while {!$done} {
            RetryTransaction {
                set genre [db $db openid $fsid]
                set subgenres [dbobj $genre gettarget Child]
                set numsubs [llength $subgenres]
                if {$subgenres != ""} {
                    set maxcount [expr ($numsubs > $idx + $incrsize) ? ($idx + $incrsize) : $numsubs]
                    for {set i $idx} {$i < $maxcount} {incr i} {
                        set subgenre [dbobj $genre get Child $i]
                        set index [dbobj $subgenre get Value]
                        if {$index != 0 && [lsearch $keys $index] == -1} {
                            set vlabel [strim [dbobj $subgenre get Name]]
                            lappend keys $index
                            lappend vals $vlabel
                        }
                    }
                    if {$numsubs == $maxcount} {
                        set done 1
                    } else {
                        incr idx $incrsize
                    }
                } else {
                    set done 1
                }
            }
        }
    }
    return [list $keys $vals]
}

# extract number of thumbs / confidence / predicted flags from thumbdata
#
proc ReadThumbData { thumbs required } {
	regexp {.*(.)(..)(.)(..)(..)} "00000000[format %x $thumbs]" \
		dummy version unused flags nthumbs hexconfidence

			scan $nthumbs %x numthumbs
			if {$numthumbs > 3} {
				incr numthumbs -256
			}
			scan $hexconfidence %x confidence
			return [expr $numthumbs * 128]
}

# Thumbs stored as vectors, function to convert to a thumb value -3 -> +3
proc decode_vector {vector} {

	set largesti 0
	set largestn 0
	set first 1
	set count 0

	foreach val $vector {
		if { $val > $largestn } {
			set first 0
			set largestn $val
			set largesti $count
		}
		incr count
	}
	if {$first == 1} {
		return 0
	} else {
		return [expr $largesti - 3]
	}
}

# Get the thumbs given a genre number
proc genreThumbs { genre } {
global db
			 set path "/Preference/a/14/$genre"

				if { [catch {set pref [db $db open $path]}] } { return 0 }
			 	set vector [dbobj $pref get Vector]

			 	return [decode_vector $vector]
}

# convert genre number to genre text name ( 39 -> Fantasy )

proc findgenrename { genrenum } {
global genrenums genrevals
 set genreindex [lsearch $genrenums $genrenum]
 return [lindex $genrevals $genreindex]
}

# convert genre text name to genre number  ( Fantasy -> 39 )

proc findgenrenum { genrename } {
global genrenums genrevals
 set genreindex [lsearch $genrevals $genrename]
 return [lindex $genrenums $genreindex]
}

# read the todo list

proc refresh-todolist { } {
global db todolist
set todolist []
ForeachMfsFile fsid name type "/Recording/Active" "" {

	if {$type == "tyDb"}  {
		if { [regexp {^4} $name] || [regexp {^3} $name] } { 
			# 4 is a todo entry, 3 is a recording in progress
			after 50
			RetryTransaction {
				set obj [db $db openid $fsid]
				set selectionType [dbobj $obj get SelectionType]

				regexp {([0-9]*)/(.*)} [dbobj $obj gettarget Showing] junk part1 part2

				set subObj [db $db openid $part1 $part2]

				set programId [dbobj $subObj get Program]
				set title [dbobj $programId get Title]

				set date [dbobj $subObj get Date]
				set duration [dbobj $subObj get Duration]

				set starttime [dbobj $subObj get Time] 
				set endtime [expr $starttime + $duration]

				# add hard padding if set

				incr starttime -[defaultval 0 [dbobj $obj get StartPadding]]
      				incr endtime [defaultval 0 [dbobj $obj get EndPadding]]

				lappend todolist "{$title} $date $starttime $endtime"
				}
			}
		}
}

}


proc get_freespace { required } {

# add up the free space (i.e. size of deleted programmes + suggestions)

global db historylist 

set free_space 0
set $required [expr $required * 1000 * 1000]  
ForeachMfsFile fsid name type "/Recording/DiskUsed/10" "" {
   after 50
   RetryTransaction {
    set recording            [db $db openid $fsid]
    set state                [dbobj $recording get State]
    set seltype        [dbobj $recording get SelectionType]

    # add up free space
    # free space =  a deleted programme or a suggestion

    if { $state == 5 || $seltype == 6} { incr free_space  [dbobj $recording get StreamFileSize] }

    if {$free_space > $required } { return 1 }
    }
}
if {$free_space < $required } { return 0 }
}

proc get_nowplaying { } {
global db historylist 

# /Recording/NowShowing only has current non-deleted items in it 
# so quicker to scan
# (This is /Recording/NowPlaying on US tivos)

ForeachMfsFile fsid name type "/Recording/NowShowing" "" {
   after 50
   RetryTransaction {
    set recording            [db $db openid $fsid]
    # set state                [dbobj $recording get State]
    # set seltype        [dbobj $recording get SelectionType]

    set startdate [dbobj $recording get StartDate]
    set showing [dbobj $recording get Showing]
    set program [dbobj $showing get Program]
    set title [dbobj $program get Title]
    set episode [strim [dbobj $program get EpisodeTitle]]

    set inserted [catch {
    		set series [dbobj $program get Series]
		set seriesname [dbobj $series get Title]
			}]

    if { $inserted != 0 || $episode==""} {
    		# item has no series or episode data, so use normal title
        	set seriesname $title
    		}

    lappend historylist "$startdate $fsid {$seriesname}"
    }
  }

}

# main code

set db [dbopen]
# EnableTransactionHoldoff true

set bg false
set debug false
set runonce false
set daysahead 0
set threshold 0
set episodeDays 1

set logchan "stdout"

for {set i 0} {$i < [llength $argv]} {incr i} {

  set arg [lindex $argv $i]

  switch -- $arg {
  -sugqual -
  -quality {incr i; set recquality [lindex $argv $i]}
  -days -
  -daysahead {incr i; set daysahead [lindex $argv $i]}
  -thumbs -
  -threshold {incr i; set minThumbs [lindex $argv $i]}
  -daysback -
  -epdays -
  -episodedays {incr i; set episodeDays [lindex $argv $i]}
  -console { set bg true }
  -v -
  -debug { set debug true ; set runonce true ; set bg true 
	   set logchan "stdout"
	   }
  -runonce { set runonce true }

  -todo { set debug true; set runonce true; set bg true; 

	refresh-todolist
	
	foreach todo $todolist {
				set tname [strim [lindex $todo 0]]
				set tdate [lindex $todo 1]
				set tstarttime [lindex $todo 2]
				set tstoptime [lindex $todo 3]

				set tstarttime [clock format $tstarttime -format "%H:%M"] 
				set tstoptime [clock format $tstoptime -format "%H:%M"] 
				set day [clock format [expr $tdate * 86400] -format "%A %dth"]
				puts "$day $tstarttime - $tstoptime $tname"
				}
	exit
	}
  }
}


# If running in foreground without -run option, then fork to background process
if { $bg == "false" } {
	eval exec {[info nameofexecutable] [info script]} $argv {-console > /var/log/suggs.log &} 
	exit
	}


##########################
RetryTransaction {
set setup [db $db open /Setup]
set recquality [defaultval 100 [dbobj $setup get RecordQuality]]
}


set logchan "stdout"

# Run through all channels, and store possible suggestions in a list
#
proc process_schedule { date } {
global db debug
global channelsReceived today time
global allprogs minThumbs
global blockgenres blocklist historylist
global episodeDays

# scan all channels 

foreach thischannel $channelsReceived {

	set stationfsid [lindex $thischannel 0 ]
	set callsign [lindex $thischannel 1]
	if {$debug } { puts -nonewline "$callsign "; flush stdout }

# Get a list of programmes for this channel
after 100

RetryTransaction {
        set schedlist [get_fsidbyprefix "/Schedule" "$stationfsid:$date:"]
	if { [ catch { set stationday [db $db openid [lindex $schedlist 0]] } ] } { 
			break }
	set showings [dbobj $stationday gettarget Showing]
	}

	# Do them in batches of 10 (tivo doesn't like long transactions)

	for {set x 0} {$x < [llength $showings]} {incr x 10} {
		after 10

		# do 10 programmes in each transaction
		RetryTransaction {
			foreach showingfsid [lrange $showings $x [expr $x+9]] {
				regexp {([0-9]*)/(.*)} $showingfsid junk showingobjid subobjid
				set showing [db $db openidconstruction $showingobjid $subobjid]
		set recordThis 0
        	set starttime [dbobj $showing get Time]

		# don't look at programmes already started or finished today
        	if { $starttime > $time  || $date > $today }  {
          		set program [dbobj $showing get Program]
          		set tmsid [dbobj $program get TmsId]
          		set title [dbobj $program get Title]
          		set seriesid [dbobj $program get Series]

			if { !$minThumbs } {  set recordThis 1 }
	
	  		set thumbValue ""
	  		catch { set thumbValue [dbobj $seriesid get ThumbData ] }
	  		if { $thumbValue != "" } {  
				set thumbData [ReadThumbData $thumbValue Void] 

	 			if {$thumbData >= $minThumbs } { 
					if {$debug} { # puts " SUGGEST $title ($thumbData)"}
					set recordThis 1
					} else {
					set recordThis 0
					}
				} else {
	  			set thumbData 0
	  			set thumbValue 0
				}

			# Find reasons not to record....

			# Check if its genre is blocked (e.g. football)

			if { $recordThis } {
          			set genres [dbobj $program get Genre]
				foreach item $blockgenres {
					if  { [lsearch $genres $item] != -1 } {
					        # putlog "$title - cancelled ([lindex $genrevals [lsearch $genrenums $item]] genre blocklist)"
						set recordThis 0
					    }
					}
				if {[lsearch [string tolower $blocklist] [string tolower $title]] >= 0} {
					putlog "$title - cancelled (title blocklist)"
					set recordThis 0
					}
				}
			# Check we haven't recorded this already sometime 

			if { $recordThis } {
					# Don't record the same series twice in one day
					# So won't record 5 episodes of simpsons each day!

					# format:
					# startdate fsid title

					foreach oldrec $historylist {

						set oldtitle [lindex $oldrec 2]
						set oldstartdate [lindex $oldrec 0]

						# episodeDays = number of days before recording another episode
						if { $title == $oldtitle  && $oldstartdate > [expr $today - $episodeDays] } { 
							putlog "Already recorded '$title' in the past $episodeDays days"
							set recordThis 0 }
						}
					}

			if { $recordThis } {

				# list of all possible shows, without regard for clashes
				# we'll try to actually set recordings later
	
				set thumbcount 0
				set genrecount 0

				# add up genre thumbs for this programme
				foreach genre $genres {
					incr thumbcount [genreThumbs $genre]
					}
				set ratingtext [format "%03d" [expr 100 + $thumbcount] ]
				set thumbtext [format "%03d" $thumbData ]

				# don't record negative genres
				if { $thumbcount >= 0 } {
     					set stoptime [expr $starttime + [dbobj $showing get Duration]]
					lappend allprogs "$thumbtext $ratingtext {$title} $showingobjid $subobjid $callsign $date $starttime $stoptime"
					}
				}
		# end starttime
		}
	  # end showing loop
      	  } 
	}
     }
   }
}
##########################################
# main entry

set pidfile  "/var/log/suggspid.[pid]"
set suggschannels "/var/hack/suggs.channels"
set suggsprogs "/var/hack/suggs.progs"

set blocklist [load_list "/var/hack/blocklist.txt"]
set blockgenretext [load_list "/var/hack/blockgenres.txt"]

set genres [GetGenres]
set genrenums [lindex $genres 0]
set genrevals [lindex $genres 1]

set blockgenres {}
# Convert genre names into numbers:
# blockgenretext a list of genre names, we want a list of genre numbers
foreach genre $blockgenretext {
	set genreindex [lsearch $genrevals $genre]
	if {$genreindex == -1} {
		putlog "Invalid genre: $genre" 
		} else {
		putlog "Blocking genre: $genre" 
		# the number:
	 	lappend blockgenres [lindex $genrenums $genreindex]
		}
}

# kill any other running version
catch {eval file delete [glob /var/log/suggspid.* ]}

# kill historyfile too, as file format has changed...
catch {eval file delete /var/hack/suggs.history }
catch {eval file delete /var/hack/suggs.progs }

set handle [open $pidfile w] ; close $handle

  set date [expr [clock seconds]/86400]
  set time [expr [clock seconds]%86400]

# Read channel list from disk:

	set channelage 1
	if { [file exists $suggschannels] } {
		set channelage  [expr $date - [expr [file mtime $suggschannels] / 86400]]
		}
	# Only update channel list once per day
	if { $channelage == 0 } {
		putlog "reading channel list from disk (cached)"
		set handle [open $suggschannels r]
		gets $handle channelsReceived
		close $handle
		} else {
		putlog "reading channel list from mfs"
# get a list of all channels

   RetryTransaction {
      set setup [db $db open /Setup]
      set sources [dbobj $setup get Source]
      set channels ""
      foreach source $sources {
         append channels [dbobj $source gettarget Channel] " "
      }
      set channelcount [llength $channels]
   }
   set increment 30

   for {set j 0} {$j < $channelcount} {incr j $increment} {
      set channels2 [lrange $channels $j [expr $j + $increment - 1]]
      RetryTransaction {
         foreach channel $channels2 {
            regexp {([0-9]*)/(.*)} $channel junk id subid
            set channelobj [db $db openidconstruction $id $subid]
            set record [defaultval 1 [dbobj $channelobj get Record]]
            set favorite [defaultval 0 [dbobj $channelobj get Favorite]]
            if { $record > 0 } {
               set num [dbobj $channelobj get Number]
               set num [expr $num & 0xFFFF]
               set station [dbobj $channelobj get Station]
               set stationfsid [dbobj $station fsid]
               set callsign [dbobj $station get CallSign]

	 	lappend channelsReceived "$stationfsid $callsign"
            }
         }
      }
      }

# Now write channel list to disk:

		set handle [open $suggschannels w]
		puts $handle $channelsReceived
		close $handle
}
# MAIN LOOP STARTS HERE

while { 1 } {

if { [catch {
set date [expr [clock seconds]/86400]
set time [expr [clock seconds]%86400]

set now $time
set today $date


set recordings 0
set historylist []
set allprogs []
set todolist []

# Only bother setting suggestions if we have at least an hour (2GB) free:
putlog "Checking for free space"
if {[get_freespace 2] } {
	putlog "Scanning todo list"
	refresh-todolist 
        putlog "Scanning now playing"
	get_nowplaying 

	set fileage 1
	if { [file exists $suggsprogs] } {
		set fileage  [expr $date - [expr [file mtime $suggsprogs] / 86400]]
		}
	# Only update once per day
	if { $fileage == 0 } {
		putlog "Reading schedule list from disk (cached)"
		set handle [open $suggsprogs r]
		gets $handle allprogs
		close $handle
		} else {
			putlog "Processing schedule"
			for { set today $date } { [expr $date - $today] <= $daysahead } { incr date } {
				process_schedule $date
				}
			}
	} else { 
		putlog "drive has less than 2GB free, no space for suggestions" 
		}


# Ok, got a filtered list of current programmes

# sort by first field (thumbData), then second field (genre-rating)

set allprogs [lsort -decreasing $allprogs]

# Try to record highest thumbed/rated programs first

foreach prog $allprogs {
			set recordThis 1
			set thumbData [lindex $prog 0]
			set genreThumb [lindex $prog 1]
			set title [lindex $prog 2]

			set showingobjid [lindex $prog 3]
			set subobjid [lindex $prog 4]
			set callsign [lindex $prog 5]

        		set date [lindex $prog 6]
        		set starttime [lindex $prog 7]
     			set stoptime [lindex $prog 8]

			# Ignore programmes already started
			if { $starttime < $now } { set recordThis 0 }

			# check there is time to record it 
			# (no clashes in the todo list)

			if { $recordThis } {

				foreach todo $todolist {

						set tname [lindex $todo 0]
						set tdate [lindex $todo 1]

						# don't schedule more than one episode of the same program in each run

						if { $tname == $title }  {  
								# putlog " cancelled $title (duplicate program todo entry)"
								set recordThis 0 }
						if {$date == $tdate} {
							set tstarttime [lindex $todo 2]
							set tstoptime [lindex $todo 3]

							if { $starttime >= $tstarttime  &&  $starttime <= $tstoptime }  {  set recordThis 0 }
							if { $starttime < $tstarttime  &&  $stoptime > $tstarttime }  {  set recordThis 0 }
							if { $recordThis == 0 } {
								if {$debug} { # putlog "New recording $title *CONFLICT* with $tname"}
								break
								}
							}
						}

			# Ok, lets set it to record
			if { $recordThis } {

				putlog "SCHEDULE $title ($thumbData / $genreThumb) on $callsign at [clock format $starttime -format "%H:%M"] "

				# after 1000
   				RetryTransaction {
					set showing [db $db openidconstruction $showingobjid $subobjid]

 	 				if { [catch {set recording [db $db create Recording] } ] } {
						break }
         				if { [catch {set newshowing [db $db createsub Showing $recording]} ] } {
						break }
         				if { [catch { dbobj $newshowing copyfrom $showing } ] } {
						break }
         				dbobj $newshowing set Reason 2
         				dbobj $recording set Showing $newshowing
			
       					dbobj $recording set BitRate 0
       					dbobj $recording set ExpirationDate $today 
       					dbobj $recording set ExpirationTime $stoptime

      					# dbobj $recording set Score $thumbValue 
      					dbobj $recording set Score 0

					dbobj $recording set RecordQuality $recquality 

      					dbobj $recording set SelectionType 6
      					dbobj $recording set State 6

					lappend todolist "{$title} $date $starttime $stoptime"
					incr recordings

   					} 
					# end recordThis
				}

	} 
}
putlog "Clearing lists"

# clear lists to free up memory
set historylist []
set todolist []
set allprogs []

# putlog "Flushing to disk"
# set handle [open $suggsprogs w]
# puts $handle $allprogs
# close $handle


# end of catch code in main loop
} result ]  } { 
	putlog "Error... $errorInfo"
	putlog "... retrying later"
	after [expr 60 * 1000]
	}


if { $runonce } { exit }



# loop around after 30 mins

putlog "Waiting for 30 mins" 

for { set delay 0 } { $delay < 30 } { incr delay } {
after [expr 60 * 1000]
if { ![file exists $pidfile]  } { 
	# another copy running..exit
	putlog "exiting"
	exit }
}

# loop around again
}
