set script_dir [file normalize [file dirname [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set hdl_dir [file join $repo_dir hdl]
set xdc_file [file join $repo_dir xdc fa_axis_top.xdc]
set build_dir [file join $repo_dir build]
set project_dir [file join $build_dir fa_axis_project]
set ip_root [file join $build_dir ip_repo fa_axis_top_1_0]
set report_dir [file join $build_dir reports]

#Dodavanje izvora projekta
set hdl_files [list \
    [file join $hdl_dir fa_types_pkg.vhd] \
    [file join $hdl_dir memory.vhd] \
    [file join $hdl_dir ring_buffer.vhd] \
    [file join $hdl_dir exp_rom.vhd] \
    [file join $hdl_dir recip_rom.vhd] \
    [file join $hdl_dir datapath_v2.vhd] \
    [file join $hdl_dir controlpath_real.vhd] \
    [file join $hdl_dir top_qkt_v2.vhd] \
    [file join $hdl_dir streaming_block.vhd] \
    [file join $hdl_dir fa_axis_top.vhd]]

foreach source_file [concat $hdl_files [list $xdc_file]] {
    if {![file exists $source_file]} {
        error "Missing source file: $source_file"
    }
}

if {[llength [get_projects -quiet]] != 0} {
    error "Close the current Vivado project before running this script"
}

#Kreiranje novog Vivado projekta
file delete -force $build_dir
file mkdir $project_dir
file mkdir $report_dir

create_project fa_axis_project $project_dir -part xc7z010clg400-1
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
add_files -norecurse $hdl_files
add_files -fileset constrs_1 -norecurse $xdc_file
set_property file_type {VHDL 2008} [get_files -all *.vhd]
set_property top fa_axis_top [current_fileset]
update_compile_order -fileset sources_1

#Sinteza projekta
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"
}

#Implementacija projekta
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementation failed: [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1
report_utilization -file [file join $report_dir utilization_post_route.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 10 -input_pins -file [file join $report_dir timing_post_route.rpt]
write_checkpoint -force [file join $report_dir fa_axis_top_post_route.dcp]
close_design

#Pakovanje fa_axis_top modula kao Vivado IP
ipx::package_project -root_dir $ip_root -vendor student.local -library user -taxonomy /UserIP -import_files -set_current true
set ip_core [ipx::current_core]
set_property vendor student.local $ip_core
set_property library user $ip_core
set_property name fa_axis_top $ip_core
set_property version 1.0 $ip_core
set_property display_name {FlashAttention AXI Stream Accelerator} $ip_core
set_property description {Fixed-point multi-head FlashAttention accelerator with AXI4-Stream interfaces} $ip_core

set clock_interface [ipx::get_bus_interfaces aclk -of_objects $ip_core]
set frequency_parameter [ipx::get_bus_parameters FREQ_HZ -of_objects $clock_interface]
if {$frequency_parameter eq ""} {
    set frequency_parameter [ipx::add_bus_parameter FREQ_HZ $clock_interface]
}
set_property value 100000000 $frequency_parameter

ipx::create_xgui_files $ip_core
ipx::update_checksums $ip_core
ipx::check_integrity -quiet $ip_core
ipx::save_core $ip_core

puts "BUILD PASSED"
puts "Project: [file join $project_dir fa_axis_project.xpr]"
puts "Packaged IP: $ip_root"
puts "Reports: $report_dir"
