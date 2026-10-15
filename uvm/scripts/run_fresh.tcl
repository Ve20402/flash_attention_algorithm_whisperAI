set script_dir [file dirname [file normalize [info script]]]
set uvm_dir [file dirname $script_dir]
set root_dir [file dirname $uvm_dir]

if {[llength [get_projects -quiet]] != 0} {
    error "Close the current Vivado project before running run_fresh.tcl"
}

set rtl_dir [file join $root_dir rtl hdl]
set rtl_files {}
foreach name {fa_types_pkg memory ring_buffer exp_rom recip_rom datapath_v2 controlpath_real top_qkt_v2 streaming_block fa_axis_top} {
    lappend rtl_files [file join $rtl_dir ${name}.vhd]
}
set tb_files [list \
    [file join $uvm_dir tb fa_if.sv] \
    [file join $uvm_dir tb fa_pkg.sv] \
    [file join $uvm_dir tb tb_fa_uvm.sv]]
foreach path [concat $rtl_files $tb_files] {
    if {![file isfile $path]} { error "Missing source file: $path" }
}

set stamp [clock format [clock seconds] -format %Y%m%d_%H%M%S]
set project_dir [file join $uvm_dir build fresh_$stamp]
if {[file exists $project_dir]} { error "Project directory already exists: $project_dir" }

create_project fa_uvm $project_dir -part xc7z010clg400-1
try {
    set_property target_language VHDL [current_project]
    set_property target_simulator XSim [current_project]
    set_property simulator_language Mixed [current_project]

    add_files -fileset sources_1 -norecurse $rtl_files
    set_property file_type {VHDL 2008} [get_files $rtl_files]
    set_property top fa_axis_top [get_filesets sources_1]

    add_files -fileset sim_1 -norecurse $tb_files
    set_property file_type SystemVerilog [get_files $tb_files]
    set sim_set [get_filesets sim_1]
    set_property top tb_fa_uvm $sim_set
    set_property include_dirs [list $uvm_dir [file join $uvm_dir tb] [file join $uvm_dir components]] $sim_set
    set_property -name xsim.compile.xvlog.more_options -value {-L uvm} -objects $sim_set
    set_property -name xsim.elaborate.xelab.more_options -value {-L uvm} -objects $sim_set
    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1

    puts "FA_UVM PROJECT: [file join $project_dir fa_uvm.xpr]"
    source [file join $script_dir run_all.tcl]
} finally {
    close_project
}
