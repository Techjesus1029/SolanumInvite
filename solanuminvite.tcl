# invite_request.tcl
# Eggdrop script to generate Solanum auth blocks based on account age.

namespace eval ::InviteSystem {
    # ------------------ CONFIGURATION ------------------
    variable auth_conf_path "/path/to/solanum/etc/auth.conf"
    variable db_file "data/invites.db"
    
    # Notice target (where to send the generated password securely)
    variable reply_via "NOTICE" ;# Can be NOTICE or PRIVMSG
    # ---------------------------------------------------

    variable quotas
    if {![info exists quotas]} { array set quotas {} }

    bind pub - !requestinvite [namespace current]::cmd_requestinvite
    bind join - * [namespace current]::init_db

    proc init_db {args} {
        variable db_file
        if {![file exists $db_file]} {
            set f [open $db_file w]
            puts $f "# Invite tracking database"
            close $f
        }
        load_quotas
    }

    proc load_quotas {} {
        variable db_file
        variable quotas
        array unset quotas
        if {[file exists $db_file]} {
            set f [open $db_file r]
            while {[gets $f line] >= 0} {
                if {[string match "#*" $line] || $line eq ""} { continue }
                set quotas([lindex $line 0]) [lrange $line 1 end]
            }
            close $f
        }
    }

    proc save_quotas {} {
        variable db_file
        variable quotas
        set f [open $db_file w]
        puts $f "# Account monthly_reset_timestamp remaining_invites"
        foreach acc [array names quotas] {
            puts $f "$acc $quotas($acc)"
        }
        close $f
    }

    # Helper to generate a random password
    proc gen_password {length} {
        set chars "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        set pass ""
        while {[string length $pass] < $length} {
            set idx [expr {int(rand() * [string length $chars])}]
            append pass [string index $chars $idx]
        }
        return $pass
    }

    proc cmd_requestinvite {nick uhost hand chan arg} {
        variable quotas
        variable auth_conf_path
        variable reply_via

        set target_user [string trim [lindex $arg 0]]
        if {$target_user eq ""} {
            putquick "NOTICE $nick :Usage: !requestinvite <username>"
            return 0
        }

        # Clean username to prevent injection characters
        regsub -all {[^a-zA-Z0-9_\-\[\]\{\}^`|]} $target_user "" target_user

        # NOTE: Eggdrop needs to check the requester's account age.
        # Since IRC is asynchronous, an enterprise-grade script would issue a 
        # 'PRIVMSG NickServ :INFO $nick' and catch the reply. 
        # For this logic block, we assume your script has validated the requester's account name ($account)
        # and registration age in days ($reg_days).
        
        # --- PLACEHOLDER FOR DEMONSTRATION (Replace with actual tracking logic) ---
        set requester_account $nick
        set reg_days 45 ;# Example: simulated 45 days registered
        # --------------------------------------------------------------------------

        # Determine structural tier max allowance
        if {$reg_days >= 30 && $reg_days < 60} {
            set max_invites 3
        } elseif {$reg_days >= 60} {
            set max_invites 5
        } else {
            putquick "NOTICE $nick :Your account must be registered at least 30 days to request invites."
            return 0
        }

        set now [unixtime]
        set monthly_span 2592000 ;# 30 days in seconds

        # Check existing quota
        if {[info exists quotas($requester_account)]} {
            set reset_time [lindex $quotas($requester_account) 0]
            set remaining [lindex $quotas($requester_account) 1]

            if {$now > $reset_time} {
                # Monthly reset window hit
                set remaining $max_invites
                set reset_time [expr {$now + $monthly_span}]
            }
        } else {
            set remaining $max_invites
            set reset_time [expr {$now + $monthly_span}]
        }

        if {$remaining <= 0} {
            set time_left [expr {$reset_time - $now}]
            set days_left [expr {$time_left / 86400}]
            putquick "NOTICE $nick :You have exhausted your monthly invite limit. Resets in $days_left days."
            return 0
        }

        # Generate structural assets
        set password [gen_password 12]
        
        # Open and append to Solanum auth.conf
        if {[catch {
            set fileId [open $auth_conf_path "a"]
            puts $fileId "/* Invite requested by $nick ($requester_account) on [clock format $now -format {%Y-%m-%d %H:%M:%S}] */"
            puts $fileId "auth {"
            puts $fileId "    user = \"${target_user}@*\";"
            puts $fileId "    class = \"users\";"
            puts $fileId "    password = \"$password\";"
            puts $fileId "};"
            puts $fileId ""
            close $fileId
        } err]} {
            putlog "Error writing to auth.conf: $err"
            putquick "NOTICE $nick :An internal server error occurred while writing configuration."
            return 0
        }

        # Deduct quota and save
        incr remaining -1
        set quotas($requester_account) [list $reset_time $remaining]
        save_quotas()

        # Rehash the IRCd so it loads the new block instantly via Oper credentials if automated,
        # otherwise it waits for the next manual rehash.
        
        # Deliver credential set to the user
        putquick "$reply_via $nick :Invite created successfully for target user: $target_user"
        putquick "$reply_via $nick :Password: $password"
        putquick "$reply_via $nick :Remaining invites for this month: $remaining"
    }
}

::InviteSystem::init_db
putlog "Solanum Invite Request Script Loaded Successfully."
