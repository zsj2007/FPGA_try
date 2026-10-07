set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ..]]
set project    [file join $repo_root build vivado new_fpga.xpr]
set sim_top    vision_pipeline_tb

if {[llength $argv] > 0} {
    set sim_top [lindex $argv 0]
}

# Optional second argument selects an alternate .xpr file.
if {[llength $argv] > 1} {
    set project [file normalize [lindex $argv 1]]
}

if {![file exists $project]} {
    error "Project does not exist. Run vivado/create_project.tcl first."
}

open_project $project
set_property top $sim_top [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
puts "Running simulation top: $sim_top"
launch_simulation
close_sim
close_project
