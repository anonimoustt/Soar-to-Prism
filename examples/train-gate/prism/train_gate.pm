// Composed PTA model for the Train-Gate railroad crossing, assembled by hand
// from the three per-agent snippets that the Soar-to-PRISM translator emits
// (controller.pm, train.pm, gate.pm in this directory). See
// examples/train-gate/TRANSLATION_WALKTHROUGH.md for how each piece was
// generated and why the hand-assembly steps below were necessary:
//
//  - PRISM requires module/variable/action names to be unique across the
//    whole file; the translator only sees one Soar agent at a time, so the
//    per-agent snippets all reused "module context", "state_type", etc.
//    Names below are disambiguated (ctrl_state / position / gate_position,
//    and t_/g_ prefixed action labels for train/gate) so the three modules
//    don't collide or accidentally force PRISM synchronization on actions
//    that are only coincidentally named the same (e.g. train's "approach"
//    and the controller's "approach" are independent decisions in Soar --
//    giving them the same PRISM action label would force them to fire in
//    lockstep, which is not what the isolated-working-memory Soar agents do).
//  - The translator captured the shared tick counter as an ordinary bounded
//    variable ("state_io_clock", fed from Python in the real system) because
//    it has no way to know it should be the same quantity as a native PRISM
//    PTA clock. Nothing in the generated PRISM would ever advance it. Here
//    it is replaced by a real PTA clock that PRISM advances automatically --
//    that's the actual point of using PTA instead of a plain DTMC/MDP: time
//    elapses continuously and clocks gate transitions instead of being
//    stepped by hand. (It can't be named "clock" -- that word is the PRISM
//    keyword used to declare a clock's *type*, so a variable can't be
//    named that.)
//  - Each module gets its OWN clock (tm_c, tm_t) rather than sharing one
//    across modules. An earlier version shared a single clock declared in
//    "controller" and merely read from "train"; PRISM's PTA/digital-clocks
//    engine built that model with no error but did not actually enforce
//    train's invariant against a clock it didn't own -- PRISM reported a
//    live "timelock" state (ctrl_state=2, position=0, ...) that should have
//    been unreachable. Every clock in PRISM's own bundled multi-module PTA
//    examples (e.g. prism-examples/ptas/csma) is likewise local to the
//    module whose invariant uses it. Since both clocks here start at 0 and
//    tick at the same global rate, they only need to be reset in lockstep to
//    stay equal -- done via the shared, synchronized [raise] action (a
//    no-op for train's own state, just there to reset tm_t together with
//    controller's tm_c at the end of every 17-tick cycle).
//  - The unused "state_type" variable (a leftover from matching the Soar
//    idiom "^type state" in each agent's init rule) is dropped; it was never
//    read or written by any transition.

pta

module controller
  ctrl_state : [0..3] init 0; // 0=S0 1=S1 2=S2 3=S3
  tm_c : clock;

  invariant
    (ctrl_state=0 => tm_c<=2) &
    (ctrl_state=1 => tm_c<=6) &
    (ctrl_state=2 => tm_c<=14) &
    (ctrl_state=3 => tm_c<=17)
  endinvariant

  // tm_c is integer-valued (ticks), so the original Soar guard "clock > X <= Y"
  // is written here as the equivalent non-strict "tm_c >= X+1 & tm_c <= Y" --
  // PRISM's digital-clocks checking engine (used below) rejects strict bounds.
  [approach] ctrl_state = 0 & tm_c >= 2  & tm_c <= 2  -> 1.0 : (ctrl_state' = 1);
  [lower]    ctrl_state = 1 & tm_c >= 3  & tm_c <= 6  -> 1.0 : (ctrl_state' = 2);
  [exit]     ctrl_state = 2 & tm_c >= 13 & tm_c <= 14 -> 1.0 : (ctrl_state' = 3);
  [raise]    ctrl_state = 3 & tm_c >= 15 & tm_c <= 17 -> 1.0 : (ctrl_state' = 0) & (tm_c' = 0);
endmodule

module train
  // 0=far (fresh cycle, about to approach) 1=near 2=in
  // 3=far-done (already exited, just waiting out the rest of the cycle for
  // the shared reset). Soar only has one "far" value, but it's revisited
  // twice per cycle with two different timing rules attached (must leave by
  // tick 2 the first time; free to sit there the second time) -- collapsing
  // both into a single PRISM location produced an unenforceable invariant
  // and a real timelock, e.g. (position=0, tm_t=10) after an earlier exit.
  // Splitting the reused Soar value into two PRISM locations is the standard
  // timed-automata fix.
  position : [0..3] init 0;
  tm_t : clock;

  invariant
    (position=0 => tm_t<=2) &
    (position=1 => tm_t<=9) &
    (position=2 => tm_t<=12) &
    (position=3 => tm_t<=17)
  endinvariant

  [t_approach] position = 0 & tm_t >= 2  & tm_t <= 2  -> 1.0 : (position' = 1);
  [t_enter]    position = 1 & tm_t >= 7  & tm_t <= 9  -> 1.0 : (position' = 2);
  [t_exit]     position = 2 & tm_t >= 10 & tm_t <= 12 -> 1.0 : (position' = 3);
  // Synchronized with the controller's cycle-reset action: both must be ready
  // (train already done with its lap, controller's own clock in [15,17])
  // before the joint reset fires and a new cycle starts.
  [raise] position = 3 -> 1.0 : (position' = 0) & (tm_t' = 0);
endmodule

module gate
  gate_position : [0..1] init 0; // 0=up 1=down

  [g_lower] gate_position = 0 & ctrl_state = 2 -> 1.0 : (gate_position' = 1);
  [g_raise] gate_position = 1 & ctrl_state = 0 -> 1.0 : (gate_position' = 0);
endmodule
