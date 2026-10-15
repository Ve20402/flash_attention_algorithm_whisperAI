# Run in Vivado Tcl Console with an existing FA UVM project open.
# Preserves regression evidence without creating or rebuilding a project.
namespace eval ::fa {}
set ::fa::script_dir [file dirname [file normalize [info script]]]
set ::fa::uvm_dir [file dirname $::fa::script_dir]
set ::fa::root_dir [file dirname $::fa::uvm_dir]

proc ::fa::xcrg_executable {} {
    set candidates {}
    if {[info exists ::env(XILINX_VIVADO)]} {
        lappend candidates [file join $::env(XILINX_VIVADO) bin xcrg.bat]
        lappend candidates [file join $::env(XILINX_VIVADO) bin xcrg]
    }
    lappend candidates xcrg.bat xcrg
    foreach candidate $candidates {
        set executable [auto_execok $candidate]
        if {[llength $executable] > 0} {
            return $executable
        }
    }
    error "XCRG nije pronadjen. Pokreni skriptu iz Vivado Tcl Console."
}

proc ::fa::load_tests {uvm_dir} {
    set file_handle [open [file join $uvm_dir scripts tests.tsv] r]
    set lines [split [string trim [read $file_handle]] \n]
    close $file_handle
    set tests {}

    foreach line [lrange $lines 1 end] {
        set fields [split [string trimright $line \r] \t]
        if {[llength $fields] != 14} {
            error "Neispravan red u tests.tsv: $line"
        }
        lassign $fields suites name seed rows heads b bc pattern data gaps stalls reset_compute last_stall purpose
        if {"extended" ni [split $suites {;}]} {
            continue
        }
        if {[info exists ::fa::test_filter] && [llength $::fa::test_filter] > 0 &&
            $name ni $::fa::test_filter} {
            continue
        }
        set flags {}
        if {$data} {
            lappend flags FA_RANDOM_DATA
        }
        if {$gaps} {
            lappend flags FA_INPUT_GAPS
        }
        if {$stalls} {
            lappend flags FA_OUTPUT_STALLS
        }
        if {!$data && !$gaps && !$stalls} {
            lappend flags FA_BASELINE
        }
        if {$reset_compute} {
            lappend flags FA_RESET_COMPUTE
        }
        if {$last_stall > 0} {
            lappend flags FA_LAST_STALL=$last_stall
        }
        lappend tests [list $name $seed $flags $data $gaps $stalls $rows $heads $b $bc $pattern $reset_compute]
    }
    return $tests
}

proc ::fa::merge_coverage {results_dir passing_tests} {
    if {[llength $passing_tests] == 0} {
        error "Nema uspesnih testova sa coverage bazom."
    }

    set arguments {}
    foreach name $passing_tests {
        lappend arguments -cov_db_dir [file join $results_dir $name coverage]
        lappend arguments -cov_db_name fa
    }

    set merged_dir [file join $results_dir coverage_merged]
    file mkdir $merged_dir
    set report_dir [file join $merged_dir html]
    set executable [::fa::xcrg_executable]
    puts "FA_COVERAGE spajanje [llength $passing_tests] uspesnih testova"
    set output [exec {*}$executable {*}$arguments \
        -merge_dir $merged_dir -merge_db_name merged \
        -report_dir $report_dir -report_format html 2>@1]
    puts $output

    set html [file join $report_dir functionalCoverageReport dashboard.html]
    if {![file exists $html]} {
        error "XCRG nije napravio HTML izvestaj."
    }
    return $html
}

proc ::fa::write_text {path value} {
    set fd [open $path w]
    try { puts $fd $value } finally { close $fd }
}

proc ::fa::capture_wave {name test_dir} {
    create_wave_config $name
    set signals [list /tb_fa_uvm/aclk]
    foreach signal {
        aresetn run all_done compute_active
        s_axis_tvalid s_axis_tready s_axis_tdata s_axis_tkeep s_axis_tlast
        m_axis_tvalid m_axis_tready m_axis_tdata m_axis_tkeep m_axis_tlast
    } {
        lappend signals /tb_fa_uvm/bus/$signal
    }
    foreach signal $signals {
        set object [get_objects -quiet $signal]
        if {[llength $object] == 0} { error "Missing waveform signal: $signal" }
        if {[string match *tdata $signal] || [string match *tkeep $signal]} {
            add_wave -radix hex $object
        } else {
            add_wave $object
        }
        log_wave $object
    }
    save_wave_config [file join $test_dir waveform.wcfg]
}

proc ::fa::copy_logs {simulation_dir test_dir} {
    set logs_dir [file join $test_dir logs]
    file mkdir $logs_dir
    foreach filename {compile.log xvlog.log xvhdl.log elaborate.log xelab.log simulate.log xsim.log} {
        set path [file join $simulation_dir $filename]
        if {[file exists $path]} { file copy -force $path [file join $logs_dir $filename] }
    }
}

