set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ..]]
set build_dir  [file join $repo_root build vivado]

if {[llength $argv] > 0} {
    set build_dir [file normalize [lindex $argv 0]]
}

create_project -force new_fpga $build_dir -part xc7z010clg400-2
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property source_mgmt_mode None [current_project]

add_files -norecurse [list     [file join $repo_root modules axis_video_passthrough axis_video_passthrough.sv]     [file join $repo_root modules binary_threshold binary_threshold.sv]     [file join $repo_root modules bounding_box_overlay bounding_box_overlay.sv]     [file join $repo_root modules camera_capture camera_capture.sv]     [file join $repo_root modules los_guidance cordic_atan2.sv]     [file join $repo_root modules los_guidance los_guidance.sv]     [file join $repo_root modules blob_analyzer ccl_analyzer.sv]     [file join $repo_root modules vision_pipeline vision_pipeline.sv] ]

add_files -fileset sim_1 -norecurse [list     [file join $repo_root modules axis_video_passthrough axis_video_passthrough_tb.sv]     [file join $repo_root modules binary_threshold binary_threshold_tb.sv]     [file join $repo_root modules bounding_box_overlay bounding_box_overlay_tb.sv]     [file join $repo_root modules camera_capture camera_capture_tb.sv]     [file join $repo_root modules los_guidance los_guidance_tb.sv]     [file join $repo_root modules vision_pipeline vision_pipeline_tb.sv]     [file join $repo_root modules vision_pipeline vision_pipeline_image_tb.sv]     [file join $repo_root modules vision_pipeline vision_pipeline_video_tb.sv] ]

set_property top vision_pipeline [get_filesets sources_1]
set_property top vision_pipeline_video_tb [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]

puts "Created project: [file join $build_dir new_fpga.xpr]"
puts "Next: Flow Navigator -> Simulation -> Run Behavioral Simulation"
