pta

// PTA generated from Soar rules using time scale 1.000
const double time_scale = 1.000;
// time units: ticks
const int deadline;
const int use_box;
const double box_accuracy;

module environment
    state_io_clock : [1..17] init 1;

endmodule

module context
    state_type : [0..1] init 0;
    state_ctrl_state : [0..3] init 0;
    tm : clock;

    invariant
    (state_ctrl_state = 0) => tm <= 2 &
    (state_ctrl_state = 1) => tm <= 6 &
    (state_ctrl_state = 2) => tm <= 14 &
    (state_ctrl_state = 3) => tm <= 17
    endinvariant

    [approach] state_ctrl_state = 0 & state_io_clock > 1 & state_io_clock <= 2 -> 1.0 : (state_ctrl_state' = 1);
    [lower] state_ctrl_state = 1 & state_io_clock > 2 & state_io_clock <= 6 -> 1.0 : (state_ctrl_state' = 2);
    [exit] state_ctrl_state = 2 & state_io_clock > 12 & state_io_clock <= 14 -> 1.0 : (state_ctrl_state' = 3);
    [raise] state_ctrl_state = 3 & state_io_clock > 14 & state_io_clock <= 17 -> 1.0 : (state_ctrl_state' = 0) & (tm' = 0);
endmodule


