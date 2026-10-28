"""Category definitions for the synthetic lab-result dataset.

Each builder returns a Case: the subject result, optional earlier results for the same patient,
optional sample-quality indices and an optional free-text note. All values are synthetic.
"""
from dataclasses import dataclass, field

CLEAR_CRITICAL = "clear-critical"
CONTEXTUAL_CRITICAL = "contextual-critical"
EXPLAINABLE_FALSE_CRITICAL = "explainable-false-critical"
ACUTE_DROP_IN_RANGE = "acute-drop-in-range"
SAMPLE_PROBLEM = "sample-problem"
AMBIGUOUS = "ambiguous"
RECOLLECT = "recollect"
NORMAL = "normal"

CATEGORIES = (
    CLEAR_CRITICAL,
    CONTEXTUAL_CRITICAL,
    EXPLAINABLE_FALSE_CRITICAL,
    ACUTE_DROP_IN_RANGE,
    SAMPLE_PROBLEM,
    AMBIGUOUS,
)

# The eight categories of the evaluation dataset (research R8 of feature 4). The six above keep their builders for the
# committed sample set; the evaluation profile swaps in a bounded ambiguous builder and adds recollect and normal.
EVALUATION_CATEGORIES = (
    CLEAR_CRITICAL,
    CONTEXTUAL_CRITICAL,
    EXPLAINABLE_FALSE_CRITICAL,
    ACUTE_DROP_IN_RANGE,
    SAMPLE_PROBLEM,
    RECOLLECT,
    AMBIGUOUS,
    NORMAL,
)

# The decision a clinician following the synthetic policy expects, assigned by construction (never by a model).
# A result critical by the rule table is expected CRITICAL even with a sample problem or a stable history (P-1, P-2).
EXPECTED = {
    CLEAR_CRITICAL: "CRITICAL",
    CONTEXTUAL_CRITICAL: "CRITICAL",
    EXPLAINABLE_FALSE_CRITICAL: "CRITICAL",
    ACUTE_DROP_IN_RANGE: "CRITICAL",
    SAMPLE_PROBLEM: "CRITICAL",
    RECOLLECT: "RECOLLECT",
    AMBIGUOUS: "NEEDS_REVIEW",
    NORMAL: "NON_CRITICAL",
}

# Reference table for the synthetic analytes: code (LOINC), name, unit, normal range, critical limits.
ANALYTES = {
    "K": dict(code="2823-3", name="Potassium", unit="mmol/L", low=3.5, high=5.1, crit_low=2.5, crit_high=6.5, decimals=1),
    "GLU": dict(code="2345-7", name="Glucose", unit="mg/dL", low=70, high=99, crit_low=40, crit_high=500, decimals=0),
    "HGB": dict(code="718-7", name="Hemoglobin", unit="g/dL", low=12.0, high=17.0, crit_low=7.0, crit_high=20.0, decimals=1),
    "NA": dict(code="2951-2", name="Sodium", unit="mmol/L", low=136, high=145, crit_low=120, crit_high=160, decimals=0),
}

# Hemolysis index above which a potassium result is considered unreliable.
HEMOLYSIS_LIMIT = 100


@dataclass
class Case:
    category: str
    analyte: str
    value: float
    history: list = field(default_factory=list)  # (hours before the subject result, value)
    indices: dict = field(default_factory=dict)  # sample-quality index code -> value
    note: str = ""


def _round(analyte, value):
    return round(value, ANALYTES[analyte]["decimals"])


def _normal_mid(analyte):
    spec = ANALYTES[analyte]
    return (spec["low"] + spec["high"]) / 2


def clear_critical(rng, analyte):
    spec = ANALYTES[analyte]
    if rng.random() < 0.5:
        value = spec["crit_high"] * rng.uniform(1.05, 1.35)
    else:
        value = spec["crit_low"] * rng.uniform(0.6, 0.95)
    return Case(CLEAR_CRITICAL, analyte, _round(analyte, value))


def contextual_critical(rng, analyte):
    spec = ANALYTES[analyte]
    if analyte == "HGB":
        value = spec["crit_low"] * rng.uniform(1.03, 1.12)
    else:
        value = spec["crit_high"] * rng.uniform(0.93, 0.99)
    prior = _normal_mid(analyte) * rng.uniform(0.97, 1.03)
    return Case(CONTEXTUAL_CRITICAL, analyte, _round(analyte, value), history=[(rng.randint(10, 14), _round(analyte, prior))])


