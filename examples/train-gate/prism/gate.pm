pta

// PTA generated from Soar rules using time scale 1.000
const double time_scale = 1.000;
// time units: ticks
const int deadline;
const int use_box;
const double box_accuracy;

module environment
    state_io_ctrl_state : [0..2] init 0;

endmodule

module context
    state_type : [0..1] init 0;
    state_gate_position : [0..1] init 0;

    [lower] state_gate_position = 0 & state_io_ctrl_state = 2 -> 1.0 : (state_gate_position' = 1);
    [raise] state_gate_position = 1 & state_io_ctrl_state = 0 -> 1.0 : (state_gate_position' = 0);
endmodule


