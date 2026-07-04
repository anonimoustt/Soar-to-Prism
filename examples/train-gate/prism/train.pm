pta

// PTA generated from Soar rules using time scale 1.000
const double time_scale = 1.000;
// time units: ticks
const int deadline;
const int use_box;
const double box_accuracy;

module environment
    state_io_clock : [1..12] init 1;

endmodule

module context
    state_type : [0..1] init 0;
    state_position : [0..2] init 0;
    tm : clock;

    invariant
    (state_position = 0) => tm <= 2 &
    (state_position = 1) => tm <= 9 &
    (state_position = 2) => tm <= 12
    endinvariant

    [approach] state_position = 0 & state_io_clock > 1 & state_io_clock <= 2 -> 1.0 : (state_position' = 1);
    [enter] state_position = 1 & state_io_clock > 6 & state_io_clock <= 9 -> 1.0 : (state_position' = 2);
    [exit] state_position = 2 & state_io_clock > 9 & state_io_clock <= 12 -> 1.0 : (state_position' = 0);
endmodule


