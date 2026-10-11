"""Operate registered dual-backend packages inside the existing UCAgent desktop."""

import re
import tkinter as tk
from tkinter import ttk
from uuid import uuid4

from .client import collection, segment
from .i18n import tr
from .views import BaseView
from .widgets import Table, TextBox


def package_route(identifier):
    """Validate an opaque registered package and explicit backend before navigation."""
    package, separator, backend = str(identifier).rpartition(":")
    if not separator or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,95}", package) or backend not in ("sby", "formalmc"):
        raise ValueError(tr("portable_bad_route"))
    return package, backend


class PortableFormalPackages(BaseView):
    """List server-registered packages without importing files or dispatching tools."""

    def __init__(self, parent, app, identifier=None):
        """Build the package list and direct SBY/FormalMC entry buttons."""
        super().__init__(parent, app, identifier)
        ttk.Label(self, text=tr("portable_intro"), wraplength=1000, style="Hint.TLabel").pack(fill="x", pady=(0, 12))
        bar = ttk.Frame(self)
        bar.pack(fill="x", pady=(0, 10))
        for backend in ("sby", "formalmc"):
            ttk.Button(bar, text=tr("portable_open_" + backend), command=lambda chosen=backend: self.open(chosen)).pack(side="left", padx=(0, 10))
        self.table = Table(self, [("title", "project_name", 400), ("id", "ID", 260)], on_open=lambda: self.open("sby"))
        self.table.pack(fill="both", expand=True)
        self.empty = ttk.Label(self, style="Hint.TLabel")
        self.empty.pack(fill="x", pady=8)

    def refresh(self):
        """Read registered packages from the configured execution service."""
        self.app.io(self, lambda: collection(self.client.call("/portable-formal")), self.render, self.failed)

    def render(self, rows):
        """Display only registered packages and retain the selected identity."""
        self.loaded()
        self.table.set_rows(rows)
        if len(rows) == 1 and not self.table.selected():
            self.table.tree.selection_set(rows[0]["id"])
        self.empty.configure(text="" if rows else tr("portable_empty"))

    def open(self, backend):
        """Open one backend's controls without starting a verification run."""
        row = self.table.selected()
        if row:
            self.app.show("portable_formal_package", row["id"] + ":" + backend)


