# Feedback Iteration

How UI work gets reviewed in this project.

Before iterating on a surface that's built but looks off, fan out a panel of subagents wearing
different readers' eyes, and give them the screen as text. This finds things that rounds of
screenshot-and-tweak reliably miss - screenshot-and-tweak converges on "looks tidier," not on the
number that quietly destroys trust in the rest of the screen, the word that assigns blame to the
wrong party, or the layout constant that collapses the moment real data fills it.

## The method

1. Describe the surface as text - top to bottom, every element, its type weight and colour role,
   what's tappable and what isn't. Include the sparse state and the populated one. Don't include
   your own opinion of it, and don't name the problem you suspect - the value is in what a reader
   finds unprompted.
2. Give each agent one persona and no codebase access. A reviewer who knows the implementation
   reviews the implementation, not the surface a real reader sees.
3. Ask for a verdict, not a survey - "which one, and why" beats "here are four options." Tell them
   to be blunt.
4. Run every persona in parallel, in one message, so nothing is contaminated by another's answer.
5. Count the convergence. A finding two personas reach independently, from opposite directions, is
   worth more than a finding one of them argues well.
6. Verify before acting - panels state things about the code confidently and are sometimes wrong.

## The standing panel

Six lenses. Not all apply to every surface; pick what the screen actually risks.

| Lens | Finds |
|---|---|
| Daily reader | whether the screen serves the one job it exists for, and what they scroll past |
| UX designer | hierarchy, information architecture, platform convention |
| Complete novice | every word that assumes knowledge, every affordance that isn't one |
| Affordance and density | whether a thing looks tappable, whether its target is reachable, whether the layout still scans once it's full of real data |
| Power user | what a large library needs that a small one doesn't |
| Lapsed returner | what the surface says to someone who fell off - the loss-mechanic detector |

Add a domain specialist where a screen has one - a data-visualisation lens on a chart or heatmap
finds bin policy, empty-vs-lowest-bin separation, axis minimums, and autoscale traps that the
general panel won't.

The two most valuable lenses are the two easiest to skip. The novice finds vocabulary failures
nobody fluent can see. The lapsed returner is the only lens that reports how a screen makes
someone feel, which is the axis apps are actually deleted on.

**The affordance lens is not an accessibility lens.** A full-screen image reader doesn't live or
die on VoiceOver grouping, so the lens spends its budget on questions that survive that reframing:
does it look tappable, is the target reachable (44pt, with dead space between adjacent controls,
not a bare 16pt chevron beside a label it can be mistaken for), and does the layout survive real
data (bigger text is the cheapest stress test for all three at once).

## Deciding, not just reviewing

The same fan-out settles open design questions, with one change: ask for a commitment. Ask each
decision agent for the call, the reasoning, and the strongest argument for the option they
rejected - the rejected argument is what tells you whether the call was close.

Reviewing and deciding work best as two rounds against the same agents, not one. Round one is open
("what's wrong with this"); round two puts the candidate designs - including ones the panel itself
proposed - back in front of every lens and asks each to pick one.

Three things make round two worth its cost:

- **Feed back what got verified in between.** Round one produces claims about the code; some will
  be wrong. Handing each agent the confirmed facts before round two changes votes - an agent will
  switch away from its own round-one proposal once told a premise it was defending was wrong.
- **A proposal survives round two or it was never good.** The strongest idea from round one can
  die in round two under lenses that hadn't seen it yet - round one alone would have shipped it.
- **Ask the dissenter the question that would change its mind**, specifically and by name. A lone
  dissenting vote can come back with the exact conditional that makes the majority position safe.

Give every agent the same candidate list in the same words, and let them keep their round-one
transcript so the pick is reasoned from what they already found.

## Rules

- The panel advises; the repo decides. Where a finding contradicts a written rule, the rule is
  either wrong or the surface is - say which, in the owning doc, rather than letting them drift
  apart.
- Report convergence, not transcripts - which lenses agreed, on what, independently.
- Don't run it on trivia. It's for a surface that's built, working, and "looks off" - exactly when
  screenshots stop helping.
- Verify every claim about the code before acting on it.
- Write the finding down as a rule, in <doc:Design> if it generalises or in the owning feature doc
  if it doesn't. The point is not to re-run the panel for the same lesson.
