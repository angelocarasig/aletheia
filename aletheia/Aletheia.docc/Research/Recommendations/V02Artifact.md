# v02: What Changes, and Why

A research plan for improving on the v01 recommender. **Not built in the app** - a labelling tool
exists on the training-machine side; nothing here has an app counterpart yet, and v01 keeps running
throughout regardless of what happens here.

See <doc:V01Artifact> for what v01 actually is and <doc:PortPlan> for how it shipped.

## The core framing

**v02 is not meant to be a better recommender. It's meant to be a better experiment.** The v01
scoring engine compresses a large catalogue into three interpretable similarity blocks, and that
part doesn't need to change. What's weak is everything around it: a small number of preference
labels from one person across a handful of queries, evaluated with a metric that's already been
replaced twice.

Two independent research passes converged on the same idea from different angles: treat preference
capture as a small adaptive experiment, and treat the existing recommender as a feature generator
for that experiment, not as the thing being replaced. With one user, a fixed feature space, and
only a handful of tunable parameters, better experimental design matters far more here than a more
sophisticated model.

## What's ruled out, and why

Reinforcement learning - the actual problem is inferring a static preference function from sparse
observations, which is supervised preference learning, not RL; RL needs today's action to change
tomorrow's state, and this doesn't have that. Contextual bandits - formally applicable but needs
exploration traffic a personal offline app doesn't generate (one cheap idea from bandit theory is
still worth stealing, see below). LambdaMART and neural learning-to-rank - correct tools for
problems with far more independent observations than a few hundred correlated labels from one
person; at this size they'd memorise rather than generalise. Embedding retraining - out of scope by
construction, the embedding matrix is frozen and shipped. Per-tag personalised weights - too many
free parameters against too few labels, though the tag hierarchy offers a shrinkage path once a
simpler model has saturated. Manufacturing labels from cross-source agreement - agreement between
sources says something about metadata reliability, nothing about user preference, and conflating
the two is the one hard rule everything else here respects.

## Why the label count isn't the real bottleneck

The labels collected so far aren't independent observations - many judgements against one seed are
correlated through that seed's intent, so the unit of generalisation is a query, not a judgement,
which makes the effective sample size far smaller than the raw label count suggests. And absolute
ratings are the wrong instrument for a ranking problem in the first place: a relative comparison
("which of these two is closer to what I want from this seed") maps directly onto the thing being
optimised, where an absolute rating has to be converted into relative information after the fact.
A three-level "ok" rating in particular collapses several different meanings into one label and
should stop being treated as a ranking signal.

## The two-stage idea

The most useful structural idea, and what makes per-source metadata usable at all: treat the
corpus (millions of weak per-source observations about representation reliability) and the human
(a much smaller number of strong observations about actual preference) as two different learning
problems that must not be mixed. The corpus teaches how much to trust a given representation; the
human teaches what "similar" means to this particular reader. A source's tags are a noisy, partial
observation of the same underlying title rather than a second independent dataset - which reframes
"does this source's tag data help" into a per-source, per-tag precision/recall question answerable
with no user labelling at all.

This is currently blocked in this app specifically: `series_tag` carries no provenance column, so
there's no way to trace which source contributed which tag, which is what the precision/recall
question needs. Unblocking it needs a schema change (see <doc:aletheia/Schema>) adding a metadata reference
to `series_tag`, mirroring how `title` already carries one.

## The personal model, kept deliberately small

The current score is already almost a statistical model - a weighted sum of the three blocks. The
plan is to replace the hand-swept weights with a small regularized fit over pairwise comparisons
(a Bradley-Terry model), penalized toward the current hand-tuned weights rather than fit
unconstrained - safer at this sample size, and interpretable. A handful of interaction terms and a
slow, strongly-priored fit of the existing taper/decay parameters are worth having early; nothing
more flexible than that until the small model has actually saturated. One idea borrowed from bandit
theory without adopting the whole framework: a small exploration quota, sending most
recommendations from the current best model and a minority chosen because the model is genuinely
uncertain about them.

## Implicit signals: log everything, trust little

Explicit comparisons and ratings are the strongest signal; a completion or a re-read is real but
ambiguous evidence (a reader can finish a series for characters they like while the recommendation
premise is nothing like what they'd want elsewhere); a search without an open is closer to noise.
Never fold these into one blended reward number - that produces a number that looks principled and
isn't. Keep separate evidence channels and let explicit labels calibrate how much each one is
worth. Log impressions, not just interactions, since a recommendation can only be tapped if it was
shown, and position affects taps independently of quality - the fix is visibility into what was
shown and ignored, not a ranking-time correction.

## The evaluation rebuild

The most important piece, because two earlier metrics have already failed here. Four separate
label sets are needed: a training set that changes as labelling continues; a small development set
fixed early for model-selection decisions; a gold set fixed forever and never trained on, used only
for regression testing; and the unresolved (projected-seed) case judged entirely separately from
the other three. The gold set is what makes a coverage-confound result (a metric that looks
perfect because it was only ever evaluated on a tiny, cherry-picked slice of results) structurally
impossible.

Splits and resampling both need to happen by query, never by individual label, since labels from
one seed share that seed's intent and randomly mixing them leaks information across the split.
Coverage (how much of a result set was actually judged) has to be reported as a first-class metric
next to any accuracy number, not a footnote, or a high accuracy score next to almost nothing judged
reads as far more meaningful than it is.

## What's actually been found so far

A handful of concrete negative results, worth carrying even though the broader plan is still
mostly unbuilt:

- **No fixed weighting of the three blocks predicts this reader's choices on held-out data.** An
  exhaustive grid search over the block weights found an in-sample optimum that collapses to
  below-chance accuracy once evaluated on held-out queries - the signature of fitting noise, not a
  real pattern. The current preference-model phase can't proceed on the data collected so far.
- **An LLM judge doesn't work as a substitute for the reader's own labels.** Several independent
  model instances judged the same pairs the reader had already judged, blind and with sides
  randomised: agreement with the reader was moderate, but agreement with *each other* was much
  higher - a self-consistent judge that's only moderately aligned with the actual target is aimed
  at a slightly wrong thing, and that bias wouldn't be visible from any validation that draws on
  the same source. The judge only agreed with the reader where agreement was cheap (on pairs that
  weren't actually informative); on the genuinely informative disagreement cases it did
  noticeably worse. It's still useful for pre-screening obviously-dead candidates and suggesting
  candidate reason codes, just not as ground truth.
- **Every label collected so far tests refinement, not retrieval.** All of them compared candidates
  drawn from deep inside the model's own shortlist, so none of them actually tests whether the
  shortlist is better than an arbitrary mediocre result - a separate sampling strategy pairing a
  shortlist candidate against a mid-ranked one was added specifically to close this gap.
- **Repeatability of the reader's own labels is what everything else has to be interpreted
  against.** Re-asking previously-answered comparisons after a delay, with the pairing re-flipped
  so the same *side* isn't just being re-picked, measures how much of the reader's own judgement is
  noise - and that number decides whether a low held-out accuracy means the model is bad or means
  the target itself is close to as good as it can get.

## Open questions

Where preference labelling should actually happen (a separate research tool, or inside the app
itself, which has the reader's real library and context but a smaller iteration loop). Whether an
impression log belongs in the app's own database or stays a research-only artifact - either way
it's a flagged schema change. What entity-resolution precision floor the source-reliability
statistics need before they're trustworthy. And whether the v01 alias-collapse defect gets fixed
before any of this - every representation experiment inherits that ceiling until it does.