class PortableFormalView(BaseView):
    """Keep backend settings, active execution and fresh proof evidence distinct."""

    def __init__(self, parent, app, identifier=None):
        """Build backend switching and bounded execution controls in the native shell."""
        package, backend = package_route(identifier)
        super().__init__(parent, app, identifier)
        self.package_id, self.backend = package, backend
        self.endpoint = "/portable-formal/" + segment(package)
        self.row = None
        self.pending_action = False
        self.read_epoch = 0
        self.saved = {}
        self.drafts = {}
        self.run_cache = {}
        self.backend_buttons = {}
        switch = ttk.Frame(self)
        switch.pack(fill="x", pady=(0, 10))
        self.heading = ttk.Label(switch, style="Title.TLabel")
        self.heading.pack(side="left", fill="x", expand=True)
        for choice in ("sby", "formalmc"):
            button = ttk.Button(switch, text=tr("portable_switch_" + choice), command=lambda selected=choice: self.switch_backend(selected))
            button.pack(side="left", padx=(8, 0))
            self.backend_buttons[choice] = button
        self.scope = ttk.Label(self, wraplength=1050, style="Hint.TLabel")
        self.scope.pack(fill="x", pady=(0, 5))
        self.baseline = ttk.Label(self, text=tr("portable_baseline"), wraplength=1050, style="Hint.TLabel")
        self.baseline.pack(fill="x", pady=(0, 6))
        self.active_label = ttk.Label(self)
        self.active_label.pack(fill="x", pady=(0, 9))
        config = ttk.LabelFrame(self, text=tr("portable_config"), padding=12)
        config.pack(fill="x", pady=(0, 10))
        config.columnconfigure(1, weight=1)
        self.fields = {}
        for index, key in enumerate(("tool", "tool_dirs", "timeout", "sby_timeout")):
            label = ttk.Label(config, text=tr("portable_" + key))
            label.grid(row=index, column=0, sticky="w", padx=(0, 12), pady=3)
            var = tk.StringVar(self)
            entry = ttk.Entry(config, textvariable=var)
            entry.grid(row=index, column=1, sticky="ew", pady=3)
            self.fields[key] = var
            if key == "sby_timeout":
                self.sby_timeout_widgets = (label, entry)
        ttk.Label(config, text=tr("portable_config_hint"), style="Hint.TLabel").grid(row=4, column=0, columnspan=2, sticky="w", pady=(5, 0))
        controls = ttk.Frame(self)
        controls.pack(fill="x", pady=(0, 10))
        self.buttons = {}
        for action in ("save", "preflight", "self-test", "run", "cancel"):
            command = self.save_config if action == "save" else self.cancel if action == "cancel" else lambda selected=action: self.start(selected)
            button = ttk.Button(controls, text=tr("portable_" + action), command=command, style="Primary.TButton" if action == "run" else "TButton")
            button.pack(side="left", padx=(0, 8))
            self.buttons[action] = button
        self.notice = ttk.Label(self, wraplength=1050, style="Error.TLabel")
        self.notice.pack(fill="x", pady=(0, 6))
        tabs = ttk.Notebook(self)
        tabs.pack(fill="both", expand=True)
        results = ttk.Frame(tabs, padding=8)
        tabs.add(results, text=tr("portable_results"))
        self.result_label = ttk.Label(results, wraplength=1040)
        self.result_label.pack(fill="x", pady=(0, 6))
        self.result_text = TextBox(results, height=6)
        self.result_text.pack(fill="both", expand=True)
        logs = ttk.Frame(tabs, padding=8)
        tabs.add(logs, text=tr("portable_logs"))
        self.log = TextBox(logs, height=10, terminal=True)
        self.log.pack(fill="both", expand=True)
        jobs = ttk.Frame(tabs, padding=8)
        tabs.add(jobs, text=tr("portable_jobs"))
        self.jobs = Table(jobs, [("id", "name", 390), ("mode", "kind", 100), ("check_count", "portable_ck_count", 100)], height=6)
        self.jobs.pack(fill="both", expand=True)
        self.switch_backend(backend)

    def field_values(self):
        """Read a backend draft as literal strings without modifying its configuration."""
        return {key: var.get() for key, var in self.fields.items()}

    def dirty(self):
        """Report whether the selected backend has unsaved edits."""
        return self.field_values() != self.saved.get(self.backend, {})

    def switch_backend(self, backend):
        """Switch controls immediately while preserving drafts and active-run ownership."""
        if backend not in ("sby", "formalmc"):
            raise ValueError(tr("portable_bad_route"))
        if self.backend in self.saved:
            self.drafts[self.backend] = self.field_values()
        self.backend = backend
        values = self.drafts.get(backend, self.saved.get(backend, {}))
        for key, var in self.fields.items():
            var.set(values.get(key, ""))
        for choice, button in self.backend_buttons.items():
            button.configure(style="Primary.TButton" if backend == choice else "TButton")
        for widget in self.sby_timeout_widgets:
            widget.grid() if backend == "sby" else widget.grid_remove()
        self.heading.configure(text="{} · {}".format(self.row.get("title", self.package_id) if self.row else self.package_id, "SBY" if backend == "sby" else "FormalMC"))
        self.notice.configure(text="")
        self.display_run()
        self.update_controls()

    def refresh(self):
        """Refresh server facts without resubmitting actions or overwriting edited fields."""
        epoch = self.read_epoch

        def done(row):
            """Discard reads begun before an acknowledged or pending mutation."""
            if epoch == self.read_epoch:
                self.render(row)
            else:
                self.refresh()

        self.app.io(self, lambda: self.client.call(self.endpoint), done, self.failed)

    def render(self, row):
        """Merge clean settings only and keep historical baselines separate from fresh runs."""
        self.loaded()
        if self.backend in self.saved:
            self.drafts[self.backend] = self.field_values()
        self.row = row
        for backend in ("sby", "formalmc"):
            config = row["configs"][backend]
            values = {"tool": str(config.get("tool") or ""), "tool_dirs": ";".join(config.get("tool_dirs") or []),
                      "timeout": str(config.get("timeout", 1200)), "sby_timeout": str(config.get("sby_timeout") or "")}
            if backend not in self.saved or self.drafts.get(backend, self.saved[backend]) == self.saved[backend]:
                self.drafts[backend] = values.copy()
            self.saved[backend] = values
        for key, var in self.fields.items():
            var.set(self.drafts[self.backend][key])
        counts = row.get("counts", {})
        self.scope.configure(text=tr("portable_scope", jobs=len(row.get("jobs", [])), checks=counts.get("checks", 0), safety=counts.get("assert", 0), covers=counts.get("cover", 0), assumptions=counts.get("assume", 0)))
        self.jobs.set_rows([dict(job, check_count=job.get("check_count", len(job["ck_ids"]) if "ck_ids" in job else "--")) for job in row.get("jobs", [])])
        self.heading.configure(text="{} · {}".format(row.get("title", self.package_id), "SBY" if self.backend == "sby" else "FormalMC"))
        self.update_controls()
        self.display_run()
        latest = row["backends"][self.backend].get("latest_run")
        if latest:
            run_id, backend = latest["id"], self.backend
            self.app.io(self, lambda: self.client.call(self.endpoint + "/runs/" + segment(run_id)),
                        lambda result: self.loaded_run(backend, run_id, result), self.failed, key="run:" + run_id)
        self.poll()

    def loaded_run(self, backend, run_id, record):
        """Cache bounded evidence without allowing a stale response to replace another run."""
        self.run_cache[run_id] = record
        latest = (self.row or {}).get("backends", {}).get(backend, {}).get("latest_run")
        if self.backend == backend and latest and latest["id"] == run_id:
            self.display_run()

    def display_run(self):
        """Show fresh results for the selected backend, never infer a proof from execution."""
        latest = (self.row or {}).get("backends", {}).get(self.backend, {}).get("latest_run")
        if not latest:
            self.result_label.configure(text=tr("portable_not_run", backend="SBY" if self.backend == "sby" else "FormalMC"))
            self.result_text.set("")
            self.log.set("")
            return
        record = self.run_cache.get(latest["id"], latest)
        self.result_label.configure(text=tr("portable_run_state", backend=record["backend"], action=tr("portable_" + record["action"]), status=tr(record["status"]), run=record["id"]))
        result = record.get("result")
        if record["action"] in ("preflight", "self-test"):
            summary = tr("portable_check_not_proof")
        elif record.get("full_suite_passed") is True and isinstance(result, dict) and result.get("full_suite_passed") is True and result.get("status") == "passed":
            counts = result.get("counts", {})
            summary = tr("portable_full_pass", proven=counts.get("proven", 0), covered=counts.get("covered", 0), assumptions=counts.get("assumption", 0))
        else:
            summary = tr("portable_not_full_pass")
        self.result_label.configure(text=self.result_label.cget("text") + "\n" + summary)
        self.result_text.set(result if result is not None else {"status": record["status"], "diagnostic": record.get("diagnostic") or record.get("error") or tr("portable_no_result")})
        self.log.set(record.get("log") or "")

    def update_controls(self):
        """Prevent duplicate launches across both backends while keeping switching available."""
        active = (self.row or {}).get("active_run")
        self.active_label.configure(text=tr("portable_active", package=active.get("package_id", self.package_id), backend=active["backend"], action=tr("portable_" + active["action"]), run=active["id"]) if active else tr("portable_idle"))
        for name, button in self.buttons.items():
            enabled = bool(self.row) and not self.pending_action and (bool(active) if name == "cancel" else not active)
            if name == "self-test" and self.backend == "sby":
                enabled = False
            if name == "cancel" and active and active.get("package_id", self.package_id) != self.package_id:
                enabled = False
            button.configure(state="normal" if enabled else "disabled")

    def save_config(self):
        """Validate and save only the selected backend's settings with revision protection."""
        if not self.row or self.pending_action or self.row.get("active_run"):
            return
        backend, submitted = self.backend, self.field_values()
        try:
            config = {"tool": submitted["tool"].strip() or ("sby" if backend == "sby" else "FormalMC"), "tool_dirs": [value.strip() for value in submitted["tool_dirs"].split(";") if value.strip()], "timeout": int(submitted["timeout"])}
            if not 1 <= config["timeout"] <= 604800:
                raise ValueError()
            if backend == "sby" and submitted["sby_timeout"].strip():
                config["sby_timeout"] = int(submitted["sby_timeout"])
                if not 1 <= config["sby_timeout"] <= 604800:
                    raise ValueError()
        except ValueError:
            self.notice.configure(text=tr("portable_bad_timeout"))
            return
        body = {"backend": backend, "config": config, "revision": self.row["revision"]}
        self.pending_action = True
        self.read_epoch += 1
        self.update_controls()

        def done(row):
            """Accept the saved revision while retaining edits typed during the request."""
            current = self.field_values() if backend == self.backend else self.drafts.get(backend)
            if current == submitted:
                self.drafts[backend] = self.saved[backend].copy()
                if backend == self.backend:
                    for key, value in self.drafts[backend].items():
                        self.fields[key].set(value)
            self.pending_action = False
            self.read_epoch += 1
            self.render(row)
            self.notice.configure(text=tr("portable_saved", backend=backend))

        if not self.app.io(self, lambda: self.client.call(self.endpoint + "/config", "POST", body), done, self.action_failed, key="action"):
            self.pending_action = False
            self.update_controls()

    def start(self, action):
        """Dispatch an explicit action against the selected, saved backend exactly once."""
        if action not in ("preflight", "self-test", "run") or not self.row or self.pending_action or self.row.get("active_run"):
            return
        if action == "self-test" and self.backend == "sby":
            return
        if self.dirty():
            self.notice.configure(text=tr("portable_save_first"))
            return
        body = {"backend": self.backend, "action": action, "revision": self.row["revision"], "request_id": uuid4().hex}
        self.pending_action = True
        self.read_epoch += 1
        self.notice.configure(text="")
        self.update_controls()
        if not self.app.io(self, lambda: self.client.call(self.endpoint + "/runs", "POST", body), self.started, self.action_failed, key="action"):
            self.pending_action = False
            self.update_controls()

    def started(self, record):
        """Record the accepted run before polling so a second click cannot duplicate it."""
        self.pending_action = False
        self.read_epoch += 1
        self.row["backends"][record["backend"]]["latest_run"] = record
        if record["status"] in ("starting", "queued", "running", "cancelling"):
            self.row["active_run"] = record
        elif self.row.get("active_run") and self.row["active_run"]["id"] == record["id"]:
            self.row["active_run"] = None
        self.run_cache[record["id"]] = record
        self.update_controls()
        self.display_run()
        self.refresh()

    def cancel(self):
        """Cancel the actual active run regardless of which backend is being viewed."""
        active = (self.row or {}).get("active_run")
        if not active or self.pending_action or active.get("package_id", self.package_id) != self.package_id:
            return
        self.pending_action = True
        self.read_epoch += 1
        self.update_controls()
        if not self.app.io(self, lambda: self.client.call(self.endpoint + "/runs/" + segment(active["id"]) + "/cancel", "POST", {}), self.started, self.action_failed, key="action"):
            self.pending_action = False
            self.update_controls()

    def action_failed(self, error):
        """Expose the real failure and reconcile read-only state without retrying writes."""
        self.pending_action = False
        self.read_epoch += 1
        self.notice.configure(text=str(error))
        self.update_controls()
        self.refresh()

    def failed(self, error):
        """Retain draft configuration and retry only read-only state on connection failure."""
        super().failed(error)
        self.poll()
