# How much labelling does landscape optimization need?

**tl;dr** How good? With ~50 labels the rig closes 85% of
the gap to the best row on the median dataset (RQ0). How
fast? 50 labels beat 20 on 57% of datasets, budgets past
~40 are unspendable, and a full 20-repeat study of one
dataset costs about a quarter of a CPU second (RQ1). How
simple? Random labelling ties active 67% of the time and
the rest splits almost evenly - on this corpus, at this
budget, clever labelling buys nothing reliable (RQ2).

## Why active learning?

In many engineering problems the x values are cheap but the
y values are dear: running a benchmark, compiling a config,
polling a focus group, waiting weeks for a build to fail.
So the real question is not "how good is the model?" but
"how few labels buy a good answer?" Active learning attacks
this by letting the model-so-far choose which example to
label next, spending the budget where it expects to learn
the most.

The active method here is a landscape sampler in the
FASTMAP family: project unlabelled rows onto the line
joining the two most distant labelled points (found via the
x-distance `distx`), orient that line by the labelled y
values so one pole is "good", then cull the third of the
pool projecting nearest the bad pole. Label a few more,
re-project, cull again - the pool shrinks geometrically
toward the good region, and only labelled rows are ever
scored. Random sampling is the control.

## Method

**Data.** 129 CSV files from `../optimiz` (config spaces,
process models, HPO logs, misc tabular). Column names code
their role: leading uppercase = numeric; trailing `+`/`-` =
goal to maximize/minimize; trailing `X` = ignore. Cells
holding `?` are missing. Files larger than 1024 rows are
randomly sampled down (`--cap`).

**Task.** Multi-objective row selection: find rows near the
ideal point. A row's quality is `disty` - the p-norm (p=2)
distance from its normalized goal values to best
(0 = ideal, 1 = worst).

**Rig (`holdout`).** Per repeat: shuffle rows, split 50:50
into train and test. A labeller inspects at most
`--budget - --check` training rows. A regression tree
(min leaf 3, max depth 4) is fit to the labelled rows'
`disty`. The `--check = 5` test rows with the best predicted
leaves are "bought"; the rig returns the truly best of
those. Score = `wins`: percent of the gap to the dataset's
best row that the pick closes (100 = optimal, 0 = median,
clamped at +/-100).

**Comparisons.** Per dataset, 20 paired repeats per arm
(repeat k reseeds both arms with `seed + k`). Delta = 0 if
the two win-distributions are statistically
indistinguishable - Cohen (d <= 0.35) and Cliff's delta
(<= 0.195) and Kolmogorov-Smirnov (95%) must all agree -
else `mean(win(a)) - mean(win(b))`.

Everything is deterministic (own 16807 LCG) and reproduces
bit-identically on SBCL and CLISP. Rerun: `make holdouts`
(RQ0), `make budgets` (RQ1), `make deltas` (RQ2).

**Get the code and data.** One source file, one data repo:

    git clone https://github.com/aiez/lithp
    git clone https://github.com/aiez/optimiz
    cd lithp/sandbox
    sbcl --script ezr2.lisp -h        # options, tests
    sbcl --script ezr2.lisp --all     # unit tests, ~0.1s
    sbcl --script ezr2.lisp --study   # the studies, ~1s

The data repo must sit beside `lithp` (paths default to
`../../optimiz/*.csv`); any CSV following the header
conventions above also works via `--file`.

## RQ0: how good are our optimizers?

Before comparing variants, check the rig finds anything at
all. `wins` calibrates each dataset: 100 = the pick equals
the best row in the data, 0 = no better than the median
row, negative = worse than median.

`mu(win)`, active labelling, budget 50, 20 repeats,
129 datasets (one `*` = 3 datasets):

```
[  0, 10)    0%
[ 10, 20)    2%  *
[ 20, 30)    2%  *
[ 30, 40)    2%  *
[ 40, 50)    6%  ***
[ 50, 60)    4%  **
[ 60, 70)   17%  ********
[ 70, 80)    9%  ****
[ 80, 90)   18%  ********
[ 90,100]   40%  *****************
```

Quartiles: min 16, q1 66, median 85, q3 96, max 100.

**Answer:** good. With only ~45 labels plus 5 checked test
rows, the median dataset closes 85% of the gap between its
median and best row; 39% of datasets close 90% or more.
No dataset scores below zero (never worse than guessing).
The stragglers (two datasets under 20) are rugged or noisy
landscapes worth separate study.