proc ::fa::read_status {status test} {
    lassign $test name seed flags data gaps stalls rows heads b bc pattern reset_compute
    if {![file exists $status]} { return [list FAIL 0 "" "No final status.csv"] }
    set fd [open $status r]
    try { set lines [split [string trim [read $fd]] \n] } finally { close $fd }
    set fields [split [string trim [lindex $lines 1]] ,]
    if {[llength $fields] != 14} { return [list FAIL 0 "" "Invalid status.csv format"] }
    lassign $fields version reported checked maximum got_data got_gaps got_stalls got_rows got_heads got_b got_bc got_pattern got_reset got_reset_compute
    set expected_checked [expr {$reset_compute ? 0 : $rows*$heads*64}]
    if {$version ne "FA_UVM_R15" || $reported ne "PASS" ||
        $checked != $expected_checked || $got_data ne $data || $got_gaps ne $gaps ||
        $got_stalls ne $stalls || $got_rows ne $rows || $got_heads ne $heads ||
        $got_b ne $b || $got_bc ne $bc || $got_pattern ne $pattern ||
        $got_reset != $reset_compute || $got_reset_compute != $reset_compute} {
        return [list FAIL $checked $maximum "Final status does not match a completed passing test"]
    }
    return [list PASS $checked $maximum ""]
}

