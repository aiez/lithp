# STYLE.md — how this code gets written

Tiny functions. Beautiful code. Every change runs on SBCL and
CLISP (`sbcl --script`, `clisp -q -norc`) before it lands.
Lines fit 65 chars.

## Conventions

- **cols = lists** (dolist, push + nreverse);
  **row, rows = vectors** (O(1) `elt` by column index,
  O(1) append via `end!`, in-place sort).
- `&aux` for locals; `aif`/`it` anaphora;
  `$slot` reader macro = `(ats i 'slot)`;
  `?` macro for nested slot access.
- `add` returns the value added, so folds nest:
  `(add group (add ys (funcall y r)))`.
- Summaries are `num`/`sym` structs; behavior differences are
  CLOS methods, never type-ifs.
- Tests are `eg--*` functions run via CLI flags
  (`--all` resets the seed before each); asserts required,
  pinned to known-good numbers.

## Refactoring playbook

Applied in roughly this order when asking "can this be
simpler?":

1. **Port literally first.** Copy the reference shape
   (ezr2.py), pin tests to known numbers, verify on both
   lisps. Improve only after green.
2. **Type-if → CLOS.** `(if (sym-p x) ...)` becomes two
   defmethods. A summary struct may serve as the dispatch
   token even if its stats go unused.
3. **Generator → sink closure.** Don't collect/sort/argmin
   candidates. Pass a best-keeper closure (`best!`) into the
   generator; offer each candidate by `funcall`. O(1) memory;
   cons only on improvement.
4. **Fuse passes.** A loop already touching every row should
   accumulate the side summaries too.
5. **Helper on second use, merge on single use.** `ats!`,
   `argmin`, `end!` earned names; helpers with one caller get
   folded back in.
6. **No approximation for speed without measured need.**
   Exact "try every number" beats `--bins` sampling; the
   honest cost (one list + sort per numeric column) is
   accepted.
7. **Names track roles.** `xs`/`ys` for side summaries;
   `here`/`me` for the growing part; rename when a role
   shifts.
8. **Pinned asserts every step.** Each refactor must be a
   provable no-op: the invariant (best cut 5.88 @ Volume 183
   on auto93) held across every rewrite.
