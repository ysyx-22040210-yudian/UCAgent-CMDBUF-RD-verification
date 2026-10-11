"""Exhaustive finite occupancy model; this is not an RTL simulation."""
from collections import deque
from itertools import product
from pathlib import Path
import json

OUT = Path(__file__).resolve().parent


def invariant(occ):
    return all(v >= 0 for v in occ) and sum(max(v, 1) for v in occ) <= 9


def retire_then_ready(occ, retire_src):
    after = list(occ)
    if retire_src is not None:
        assert after[retire_src] > 0
        after[retire_src] -= 1
    shared = sum(max(v - 1, 0) for v in after)
    ready = tuple(sum(after) < 9 and (v == 0 or shared < 6) for v in after)
    return tuple(after), ready


states = {v for v in product(range(10), repeat=3) if invariant(v)}
transition_checks = 0
for occ in states:
    assert max(occ) <= 7
    for retire_src in [None] + [x for x in range(3) if occ[x] > 0]:
        after, ready = retire_then_ready(occ, retire_src)
        assert invariant(after)
        for src in range(3):
            nxt = tuple(v + int(src == x) for x, v in enumerate(after))
            assert ready[src] == invariant(nxt)
            if after[src] == 0:
                assert ready[src], ('Empty source lost reserved capacity', occ, retire_src, src)
            if ready[src]:
                assert sum(nxt) <= 9
                assert max(nxt) <= 7
                assert nxt in states
                transition_checks += 1

# Reachability under legal one-request AR and at most one R retirement per cycle.
seen = {(0, 0, 0)}
todo = deque(seen)
while todo:
    occ = todo.popleft()
    for retired in [None] + [x for x in range(3) if occ[x] > 0]:
        after, ready = retire_then_ready(occ, retired)
        for accepted in [None] + [x for x in range(3) if ready[x]]:
            nxt = tuple(v + int(accepted == x) for x, v in enumerate(after))
            assert invariant(nxt)
            if nxt not in seen:
                seen.add(nxt)
                todo.append(nxt)
assert seen == states


def bits(ready):
    return ''.join(str(int(v)) for v in reversed(ready))


examples = []
for occ, retired, expected in [
    ((7, 0, 0), None, '110'),
    ((7, 1, 0), None, '100'),
    ((7, 1, 1), None, '000'),
    ((4, 4, 0), None, '100'),
    ((7, 1, 1), 1, '010'),
    ((7, 1, 1), 0, '111'),
]:
    after, ready = retire_then_ready(occ, retired)
    assert bits(ready) == expected
    examples.append(dict(occ=list(occ), retire_src=retired, after=list(after), arready=expected))
assert max((4, 5, 0)) <= 7 and not invariant((4, 5, 0))

report = dict(
    result='PASS', model='One reserved entry per XAU plus six shared entries',
    legal_occupancy_states=len(states), reachable_occupancy_states=len(seen),
    accepted_transition_checks=transition_checks, examples=examples,
    verified=['invariant preservation', 'zero-occupancy source can accept after any legal retirement',
              'single-source maximum seven', 'same-cycle retirement and allocation',
              'per-source cap alone is insufficient'],
    limitations=['Occupancy policy model only; no RTL simulation or formal tool run',
                 'No upstream fairness assumption proved', 'Bank-window progress is a separate condition'],
)
(OUT/'capacity_policy_check.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False))