proc ::fa::execute {} {
    variable uvm_dir
    if {[llength [get_projects -quiet]] != 1} {
        error "Otvori postojeci FA UVM projekat pre pokretanja run_all.tcl."
    }
    set fileset [get_filesets -quiet sim_1]
    if {$fileset eq "" || [get_property top $fileset] ne "tb_fa_uvm" ||
        [get_property target_simulator [current_project]] ne "XSim"} {
        error "Otvoreni projekat mora koristiti XSim i sim_1 top tb_fa_uvm."
    }
    set package [file normalize [file join $uvm_dir tb fa_pkg.sv]]
    if {[llength [get_files -quiet $package]] != 1} {
        error "Otvoreni projekat ne koristi fa_pkg.sv iz ovog UVM okruzenja."
    }
    set project_dir [get_property DIRECTORY [current_project]]
    set project_name [get_property NAME [current_project]]
    set tests [::fa::load_tests $uvm_dir]
    if {[llength $tests] == 0} { error "No regression tests in tests.tsv" }
    set run_id [clock format [clock seconds] -format %Y%m%d_%H%M%S]
    set results_dir [file join $uvm_dir results run_all_$run_id]
    set suffix 0
    while {[file exists $results_dir]} {
        incr suffix
        set results_dir [file join $uvm_dir results run_all_${run_id}_$suffix]
    }
    set ::fa::last_results_dir $results_dir
    catch {close_sim}
    file mkdir $results_dir
    file copy [file join $uvm_dir scripts tests.tsv] [file join $results_dir tests.tsv]
    ::fa::write_text [file join $results_dir project.txt] [file join $project_dir ${project_name}.xpr]
    puts "FA_REGRESSION PROJECT: [file join $project_dir ${project_name}.xpr]"
    puts "FA_REGRESSION RESULTS: $results_dir"

    set simulation_dir [file join $project_dir ${project_name}.sim sim_1 behav xsim]
    set manifest [open [file join $results_dir run_manifest.csv] w]
    puts $manifest "test,seed,status,checked,max_abs_error,rows,heads,b,bc,pattern,reset_compute,waveform,coverage"
    set saved_properties {}
    foreach property {xsim.simulate.xsim.more_options xsim.simulate.runtime xsim.simulate.wdb verilog_define} {
        dict set saved_properties $property [get_property $property $fileset]
    }
    set old_defines [dict get $saved_properties verilog_define]
    set passing_tests {}
    set failed_tests {}
    set coverage_tests {}
    set infrastructure_errors {}
    try {
        set_property xsim.simulate.runtime 0ns $fileset
        foreach test $tests {
            lassign $test name seed flags data gaps stalls rows heads b bc pattern reset_compute
            set test_dir [file join $results_dir $name]
            file mkdir $test_dir
            set status [file join $test_dir status.csv]
            set failure [file join $test_dir failure.csv]
            set wave_enabled [expr {$name in {random_input_combined random_stalls_combined}}]
            set wave_db [file join $test_dir waveform.wdb]
            set options [list -sv_seed $seed -testplusarg UVM_VERBOSITY=UVM_NONE -testplusarg UVM_MAX_QUIT_COUNT=1]
            foreach flag $flags { lappend options -testplusarg $flag }
            foreach setting [list "FA_PATTERN=$pattern" "FA_RESULTS_FILE=$failure" "FA_STATUS_FILE=$status" "FA_PREVIEW_FILE=[file join $test_dir output_preview.csv]"] {
                lappend options -testplusarg $setting
            }
            set_property -name xsim.simulate.xsim.more_options -value $options -objects $fileset
            set defines {}
            foreach define $old_defines {
                if {![regexp {^FA_(ROWS|HEADS|B|BC)(=|$)} $define]} { lappend defines $define }
            }
            lappend defines FA_ROWS=$rows FA_HEADS=$heads FA_B=$b FA_BC=$bc
            set_property -name verilog_define -value $defines -objects $fileset
            if {$wave_enabled} {
                set_property xsim.simulate.wdb $wave_db $fileset
            } else {
                set_property xsim.simulate.wdb {} $fileset
            }
            update_compile_order -fileset sim_1
            ::fa::write_text [file join $test_dir configuration.txt] "test=$name\nseed=$seed\nrows=$rows\nheads=$heads\nb=$b\nbc=$bc\npattern=$pattern\nflags=$flags\nwaveform=$wave_enabled"
            puts "FA_REGRESSION START: $name seed=$seed waveform=$wave_enabled"
            set launched 0
            set simulation_failed [catch {
                launch_simulation -simset sim_1 -mode behavioral
                set launched 1
                if {$wave_enabled} { ::fa::capture_wave $name $test_dir }
                ::run all
                if {$reset_compute} {
                    set stream_state [get_value /tb_fa_uvm/dut/engine/state]
                    set core_state [get_value /tb_fa_uvm/dut/core/ctrl/state]
                    ::fa::write_text [file join $test_dir reset_state.txt] "stream_state=$stream_state\ncore_state=$core_state"
                    if {![string equal -nocase $stream_state IDLE] ||
                        ![string equal -nocase $core_state ST_IDLE]} {
                        error "Reset did not return both RTL state machines to IDLE"
                    }
                }
            } simulation_message]

            # Preserve coverage even after a runtime failure, when XSim permits it.
            set coverage_saved 0
            set coverage_message "Simulation was not launched"
            if {$launched} {
                set coverage_dir [file join $test_dir coverage]
                file mkdir $coverage_dir
                if {![catch {write_xsim_coverage -cov_db_dir $coverage_dir -cov_db_name fa} coverage_message]} {
                    set coverage_saved 1
                }
            }
            catch {close_sim}
            ::fa::copy_logs $simulation_dir $test_dir
            if {[catch {::fa::read_status $status $test} status_record]} {
                set status_record [list FAIL 0 "" "Cannot parse final status: $status_record"]
            }
            lassign $status_record result checked maximum status_message
            if {$simulation_failed || [file exists $failure]} { set result FAIL }
            if {$wave_enabled && (![file exists $wave_db] || [file size $wave_db] == 0)} {
                set result FAIL
                append status_message " Missing waveform database."
            }
            if {!$coverage_saved} {
                lappend infrastructure_errors "$name: coverage could not be saved"
                ::fa::write_text [file join $test_dir coverage_error.txt] $coverage_message
            }
            if {$result eq "PASS"} {
                lappend passing_tests $name
                if {$coverage_saved} { lappend coverage_tests $name }
            } else {
                lappend failed_tests $name
                ::fa::write_text [file join $test_dir failure_note.txt] "test=$name\nsimulator_error=$simulation_failed\nsimulator_message=$simulation_message\nstatus_message=$status_message\ncoverage_saved=$coverage_saved"
                if {![file exists $status]} {
                    ::fa::write_text $status "version,status,checked,max_abs_error,random_data,input_gaps,output_stalls,rows,heads,b,bc,pattern,reset_done,reset_compute\nFA_UVM_R15,FAIL,$checked,$maximum,$data,$gaps,$stalls,$rows,$heads,$b,$bc,$pattern,0,$reset_compute"
                }
            }
            puts $manifest "$name,$seed,$result,$checked,$maximum,$rows,$heads,$b,$bc,$pattern,$reset_compute,$wave_enabled,$coverage_saved"
            flush $manifest
            puts "FA_REGRESSION $result: $name checked=$checked max_error=$maximum"
        }
    } finally {
        close $manifest
        catch {close_sim}
        dict for {property value} $saved_properties {
            set_property -name $property -value $value -objects $fileset
        }
        update_compile_order -fileset sim_1
    }

    set html ""
    if {[llength $coverage_tests] > 0} {
        if {[catch {::fa::merge_coverage $results_dir $coverage_tests} html]} {
            ::fa::write_text [file join $results_dir coverage_merge_error.txt] $html
            lappend infrastructure_errors "Coverage merge failed"
            set html ""
        }
    }
    set summary "PASS=[llength $passing_tests]\nFAIL=[llength $failed_tests]\nfailed_tests=$failed_tests\ncoverage_tests=$coverage_tests\ninfrastructure_errors=$infrastructure_errors\ncoverage_html=$html"
    ::fa::write_text [file join $results_dir summary.txt] $summary
    puts "FA_REGRESSION SUMMARY: PASS=[llength $passing_tests] FAIL=[llength $failed_tests]"
    if {$html ne ""} { puts "FA_REGRESSION COVERAGE: $html" }
    puts "FA_REGRESSION EVIDENCE: $results_dir"
    if {[llength $failed_tests] || [llength $infrastructure_errors]} {
        error "Regression or coverage failed. Evidence preserved in $results_dir"
    }
}

if {![info exists ::fa::library_only] || !$::fa::library_only} {
    ::fa::execute
}