## RQ1: how fast? (budget and runtime)

Speed here has two currencies: labels spent (the dear
resource) and CPU spent (the cheap one).

### Labels

If labels did not matter, active learning would be a
solution looking for a problem.

`mu(win(budget=50)) - mu(win(budget=20))`, active labelling,
20 repeats, 129 datasets (one `*` = 3 datasets):

```
[-15,-10)    1%  *
[-10, -5)    2%  *
[ -5,  0)    2%  *
   ties=0   39%  *****************
[  0,  5)   12%  ******
[  5, 10)   18%  ********
[ 10, 15)   11%  *****
[ 15, 20)   10%  *****
[ 20, 25)    5%  **
[ 25, 30)    1%  *
```

Budget 50 beats budget 20 on 73/129 datasets (57%), by up
to +29 wins; it loses on 6 (worst -11). Labels buy real
performance - the problem is not trivial.

One caveat found while testing the other direction: budget
200 vs 50 ties on 129/129 datasets - *bitwise* identically,
not just statistically. The culling loop (`keepf 0.66`,
stop when pool < 2x leaf) self-terminates after ~40 labels,
so any budget >= 50 is never spent. The interesting budget
range for this sampler is 10-50; beyond that, extra budget
is unreachable by construction.

### Runtime

Measured on one laptop core (SBCL): one holdout (label,
build tree, buy 5 test rows) costs ~10ms on a 1024-row
dataset. One full study cell - load a dataset, 20 repeated
holdouts - costs 0.3s on auto93, ~0.25 CPU-seconds
typical. The entire RQ2 sweep (129 datasets x 20 repeats
x 2 treatments) runs in under 2 minutes wall on 10 cores.
The only slow datasets are load-dominated: Scrum100k spends
~9s parsing 100k CSV rows before sampling its 1024.

**Answer:** in labels, budget matters strongly up to
~40-50, past which this sampler cannot spend more; in CPU,
the method is effectively free - milliseconds per
optimization, so runtime never limits the study design.

## RQ2: how simple? (compare with random)

`mu(win(active)) - mu(win(random))`, budget 50, 20 repeats,
129 datasets:

```
[-15,-10)    3%  **
[-10, -5)    4%  **
[ -5,  0)    8%  ****
   ties=0   67%  *****************************
[  0,  5)    9%  ****
[  5, 10)    5%  **
[ 10, 15)    4%  **
[ 15, 20)    1%  *
[ 20, 25)    0%
[ 25, 30)    0%
```

**Answer:** yes. Active and random tie on 67% of datasets,
and the remainder splits almost evenly (23 active, 19
random) with symmetric tails (+16.8 vs -16.4). An earlier
implementation of the active sampler showed a 2.4x win
rate for active; two reimplementations of the same design
both erased that edge, suggesting it was an implementation
accident, not the method. At this budget, on this corpus,
random labelling is as good as the FASTMAP-style sampler -
and far simpler.

## Aside: which projection anchors?

A port ambiguity became an experiment. ezr2 projects the
pool onto poles chosen from labels *still in the pool*
(culled labels stop anchoring); an earlier lisp rewrite
anchored on *all* labels (a culled bad-pole label keeps
orienting the line). Which matters? Per dataset, 20 paired
repeats each way (`--anchor`; delta = pool minus all):

```
[-15,-10)    3%  **
[-10, -5)    3%  **
[ -5,  0)    6%  ***
   ties=0   73%  ********************************
[  0,  5)    9%  ****
[  5, 10)    5%  **
[ 10, 15)    1%  *
[ 15, 20)    1%  *
```

73% ties; the remainder split 19-16 with both tails near
+/-15. Neither policy dominates; anchor lists never exceed
~45 rows so neither is faster. Since the result is a tie,
the code keeps the *simpler* policy (all labels anchor;
no survivor bookkeeping), noting the divergence from ezr2
here.

## Threats to validity

Single sampler (one FASTMAP-style method), single tree
learner, fixed knobs (leaf 3, depth 4, grow 4, keepf 0.66),
20 repeats, and the `same` gate is conservative (three
tests must all reject). Different budgets interact with the
cull schedule (see RQ1 caveat); results may differ for
samplers that can actually spend a larger budget.
