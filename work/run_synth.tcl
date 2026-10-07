open_project D:/new_FPGA/build/vivado3/new_fpga.xpr
puts "Running synthesis on vision_pipeline..."
synth_design -top vision_pipeline -part xc7z010clg400-2 -mode out_of_context
puts "Synthesis complete."
close_project
