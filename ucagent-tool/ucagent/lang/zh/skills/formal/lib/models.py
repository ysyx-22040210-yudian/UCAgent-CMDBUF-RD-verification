"""Structured records shared by the guided FormalMC and SBY workflows."""

from pydantic import BaseModel, ConfigDict, Field, model_validator
from typing import List, Optional, Dict, Union, Any, Literal


class NativeInputMapping(BaseModel):
    """Name a fixed reviewed monitor-removal transform, never arbitrary executable code."""

    model_config = ConfigDict(extra="forbid")
    session_source: str = Field(min_length=1, max_length=512)
    transform: Literal["strip_cmdbuf_monitor"]


class NativeBinding(BaseModel):
    """Select exactly one signed platform property and bind its DUT inputs to this session."""

    model_config = ConfigDict(extra="forbid")
    run_id: str = Field(min_length=1, max_length=100, pattern=r"^[A-Za-z0-9_.-]+$")
    property_id: str = Field(min_length=1, max_length=2048)
    source: str = Field(min_length=1, max_length=512)
    source_sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    mode: Literal["prove", "bmc", "cover"]
    expected_kind: Literal["assert", "cover"]
    input_map: Dict[str, Union[str, NativeInputMapping]] = Field(min_length=1)
    scope: Literal["end_to_end", "local_invariant", "reachability"]
    alias_of: Optional[str] = None
    alias_justification: str = ""
    supporting_ck_ids: List[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_mode(self):
        """Prevent cover execution from being represented as a safety proof."""
        if (self.mode == "cover") != (self.expected_kind == "cover"):
            raise ValueError("native_binding.mode must match expected_kind")
        if self.alias_of and (not self.alias_of.startswith("CK-") or len(self.alias_justification.strip()) < 20):
            raise ValueError("A shared native property requires alias_of CK- and an explicit alias_justification")
        return self

class CheckPoint(BaseModel):
    """Preserve requirement traceability and choose a real guided or native obligation."""

    model_config = ConfigDict(extra="forbid")
    id: str
    style: str
    description: str
    requirements: List[str] = Field(default_factory=list)
    kind: Optional[Literal["environment", "safety", "cover", "contract"]] = None
    expected_behavior: str = ""
    formal_obligation: str = ""
    existing_evidence: List[Dict[str, Any]] = Field(default_factory=list)
    existing_evidence_keys: List[str] = Field(default_factory=list)
    spec_basis: str = ""
    evidence_gap: str = ""
    fault_ids: List[str] = Field(default_factory=list)
    implementation_status: str = ""
    proof_status: str = ""
    verification_route: Literal["guided", "native"] = "guided"
    native_binding: Optional[NativeBinding] = None
    sva_body: Optional[str] = Field(None, description="Authoritative property body; generated HDL is read-only")
    sby_guard: str = Field("1'b1", description="Explicit native-SBY sampling enable expression; no implicit reset disable")
    sby_trigger: str = Field("1'b1", description="Reachability witness expression, not a vacuity proof")

class FunctionPoint(BaseModel):
    id: str
    name: str = ""
    description: str = ""
    check_points: List[CheckPoint] = []

class FunctionGroup(BaseModel):
    id: str
    name: str = ""
    description: str = ""
    functions: List[FunctionPoint] = []

class FormalSpec(BaseModel):
    parameters: Optional[Dict[str, Union[int, str]]] = Field(None, description="Global parameters like WIDTH, NUM_PORTS")
    whitebox_signals: Optional[List[str]] = Field(None, description="Extra signal declarations for whitebox verification (e.g. 'logic [31:0] state_r')")
    function_groups: List[FunctionGroup] = []

class IterationEntry(BaseModel):
    """One normalized FormalMC execution summary."""

    timestamp: str
    pass_count: int
    fail_count: int
    tt_count: int
    cover_pass: int
    cover_fail: int
    undecided_count: int = 0

class RunResults(BaseModel):
    """Auto-collected layer: Automatically overwritten by Checker execution"""
    timestamp: str
    log_hash: str
    stats: Dict[str, int]
    failing_properties: List[str]
    tt_properties: List[str]
    undecided_properties: List[str] = []
    uncovered_signals: List[str] = []
    iteration_history: List[IterationEntry] = []

class AnalysisEntry(BaseModel):
    """Manual analysis layer: Filled by LLM, Checker only appends, never overwrites"""
    id: str
    prop_name: str
    analysis: str = Field("[LLM-TODO]", description="Detailed analysis process")
    root_cause: Optional[str] = Field(None, description="TT: Analysis root cause")
    action: Optional[str] = Field(None, description="TT: Action: ACCEPTED, FIXED")
    action_detail: str = ""
    related_assume: Optional[str] = None
    prop_type: Optional[str] = None
    sva_code: Optional[str] = None
    resolution: Optional[str] = Field(None, description="FA: Resolution: RTL_BUG, ENV_FIXED, etc.")

class BugEntry(BaseModel):
    id: str
    property: str
    ck_id: str = "[LLM-TODO]"
    fg_id: str = "[LLM-TODO]"
    fc_id: str = "[LLM-TODO]"
    rtl_file: str = "[LLM-TODO]"
    rtl_line: int = 0
    description: str = "[LLM-TODO]"
    root_cause: str = "[LLM-TODO]"
    trigger: str = "[LLM-TODO]"
    expected: str = "[LLM-TODO]"
    actual: str = "[LLM-TODO]"
    fix: str = "[LLM-TODO]"
    severity: str = "[LLM-TODO]"
    confidence: str = "[LLM-TODO]"

class AnalysisData(BaseModel):
    tt_entries: List[AnalysisEntry] = []
    fa_entries: List[AnalysisEntry] = []

class FormalRecords(BaseModel):
    dut: str
    planning: Optional[Dict[str, Any]] = None
    basic_info: Optional[Dict[str, Any]] = None
    spec: Optional[FormalSpec] = None
    run_results: Optional[RunResults] = None  # 🔵 自动层：实时反映最近一次运行结果
    analysis: Optional[AnalysisData] = None   # 🟡 分析层：LLM 填写的持久化内容
    bugs: Optional[List[BugEntry]] = None
    extra_config: Optional[Dict[str, Any]] = Field(None, description="Extra config for tool execution, e.g. TCL timeout/commands")
    summary: Optional[Dict[str, Any]] = None
