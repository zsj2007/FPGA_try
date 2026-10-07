open_project D:/new_FPGA/build/vivado4/new_fpga.xpr
set_property -name {xsim.elaborate.xelab.more_options} -value {} -objects [get_filesets sim_1]
set_property -name {xsim.compile.xvlog.more_options} -value {} -objects [get_filesets sim_1]
launch_simulation
run all
close_sim
close_project
