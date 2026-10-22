"""Read the labelled, same-cycle native properties used by this checker.

This is a deliberately small reader for our source format, not an SVA parser.
It rejects unexpected clocks, missing classifications and duplicate labels.
"""
import re

CLOCK = "@(posedge clk) disable iff (!rst_n)"
DEPENDENCIES = ("NO_REF_MODEL_PORTS", "NO_REF_MODEL_HISTORY",
                "REF_MODEL", "MODEL_SELF_CHECK")
MULTIPLICITY = {
    "E06_SUCCESS_BUSY": 8, "A_RR_BOUND": 3, "M_AGE_RANGE": 9,
    "M_CALENDAR": 9, "M_AGE_UNIQUE": 72, "C_SUCCESS_BUSY_TARGET": 16,
}
HEADER = re.compile(
    r"^[ \t]*(?P<label>\w+):[ \t]*(?P<kind>assert|assume|cover)"
    r"[ \t]+property[ \t]*\(", re.MULTILINE)


def properties(text):
    result, labels = [], set()
    for match in HEADER.finditer(text):
        level, end = 1, match.end()
        while end < len(text) and level:
            level += (text[end] == "(") - (text[end] == ")")
            end += 1
        if level or text[end:end+1] != ";":
            raise ValueError("Unterminated property: " + match["label"])
        body = text[match.end():end-1].strip()
        if not body.startswith(CLOCK):
            raise ValueError("Unexpected clock/disable: " + match["label"])
        expr = body[len(CLOCK):].strip()
        label, kind = match["label"], match["kind"]
        if label in labels:
            raise ValueError("Duplicate property label: " + label)
        labels.add(label)
        comment = text[:match.start()].rstrip().splitlines()[-1].strip()
        dependencies = [d for d in DEPENDENCIES if "[" + d + "]" in comment]
        if len(dependencies) != 1:
            raise ValueError("Missing/ambiguous classification: " + label)
        instances = 3 if re.match(r"[AMC]_XAU_", label) else MULTIPLICITY.get(label, 1)
        result.append(dict(
            kind=kind, label=label, expression=expr,
            dependency=dependencies[0], instances=instances,
            description=re.sub(r"//|\[[A-Z_]+\]", "", comment).strip(),
            line=text[:match.start()].count("\n")+1,
            end_line=text[:end+1].count("\n")+1,
            start=match.start(), end=end+1,
        ))
    if not result:
        raise ValueError("No native properties found")
    return result


def select_assertions(text, selected):
    """Select whole multiline properties; keep every assume and cover intact."""
    if selected is None:
        return text
    props = properties(text)
    missing = set(selected) - {p["label"] for p in props if p["kind"] == "assert"}
    if missing:
        raise ValueError("Unknown assertion selection: " + repr(sorted(missing)))
    for p in reversed(props):
        if p["kind"] == "assert" and p["label"] not in selected:
            block = text[p["start"]:p["end"]]
            commented = "\n".join("// Unselected: " + line for line in block.split("\n"))
            text = text[:p["start"]] + commented + text[p["end"]:]
    return text


def sampled_boolean(expression):
    """Boolean value of the same-sample obligation, for checker equivalence only."""
    if "|=>" in expression or "##" in expression:
        raise ValueError("Temporal property cannot be treated as a sampled Boolean")
    if "|->" not in expression:
        return expression
    if expression.count("|->") != 1:
        raise ValueError("Expected a single overlapping implication")
    antecedent, consequent = expression.split("|->")
    return "(!(" + antecedent.strip() + ") || (" + consequent.strip() + "))"


def lower_overlapping_implications(text):
    """Adapt only this checker's one-sample |-> to the VM read_slang frontend.

    Keep the source of record native and readable. Never lower delayed/multicycle
    SVA, or introduce implication into a cover to obtain a vacuous hit.
    """
    changes = []
    for p in reversed(properties(text)):
        expr = p["expression"]
        if "|=>" in expr or "##" in expr:
            raise ValueError("Unsupported temporal property: " + p["label"])
        if "|->" not in expr:
            continue
        if p["kind"] == "cover":
            raise ValueError("Implication is not allowed in scenario covers")
        # Current antecedents/consequents are single sampled expressions. Reject
        # temporal vocabulary rather than silently weakening a future property.
        if re.search(r"\b(first_match|throughout|within|intersect|until|s_until|"
                     r"eventually|s_eventually|nexttime|s_nexttime)\b|\[\*|\[=|\[->", expr):
            raise ValueError("Cannot Boolean-lower property: " + p["label"])
        lowered = sampled_boolean(expr)
        replacement = "%s: %s property (\n    %s\n    %s\n);" % (
            p["label"], p["kind"], CLOCK, lowered)
        text = text[:p["start"]] + replacement + text[p["end"]:]
        changes.append(dict(label=p["label"], kind=p["kind"],
                            source_expression=expr, executed_expression=lowered))
    return text, list(reversed(changes))


def instance_paths(p):
    """Stable generated paths; used only to expose checker predicate values."""
    label = p["label"]
    if label == "E06_SUCCESS_BUSY":
        return ["status_contract[%d].%s" % (g, label) for g in range(8)]
    if label == "A_RR_BOUND" or re.match(r"[AMC]_XAU_", label):
        return ["sources[%d].%s" % (g, label) for g in range(3)]
    if label in ("M_AGE_RANGE", "M_CALENDAR"):
        return ["slots[%d].%s" % (g, label) for g in range(9)]
    if label == "M_AGE_UNIQUE":
        return ["slots[%d].pairs[%d].distinct.%s" % (g, h, label)
                for g in range(9) for h in range(9) if g != h]
    if label == "C_SUCCESS_BUSY_TARGET":
        return ["bank_covers[%d].half_covers[%d].%s" % (g, h, label)
                for g in range(8) for h in range(2)]
    return [label]
