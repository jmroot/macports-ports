#!/usr/bin/env port-tclsh

# Figure out which ports link with a given lib

set libname libMagick

set archive_site https://packages.macports.org
set archive_site_private https://packages-private.macports.org

while {[llength $argv] > 0} {
    if {[lindex $argv 0] eq "--portlist"} {
        if {[llength $argv] > 1} {
            set portlist [lindex $argv 1]
            set argv [lrange $argv 2 end]
        } else {
            puts stderr "no portlist given"
            exit 1
        }
    } elseif {[lindex $argv 0] eq "--dbdir"} {
        if {[llength $argv] > 1} {
            set dbdir [file normalize [lindex $argv 1]]
            set argv [lrange $argv 2 end]
        } else {
            puts stderr "no dbdir given"
            exit 1
        }
    }
}
if {![info exists portlist]} {
    error "portlist is required"
}
if {![info exists dbdir]} {
    set dbdir [pwd]
}

package require macports
mportinit

proc handle_portlist {} {
    global portlist all_ports
    foreach p $portlist {
        lassign [mportlookup $p] portname portinfo
        lappend all_ports $portname [dict get $portinfo porturl] [dict get $portinfo portdir]
    }
}

handle_portlist

file mkdir ${dbdir}/extract

set machista_handle [machista::create_handle]
if {$machista_handle eq "NULL"} {
    error "Error creating libmachista handle"
}

proc links_with {filepath query_libname} {
    global machista_handle
    set ret 0

    set resultlist [machista::parse_file $machista_handle $filepath]
    lassign $resultlist returncode result
    if {$returncode != $machista::SUCCESS} {
        if {$returncode == $machista::EMAGIC} {
            # not a Mach-O file
            # ignore silently, these are only static libs anyway
        } else {
            ui_debug "Error parsing file ${filepath}: [machista::strerror $returncode]"
        }
        return 0
    }
    set architecture [$result cget -mt_archs]
    while {$architecture ne "NULL"} {
        set loadcommand [$architecture cget -mat_loadcmds]
        while {$loadcommand ne "NULL"} {
            set libname [file tail [$loadcommand cget -mlt_install_name]]
            if {[string match ${query_libname}*.dylib $libname]} {
                set ret 1
                break
            }
            set loadcommand [$loadcommand cget -next]
        }
        if {$ret == 1} {
            break
        }
        set architecture [$architecture cget -next]
    }

    return $ret
}

proc process_ports {} {
    global all_ports dbdir archive_site archive_site_private maxports libname
    set output [dict create]
    foreach {name porturl portdir} $all_ports {

        if {![catch {mportopen $porturl [dict create subport $name] ""} result]} {
            set workername [ditem_key $result workername]
            set archive_name [$workername eval {portfetch::percent_encode [get_portimage_name]}]
            mportclose $result

            set archive_type [file extension $archive_name]
            file delete -force ${dbdir}/check${archive_type}
            puts "fetching ${archive_name}"
            if {[catch {curl fetch ${archive_site}/${name}/${archive_name} ${dbdir}/check${archive_type}} result]} {
                if {[catch {curl fetch ${archive_site_private}/${name}/${archive_name} ${dbdir}/check${archive_type}} result]} {
                    puts stderr "failed to fetch ${archive_name}: $result"
                    dict lappend output $portdir unknown $name
                    continue
                }
            }

            file delete -force ${dbdir}/extract
            file mkdir ${dbdir}/extract
            if {[catch {system -W ${dbdir} "tar -xj -C extract -f check${archive_type}"} result]} {
                puts stderr $::errorInfo
                puts stderr "failed to extract check${archive_type} for ${name}: $result"
                dict lappend output $portdir unknown $name
                continue
            }
            foreach f {+COMMENT +CONTENTS +DESC +PORTFILE +STATE} {
                file delete -force ${dbdir}/extract/${f}
            }

            set any_matches 0
            fs-traverse -depth f [list ${dbdir}/extract] {
                if {[fileIsBinary $f] && [links_with $f $libname]} {
                    set any_matches 1
                    break
                }
            }
            if {$any_matches} {
                dict lappend output $portdir yes $name
            }
        } else {
            dict lappend output $portdir unknown $name
        }
    }
    return $output
}

set output [process_ports]
machista::destroy_handle $machista_handle

set all_portfiles [list]
set all_yesports [list]
set all_uports [list]

puts "\nPortfiles with at least one subport that may link with ${libname}:"
dict for {portdir sub} $output {
    lappend all_portfiles ${portdir}/Portfile
    puts ${portdir}/Portfile
    if {[dict exists $sub yes]} {
        foreach yesport [dict get $sub yes] {
            lappend all_yesports $yesport
            puts "  $yesport"
        }
    }
    if {[dict exists $sub unknown]} {
        foreach uport [dict get $sub unknown] {
            lappend all_uports $uport
            puts "  $uport (unconfirmed)"
        }
    }
}

if {[llength $all_portfiles] > 0} {
    puts "\nAll Portfiles of interest:"
    foreach p [lsort -dictionary $all_portfiles] {
        puts $p
    }
}
if {[llength $all_yesports] > 0} {
    puts "\nAll subports known to link:"
    foreach p [lsort -dictionary $all_yesports] {
        puts $p
    }
}
if {[llength $all_uports] > 0} {
    puts "\nAll subports of unknown linkage:"
    foreach p [lsort -dictionary $all_uports] {
        puts $p
    }
}
