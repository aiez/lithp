# How much labelling does landscape optimization need?

**tl;dr** How good? With ~50 labels the rig closes 85% of
the gap to the best row on the median dataset (RQ0). How
fast? 50 labels beat 20 on 67% of datasets, budgets past
~40 are unspendable, and a full 20-repeat study of one
dataset costs about a quarter of a CPU second (RQ1). How
simple? Random labelling ties active 61% of the time; when
they differ, active wins twice as often and, at the
extremes, twice as big (RQ2).

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

## RQ0: how good are our optimizers?

Before comparing variants, check the rig finds anything at
all. `wins` calibrates each dataset: 100 = the pick equals
the best row in the data, 0 = no better than the median
row, negative = worse than median.

`mu(win)`, active labelling, budget 50, 20 repeats,
129 datasets (one `*` = 3 datasets):

```
[  0, 10)    1%  *
[ 10, 20)    1%  *
[ 20, 30)    0%
[ 30, 40)    4%  **
[ 40, 50)    5%  ***
[ 50, 60)    5%  **
[ 60, 70)   15%  *******
[ 70, 80)   13%  ******
[ 80, 90)   18%  ********
[ 90,100]   39%  *****************
```

Quartiles: min 4.6, q1 66, median 85, q3 97, max 100.

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
[-15,-10)    0%
[-10, -5)    0%
[ -5,  0)    2%  *
   ties=0   32%  **************
[  0,  5)   20%  *********
[  5, 10)   12%  ******
[ 10, 15)   15%  *******
[ 15, 20)   11%  *****
[ 20, 25)    8%  ****
[ 25, 30)    1%  *
```

Budget 50 beats budget 20 on 86/129 datasets (67%), by up
to +28 wins; it loses on 2 (worst -2.7). Labels buy real
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
[-15,-10)    1%  *
[-10, -5)    5%  **
[ -5,  0)    6%  ***
   ties=0   60%  **************************
[  0,  5)   17%  ********
[  5, 10)    4%  **
[ 10, 15)    6%  ***
[ 15, 20)    0%
[ 20, 25)    1%  *
[ 25, 30)    0%
```

**Answer:** mostly, yes. Active and random tie on 61% of
datasets. When they differ, active wins 2.4x as often
(36 vs 15) and its extremes reach twice as far (+21.7 best
gain vs -10.2 worst loss); the biggest gains cluster in the
binary-config / software-product-line datasets. Active
labelling rarely hurts much and sometimes helps a lot -
but random is a strong, cheap baseline almost everywhere.

## Threats to validity

Single sampler (one FASTMAP-style method), single tree
learner, fixed knobs (leaf 3, depth 4, grow 4, keepf 0.66),
20 repeats, and the `same` gate is conservative (three
tests must all reject). Different budgets interact with the
cull schedule (see RQ1 caveat); results may differ for
samplers that can actually spend a larger budget.
