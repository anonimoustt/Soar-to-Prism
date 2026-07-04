# Soar → PRISM (PTA) Walkthrough: the Train-Gate crossing

This is a from-scratch walkthrough of translating a real, multi-agent Soar
model into a PRISM **probabilistic timed automaton (PTA)**, written for
someone who is new to Soar, PRISM, and PTA all at once. It uses the
[Multi-agent-Train-gate](https://github.com/rsen2025-star/Multi-agent-Train-gate)
railroad-crossing simulation (copied into `agents/` and `Uppaal/` in this
directory) as the running example, because it's small, already has a
reference formal model (a hand-built UPPAAL timed automaton), and its Soar
rules are simple enough to read in one sitting.

By the end, a Soar model of three independent, communicating agents becomes
a PRISM `.pm` file that a real model checker verifies — and the verification
results match the ones already published for the UPPAAL version.

---

## 1. The three technologies, briefly

**Soar** is a cognitive-architecture language for writing rule-based agents.
An agent's *working memory* is a graph of attribute-value pairs rooted at a
`state`. Rules (`sp { ... }`) match against working memory and fire in two
phases per decision:

- **propose** rules test the current state and, if their conditions hold,
  create an `operator` — essentially "this action is a candidate right now."
- **apply** rules test that a specific operator was selected and then
  actually change working memory (the operator's effect).

This repo's Soar files use one very common idiom throughout:
```
(<s> ^position far - near)
```
"far - near" means: retract the old value `far`, assert the new value
`near`. It looks unusual until you've seen it once.

**PRISM** is a probabilistic model checker. You describe a system as one or
more `module`s with typed variables and guarded, probabilistic transitions
(`[label] guard -> prob1 : update1 + prob2 : update2 + ...;`), and then ask
PRISM to compute the probability that some property holds (e.g. "the system
reaches an error state with probability ≤ 0.01").

**PTA (probabilistic timed automata)** extend that with real-valued
**clocks**: variables that increase continuously at rate 1 (you never
assign them a value directly — you can only *reset* one to 0). A location
can have:
- a **guard** on a transition — a clock comparison like `tm >= 2 & tm <= 6`
  gating when the transition is allowed to fire, and
- an **invariant** — a clock bound like `tm <= 6` that caps how long the
  system is allowed to *dwell* in a location before it must take some
  transition.

Invariants matter more than they look like they should: without one, a
system can sit in a location letting its clock run arbitrarily far past a
transition's window, and PRISM will refuse to model-check the result at all
("timelock" — see §5).

---

## 2. The example: a railroad level crossing

Three independent Soar agents, each with its own isolated working memory
(they cannot see each other's state directly):

| Agent | States | Decision basis |
|---|---|---|
| Train | far → near → in → far | absolute tick count |
| Controller | S0 → S1 → S2 → S3 → S0 | absolute tick count |
| Gate | up ↔ down | `ctrl-state`, mirrored in from the Controller each tick |

A Python harness (not translated here) ticks a shared clock once per step
and copies the Controller's `ctrl-state` onto the Gate's input link — Soar
agents can't share memory directly, so this is the system's only inter-agent
communication. One full cycle is 17 ticks; see `SOURCE_README.md` in this
directory for the full timing table and the original project's own README.

Look at `agents/controller/controller_v2.soar` for a minimal example of the
propose/apply pattern with a timing guard:
```
sp {controller*propose*approach
    (state <s> ^ctrl-state 0
               ^io.input-link.clock { <c> > 1 <= 2 })
-->
    (<s> ^operator <o> +)
    (<o> ^name approach)
}

sp {controller*apply*approach
    (state <s> ^operator <o> ^ctrl-state 0)
    (<o> ^name approach)
-->
    (<s> ^ctrl-state 0 - 1)
}
```
`{ <c> > 1 <= 2 }` is a Soar *conjunctive test*: both `> 1` and `<= 2` must
hold for the same clock value. This detail turns out to matter a lot below.

---

## 3. Building and running the translator

```
mvn clean compile
mvn exec:java -Dexec.mainClass="edu.fit.assist.translator.soar.main" \
  -Dexec.args="path/to/model.soar path/to/config.json"
```

The translator picks one of three output paths (`main.java`):
1. **PTA** — if the config has `clocks`/`operators`/`states`, or
   `model_type: "pta"`.
2. **Time-based DTMC/MDP** — if Soar rules reference a `time-counter`-style
   variable (this path is tailored to this project's other example model, a
   cybersickness/attention monitor; it doesn't apply here).
3. **General translator** — the fallback; the top-level `README.md` already
   flags this path as not functional.

For a multi-agent Soar model like this one, translate **each agent
separately** — `main.java` merges everything it's given into one PRISM
module, and (as covered in §6) trying to combine three agents' rules in a
single translator run causes their same-named operators to silently
collide. Point the translator at one agent's `.soar` file plus a small PTA
config, e.g. `config/controller_pta_config.json`:
```json
{
  "model_type": "pta",
  "clocks": { "tm": { "min_duration": 0, "max_duration": 17 } },
  "operators": {
    "approach": { "resets_clock": false },
    "lower":    { "resets_clock": false },
    "exit":     { "resets_clock": false },
    "raise":    { "resets_clock": true }
  },
  "states": {
    "0": { "variable": "ctrl-state", "clock": "tm", "time_bound": 2 },
    "1": { "variable": "ctrl-state", "clock": "tm", "time_bound": 6 },
    "2": { "variable": "ctrl-state", "clock": "tm", "time_bound": 14 },
    "3": { "variable": "ctrl-state", "clock": "tm", "time_bound": 17 }
  },
  "pta_semantics": { "use_init_phase": false }
}
```
A few things worth knowing about this config, per `CONFIG_GUIDE.md`:
- `clocks` declares PTA clock variables; **don't name one `clock`** — that
  word is PRISM's own keyword for declaring a clock's type, so `clock :
  clock;` is a syntax error in real PRISM. (`tm` here, short for "time.")
- `operators` maps a Soar operator name to timing metadata, including
  whether firing it resets a clock.
- `states` is what actually produces PRISM `invariant` blocks (see §5) —
  one entry per value the location variable can take, each with the clock
  bound that applies while in that value.
- `pta_semantics.use_init_phase: false` turns off a feature aimed at a
  different example model in this repo (a "mission hasn't started yet"
  gate on every transition); leaving it on with no matching Soar rules
  makes every transition permanently unreachable.

Running this against `agents/controller/controller_v2.soar` produces
`controller.pm` in this directory (also copied to `output1.pm` by the tool).
`train.pm` and `gate.pm` come from the analogous
`config/train_pta_config.json` and `config/gate_pta_config.json`.

---

## 4. Three real bugs found and fixed along the way

Running the *unmodified* translator against this model didn't produce a
correct PTA — it crashed, then produced an empty module, then produced a
timing-free module. Each symptom traced back to a distinct, fixable bug in
`src/main/java/edu/fit/assist/translator/soar/`:

1. **Crash on `(state <s> ^type state)`.** Soar's grammar treats the word
   `state` as a reserved token (`STATE`) that can *also* appear as an
   ordinary constant — e.g. testing `^type` for the literal value `state`,
   which every agent's init rule here does. `Visitor.visitConstant` only
   handled the `Sym_constant` grammar alternative and null-pointer-crashed
   on the `STATE` alternative. Fixed in `Visitor.java`.

2. **Conjunctive clock tests silently lost their second half.**
   `Visitor.visitConjunctive_test` visited only the *first* clause of a
   Soar conjunctive test like `{ <c> > 1 <= 2 }` and discarded the rest —
   the code even had a `// Conjunctive test not supported` comment. Every
   timing guard in this model uses exactly that two-sided-range idiom, so
   every guard was silently truncated to just its lower bound. Fixed by
   having the visitor join all clauses and having
   `Visitor.visitAttr_value_tests` emit one guard per clause instead of
   mangling them into a single malformed comparison.

3. **Agent-prefixed rule names weren't recognized at all.**
   `PtaTranslator.extractRuleLabels` only matched rule names that *start
   with* `propose*`/`apply*`. This repo's rules are named
   `controller*apply*approach` (agent-prefixed), which the check silently
   skipped entirely — every rule in the model was invisible to the PTA
   translator, producing a module with declared variables but zero
   transitions. Fixed by matching the segment anywhere in the name, and by
   fixing the label-inference fallback to extract the text *after*
   `apply*`/`propose*` rather than everything after the first `*`.

There's a fourth, related fix that's more of a missing-feature-wiring than
a bug: `PtaTranslator.generateInvariants()` — the method that turns a
config's `states` section into PRISM `invariant` blocks, exactly as
`CONFIG_GUIDE.md` describes — was never actually called from the PTA
generation path. `states` config was accepted and silently ignored. That's
wired up now too (see §5 for why it matters).

After all four fixes, translating the Controller agent alone produces:
```
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
```
— which matches the Controller's guard table in `SOURCE_README.md` exactly
(S0→S1 at `1<clock<=2`, S1→S2 at `2<clock<=6`, S2→S3 at `12<clock<=14`,
S3→S0 at `14<clock<=17`). Same story for `train.pm` against the Train's
guard table.

---

## 5. Why the raw generated files still don't *run*, and how to fix that

Loading `controller.pm` into real PRISM and asking `Pmax=? [ F
state_ctrl_state=3 ]` (can the Controller ever reach S3?) gives **0.0** —
never. The reason: `state_io_clock` (captured from the Soar variable
`^io.input-link.clock`, driven externally by the Python harness in the real
system) is declared as an ordinary bounded integer, stuck at its initial
value of 1 forever, because nothing in the generated PRISM ever changes it.
The translator has no way to know that this externally-fed Soar variable
and the PTA clock declared in the config (`tm`) are *the same real-time
quantity* — that's a modeling judgment call, not something inferable from
the Soar text alone.

The fix is a one-line-per-guard substitution: replace `state_io_clock`
with the real clock `tm` in every guard, e.g.
```
[approach] state_ctrl_state = 0 & tm > 1 & tm <= 2 -> 1.0 : (state_ctrl_state' = 1);
```
With that substitution (and PRISM's digital-clocks checking engine, which
needs non-strict bounds — `tm > 1` becomes `tm >= 2` since `tm` only takes
integer tick values here), the standalone Controller model verifies
cleanly: `Pmax=? [ F state_ctrl_state=3 ]` = **1.0**, `Pmax=? [ G true ]`
(no timelock anywhere) = **1.0**.

This is also where the now-wired-up `states`/invariant config earns its
keep. Try deleting the `invariant` block and re-running — PRISM (with
`-ptamethod digital`) reports:
```
Error: Timelock in PTA, e.g. in state (ctrl_state=0,tm=17,...)
```
Without an invariant capping how long the Controller may dwell in S0, `tm`
can run past the `approach` transition's `[2,2]` window with nothing
forcing the jump, and once it hits the model's global clock ceiling there's
no transition and no further time allowed to pass — a genuine dead end.
This is *why* PTA invariants exist, not an optional decoration.

---

## 6. Composing three agents into one PRISM file

`prism/train_gate.pm` hand-assembles the three translated pieces
(`prism/controller.pm`, `prism/train.pm`, `prism/gate.pm`) into one runnable
model. This step is manual and worth understanding, because every issue
below is a translator limitation you'll hit again on any other multi-agent
Soar model:

- **PRISM needs globally unique module/variable/action names; the
  translator only ever sees one agent.** All three raw snippets declare
  `module context` with a variable literally named `state_type`. Simple
  textual renaming (`ctrl_state`, `position`, `gate_position`, `module
  controller`/`train`/`gate`) fixes this — but you have to notice it and do
  it by hand.
- **Same-named actions force unwanted synchronization.** Train's
  `[approach]` and Controller's `[approach]` are independent decisions in
  Soar (isolated working memory, no shared rule), but PRISM synchronizes
  *any* modules that declare an action with the same label — they'd be
  forced to fire in lockstep, which silently changes the model's meaning.
  Renamed Train's and Gate's actions with `t_`/`g_` prefixes to keep them
  independent.
- **A clock is only meaningfully enforced by the module that owns it.**
  An earlier version of this file declared one `tm` clock in `controller`
  and just *read* it from `train`'s guards and invariant. PRISM built that
  model without a syntax error, but didn't actually enforce train's
  invariant against a clock it didn't own — PRISM's own reachability
  analysis found a live, invariant-violating "timelock" state. Every
  multi-module PTA example PRISM ships (e.g. `prism-examples/ptas/csma`)
  gives each module its own local clock instead of sharing one; doing the
  same here (`tm_c`, `tm_t`, reset together via a shared, synchronized
  `[raise]` action) fixed it.
- **A Soar value re-used across a cycle needs splitting into two PRISM
  locations if its timing rules differ each time.** Train's Soar `position`
  only has three values (far/near/in), but "far" means two different things
  across one 17-tick cycle: "haven't approached yet, must leave by tick 2"
  and "already exited, just waiting out the rest of the cycle for the
  shared reset." One PRISM invariant can't express both at once — it either
  wrongly caps the second visit at `tm<=2` too (timelock) or fails to force
  the first visit's deadline. The fix is the standard timed-automata one:
  give the "already exited" phase its own location value (`position=3`)
  with its own, looser invariant, distinct from the fresh-cycle
  `position=0`.

None of this is specific to *this* model — any Soar model with more than
one agent, or with a location that's revisited under different timing
conditions, will need the same three fixes.

---

## 7. Verifying it with real PRISM

Install PRISM (not bundled with this repo):
```
curl -LO https://www.prismmodelchecker.org/dl/prism-4.8.1-linux64-x86.tar.gz
tar xzf prism-4.8.1-linux64-x86.tar.gz && cd prism-4.8.1-linux64-x86 && ./install.sh
```
Then, because this model's clock bounds are all non-strict integer ticks
and PRISM's native PTA "games" engine only supports reachability (`F`), use
the **digital clocks** engine (which supports full PCTL, including `G`):
```
prism prism/train_gate.pm prism/train_gate.pctl -ptamethod digital
```
`prism/train_gate.pctl` mirrors the two UPPAAL queries already verified for
this model in `Uppaal/Uppaal_version_of_Train_Gate.xml` (see the table in
`SOURCE_README.md`), plus a deadlock/timelock sanity check:

| Property | UPPAAL result | PRISM result (this file) |
|---|---|---|
| `A[] not deadlock` | ✅ satisfied | `Pmax=? [G true]` = **1.0** |
| `A[] (Train.In imply Gate.Down)` | ✅ satisfied | `Pmax=? [G (position=2=>gate_position=1)]` = **1.0** |
| `A[] (Train.Near imply Gate.Down)` | ❌ not satisfied (by design — the gate closes after the approach is processed, not instantly) | `Pmax=? [G (position=1=>gate_position=1)]` = **0.0** |

The independently-built PRISM PTA model reproduces the same verification
results as the reference UPPAAL model — good evidence the translation (with
the fixes and hand-assembly steps above) is faithful, not just
syntactically valid.

(`Pmax=?` rather than UPPAAL-style `A[]`/`P>=1[...]`: PRISM's PTA engines
only accept `Pmin=?`/`Pmax=?` queries. Every transition here is
deterministic given the current state and clock, so `Pmin` and `Pmax`
agree, and a result of 1 means "always holds" — read it the same way as
`A[]`.)

---

## 8. Files in this example

```
examples/train-gate/
├── SOURCE_README.md              # original project's README (timing tables, etc.)
├── agents/                       # the Soar source (unmodified, plus load_v2.soar)
├── Uppaal/                       # the reference UPPAAL timed-automata model
├── config/*_pta_config.json      # PTA configs used to translate each agent
├── prism/
│   ├── controller.pm, train.pm, gate.pm   # raw translator output, one per agent
│   ├── train_gate.pm             # hand-composed, fully verified 3-module model
│   └── train_gate.pctl           # properties, verified against train_gate.pm
└── TRANSLATION_WALKTHROUGH.md     # this file
```