def explainable_false_critical(rng, analyte="K"):
    spec = ANALYTES["K"]
    value = spec["crit_high"] * rng.uniform(1.0, 1.08)
    history = [(24 * n, _round("K", rng.uniform(6.2, 6.9))) for n in (1, 2, 3)]
    return Case(EXPLAINABLE_FALSE_CRITICAL, "K", _round("K", value), history=history, note="Synthetic note: scheduled dialysis patient, values stable for days.")


def acute_drop_in_range(rng, analyte="HGB"):
    value = rng.uniform(7.5, 9.5)
    prior = value + rng.uniform(3.5, 5.0)
    return Case(ACUTE_DROP_IN_RANGE, "HGB", _round("HGB", value), history=[(rng.randint(12, 20), _round("HGB", prior))])


def sample_problem(rng, analyte="K"):
    value = ANALYTES["K"]["crit_high"] * rng.uniform(1.02, 1.14)
    index = rng.randint(HEMOLYSIS_LIMIT + 50, 400)
    return Case(SAMPLE_PROBLEM, "K", _round("K", value), indices={"HEMOLYSIS_INDEX": index}, note="Synthetic note: hemolyzed sample.")


def ambiguous(rng, analyte="K"):
    value = rng.uniform(6.4, 6.6)
    prior = rng.uniform(5.8, 6.2)
    index = rng.randint(70, HEMOLYSIS_LIMIT - 1)
    return Case(AMBIGUOUS, "K", _round("K", value), history=[(rng.randint(18, 22), _round("K", prior))], indices={"HEMOLYSIS_INDEX": index})


def recollect(rng, analyte="K"):
    """Elevated potassium that is not critical by rule, with a high hemolysis index: a new sample is advised."""
    value = rng.uniform(5.5, 6.3)
    index = rng.randint(HEMOLYSIS_LIMIT + 50, 400)
    return Case(RECOLLECT, "K", _round("K", value), indices={"HEMOLYSIS_INDEX": index}, note="Synthetic note: hemolyzed sample.")


def ambiguous_bounded(rng, analyte="K"):
    """Near the critical limit but below it, earlier results elevated, borderline hemolysis: a person decides."""
    value = rng.uniform(6.2, 6.44)
    prior = rng.uniform(5.8, 6.2)
    index = rng.randint(70, HEMOLYSIS_LIMIT - 1)
    return Case(AMBIGUOUS, "K", _round("K", value), history=[(rng.randint(18, 22), _round("K", prior))], indices={"HEMOLYSIS_INDEX": index})


def normal(rng, analyte):
    """Inside the normal range, no sample flags, no history."""
    spec = ANALYTES[analyte]
    margin = (spec["high"] - spec["low"]) * 0.1
    return Case(NORMAL, analyte, _round(analyte, rng.uniform(spec["low"] + margin, spec["high"] - margin)))


BUILDERS = {
    CLEAR_CRITICAL: (clear_critical, tuple(ANALYTES)),
    CONTEXTUAL_CRITICAL: (contextual_critical, tuple(ANALYTES)),
    EXPLAINABLE_FALSE_CRITICAL: (explainable_false_critical, ("K",)),
    ACUTE_DROP_IN_RANGE: (acute_drop_in_range, ("HGB",)),
    SAMPLE_PROBLEM: (sample_problem, ("K",)),
    AMBIGUOUS: (ambiguous, ("K",)),
}


# Builders of the evaluation profile: the five shared ones, the bounded ambiguous builder, recollect and normal.
EVALUATION_BUILDERS = {
    CLEAR_CRITICAL: BUILDERS[CLEAR_CRITICAL],
    CONTEXTUAL_CRITICAL: BUILDERS[CONTEXTUAL_CRITICAL],
    EXPLAINABLE_FALSE_CRITICAL: BUILDERS[EXPLAINABLE_FALSE_CRITICAL],
    ACUTE_DROP_IN_RANGE: BUILDERS[ACUTE_DROP_IN_RANGE],
    SAMPLE_PROBLEM: BUILDERS[SAMPLE_PROBLEM],
    RECOLLECT: (recollect, ("K",)),
    AMBIGUOUS: (ambiguous_bounded, ("K",)),
    NORMAL: (normal, tuple(ANALYTES)),
}
