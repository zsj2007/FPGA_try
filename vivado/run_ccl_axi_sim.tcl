# Standalone project so the existing video simulation selection is preserved.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set build_dir [file join $repo_root build ccl_axi]
create_project -force ccl_axi $build_dir -part xc7z010clg400-2
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
add_files -norecurse [list \
    [file join $repo_root modules blob_analyzer ccl_analyzer_pl.sv] \
    [file join $repo_root modules axi_bridge ccl_axi_lite.sv]]
add_files -fileset sim_1 -norecurse [file join $repo_root modules axi_bridge ccl_axi_lite_tb.sv]
set_property top ccl_axi_lite [get_filesets sources_1]
set_property top ccl_axi_lite_tb [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set pass_file [file join $build_dir ccl_axi.sim sim_1 behav xsim ccl_axi_pass.txt]
if {[file exists $pass_file]} {file delete $pass_file}
launch_simulation
if {![file exists $pass_file]} {error "CCL AXI simulation did not produce PASS; inspect XSim log"}
puts "CCL AXI simulation PASS: $pass_file"
close_sim
close_project
