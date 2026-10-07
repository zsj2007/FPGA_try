set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ..]]
set project    [file join $repo_root build vivado new_fpga.xpr]
set synth_top  brightest_window

if {[llength $argv] > 0} {
    set synth_top [lindex $argv 0]
}

if {![file exists $project]} {
    error "Project does not exist. Run vivado/create_project.tcl first."
}

open_project $project
puts "Running out-of-context synthesis top: $synth_top"
synth_design -top $synth_top -part xc7z010clg400-2 -mode out_of_context
report_utilization -file [file join $repo_root build ${synth_top}_utilization.rpt]
report_timing_summary -file [file join $repo_root build ${synth_top}_timing.rpt]
close_project

