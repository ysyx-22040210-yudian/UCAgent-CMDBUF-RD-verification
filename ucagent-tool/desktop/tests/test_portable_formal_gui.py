"""Real Tk contract tests for backend switching; no EDA tool or proof is simulated."""

from copy import deepcopy
import tkinter as tk
from tkinter import ttk
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

from ucagent_tk.client import ApiError
from ucagent_tk.formal import FormalSessionView
from ucagent_tk.i18n import tr
from ucagent_tk.portable_formal import PortableFormalPackages, PortableFormalView, package_route


class ControlledService:
    """Record API contracts and return explicitly synthetic GUI fixture states."""

    def __init__(self):
        """Keep each backend's settings and latest run independently addressable."""
        self.calls = []
        self.failure = None
        self.row = {"id": "test-package", "title": "GUI fixture", "revision": 1,
                    "manifest_sha256": "a" * 64,
                    "counts": {"checks": 177, "assert": 107, "cover": 65, "assume": 5},
                    "jobs": [{"id": "quota_math", "mode": "prove", "ck_ids": ["CK-1"]}],
                    "configs": {"sby": {"tool": "/tools/sby", "tool_dirs": ["/tools/bin"], "timeout": 1200, "sby_timeout": 900},
                                "formalmc": {"tool": "/tools/FormalMC", "tool_dirs": [], "timeout": 1800}},
                    "backends": {"sby": {"latest_run": None}, "formalmc": {"latest_run": None}},
                    "active_run": None}

    def call(self, path, method="GET", body=None, **kwargs):
        """Return only GUI metadata; deliberately do not execute any tool."""
        self.calls.append((path, method, deepcopy(body)))
        if self.failure and method == "POST":
            raise ApiError(self.failure)
        if path == "/portable-formal":
            return {"items": [{"id": self.row["id"], "title": self.row["title"], "session_ids": ["source-session"]}]}
        if method == "POST" and path.endswith("/config"):
            self.row["configs"][body["backend"]] = deepcopy(body["config"])
            self.row["revision"] += 1
        elif method == "POST" and path.endswith("/runs"):
            record = {"id": "new-run", "package_id": self.row["id"], "backend": body["backend"], "action": body["action"], "status": "starting", "full_suite_passed": False}
            self.row["backends"][body["backend"]]["latest_run"] = record
            self.row["active_run"] = record
            return deepcopy(record)
        elif method == "POST" and path.endswith("/cancel"):
            record = dict(self.row["active_run"], status="cancelled")
            self.row["backends"][record["backend"]]["latest_run"] = record
            self.row["active_run"] = None
            return record
        elif "/runs/" in path:
            for backend in self.row["backends"].values():
                if backend["latest_run"] and path.endswith(backend["latest_run"]["id"]):
                    return deepcopy(backend["latest_run"])
        return deepcopy(self.row)


class PortableFormalGuiTests(unittest.TestCase):
    """Check visible native widgets and actual action payloads without tool invocations."""

    def setUp(self):
        """Construct a hidden Tk application with synchronous, recorded API callbacks."""
        try:
            self.root = tk.Tk()
        except tk.TclError as exc:
            self.skipTest(str(exc))
        self.root.withdraw()
        self.service = ControlledService()
        self.notes = []
        self.app = SimpleNamespace(client=self.service, notify=self.notes.append, show=Mock(),
                                   connection=ttk.Label(self.root), message=ttk.Label(self.root))

        def immediate(owner, work, done, failed=None, **kwargs):
            """Deliver fixture callbacks on Tk's owning thread."""
            try:
                value = work()
            except Exception as exc:
                if failed:
                    failed(exc)
                else:
                    raise
            else:
                done(value)
            return True

        self.app.io = immediate
        self.view = PortableFormalView(self.root, self.app, "test-package:formalmc")
        self.view.pack(fill="both", expand=True)
        self.view.refresh()

    def tearDown(self):
        """Cancel owned timers and release the real widgets."""
        self.view.destroy()
        self.root.destroy()

    def test_existing_source_button_opens_registered_formalmc_without_post(self):
        """The existing SBY session offers one-click navigation, with no migration or run."""
        source = FormalSessionView(self.root, self.app, "source-session")
        source.row = {"revision": 7, "state": "completed", "options": {"engine": "sby"}}
        source.loaded_portable(self.service.call("/portable-formal")["items"])
        self.assertEqual(source.buttons["migrate_formalmc"].cget("text"), tr("portable_switch_formalmc"))
        source.buttons["migrate_formalmc"].invoke()
        self.app.show.assert_called_once_with("portable_formal_package", "test-package:formalmc")
        self.assertFalse(any(method == "POST" for _, method, _ in self.service.calls))
        source.destroy()

    def test_switch_both_directions_does_not_launch_or_copy_history(self):
        """Switching tabs is read-only and FormalMC starts without inherited SBY evidence."""
        sby = {"id": "old-sby", "backend": "sby", "action": "run", "status": "passed", "result": {"full_suite_passed": True}}
        self.service.row["backends"]["sby"]["latest_run"] = sby
        self.view.refresh()
        for backend in ("sby", "formalmc", "sby", "formalmc"):
            self.view.backend_buttons[backend].invoke()
            self.assertEqual(self.view.backend, backend)
        self.assertIn(tr("portable_not_run", backend="FormalMC"), self.view.result_label.cget("text"))
        self.assertEqual(self.view.result_text.get(), "")
        self.assertFalse(any(method == "POST" for _, method, _ in self.service.calls))

    def test_unsaved_configuration_survives_poll_and_backend_switch(self):
        """Polling updates evidence without discarding either backend's unsubmitted edits."""
        self.view.fields["tool"].set("/edited/FormalMC")
        self.view.backend_buttons["sby"].invoke()
        self.view.fields["timeout"].set("2345")
        self.view.refresh()
        self.view.backend_buttons["formalmc"].invoke()
        self.assertEqual(self.view.fields["tool"].get(), "/edited/FormalMC")
        self.view.refresh()
        self.view.backend_buttons["sby"].invoke()
        self.assertEqual(self.view.fields["timeout"].get(), "2345")
        self.assertEqual(self.view.fields["tool"].get(), "/tools/sby")

    def test_save_is_backend_specific_and_run_uses_saved_selected_backend(self):
        """A FormalMC edit never changes SBY, and the run request names the selected backend."""
        original_sby = deepcopy(self.service.row["configs"]["sby"])
        self.view.fields["tool"].set("/new/FormalMC")
        self.view.buttons["run"].invoke()
        self.assertEqual(self.view.notice.cget("text"), tr("portable_save_first"))
        self.view.buttons["save"].invoke()
        self.assertEqual(self.service.row["configs"]["sby"], original_sby)
        self.assertEqual(self.service.row["configs"]["formalmc"]["tool"], "/new/FormalMC")
        self.assertFalse(self.view.dirty())
        self.view.buttons["run"].invoke()
        posts = [body for path, method, body in self.service.calls if method == "POST" and path.endswith("/runs")]
        self.assertEqual(len(posts), 1)
        self.assertEqual((posts[0]["backend"], posts[0]["action"]), ("formalmc", "run"))

    def test_active_backend_does_not_change_and_second_launch_is_disabled(self):
        """An active FormalMC request cannot become SBY or be duplicated by switching."""
        self.view.buttons["preflight"].invoke()
        self.view.backend_buttons["sby"].invoke()
        self.assertEqual(self.view.row["active_run"]["backend"], "formalmc")
        self.assertIn("formalmc", self.view.active_label.cget("text"))
        self.assertEqual(str(self.view.buttons["run"].cget("state")), "disabled")
        self.view.buttons["run"].invoke()
        self.view.start("run")
        self.assertEqual(len([1 for path, method, _ in self.service.calls if method == "POST" and path.endswith("/runs")]), 1)

    def test_cancel_targets_active_backend_while_viewing_other_backend(self):
        """Cancellation addresses the running ID, regardless of the currently shown form."""
        self.view.buttons["self-test"].invoke()
        self.view.backend_buttons["sby"].invoke()
        self.view.buttons["cancel"].invoke()
        cancel = [path for path, method, _ in self.service.calls if method == "POST" and path.endswith("/cancel")]
        self.assertEqual(cancel, ["/portable-formal/test-package/runs/new-run/cancel"])
        self.assertIsNone(self.view.row["active_run"])

    def test_missing_tool_is_error_and_never_a_design_pass(self):
        """A real API failure remains visible and does not fabricate a result."""
        self.service.failure = "FormalMC executable not found"
        self.view.buttons["preflight"].invoke()
        self.assertIn("not found", self.view.notice.cget("text"))
        self.assertEqual(self.view.result_text.get(), "")
        self.assertEqual(self.view.result_label.cget("text"), tr("portable_not_run", backend="FormalMC"))
        self.assertFalse(self.view.pending_action)

    def test_preflight_success_is_labeled_as_environment_only(self):
        """An environment-check result is visibly different from complete verification."""
        record = {"id": "preflight-run", "backend": "formalmc", "action": "preflight", "status": "passed", "full_suite_passed": False}
        self.service.row["backends"]["formalmc"]["latest_run"] = record
        self.view.refresh()
        self.assertIn(tr("portable_preflight"), self.view.result_label.cget("text"))
        self.assertIn(tr("portable_no_result"), self.view.result_text.get())

    def test_pending_write_cannot_be_resubmitted(self):
        """Repeated clicks while a network write is unresolved dispatch at most once."""
        pending = []
        self.app.io = lambda owner, work, done, failed=None, **kwargs: pending.append((work, done)) or True
        self.view.start("run")
        self.view.backend_buttons["sby"].invoke()
        self.view.start("run")
        self.assertEqual(len(pending), 1)
        work, _ = pending[0]
        record = work()
        self.assertEqual(record["backend"], "formalmc")

    def test_sby_self_test_is_disabled_and_cannot_submit_directly(self):
        """SBY exposes only actions supported by the sealed runner."""
        self.view.backend_buttons["sby"].invoke()
        self.assertEqual(str(self.view.buttons["self-test"].cget("state")), "disabled")
        self.view.start("self-test")
        self.assertFalse(any(method == "POST" for _, method, _ in self.service.calls))

    def test_other_package_active_run_cannot_be_cancelled_here(self):
        """A manager-wide busy state blocks launch without cancelling an unrelated package."""
        self.service.row["active_run"] = {"id": "other-run", "package_id": "other-package", "backend": "sby", "action": "run", "status": "running"}
        self.view.refresh()
        self.assertIn("other-package", self.view.active_label.cget("text"))
        self.assertEqual(str(self.view.buttons["cancel"].cget("state")), "disabled")
        self.view.cancel()
        self.assertFalse(any(method == "POST" for _, method, _ in self.service.calls))

    def test_old_poll_cannot_clear_new_active_run(self):
        """A delayed GET from before launch cannot reopen the run button."""
        pending = []
        self.app.io = lambda owner, work, done, failed=None, **kwargs: pending.append((work, done)) or True
        self.view.refresh()
        old_work, old_done = pending[0]
        old_row = old_work()
        self.view.start("run")
        run_work, run_done = pending[1]
        run_done(run_work())
        old_done(old_row)
        self.assertEqual(self.view.row["active_run"]["id"], "new-run")
        self.assertEqual(str(self.view.buttons["run"].cget("state")), "disabled")

    def test_full_pass_requires_actual_complete_report(self):
        """A passed process or a record flag alone does not label the DUT as fully proved."""
        record = {"id": "proof-run", "backend": "formalmc", "action": "run", "status": "passed", "full_suite_passed": True}
        self.service.row["backends"]["formalmc"]["latest_run"] = record
        self.view.refresh()
        self.assertIn(tr("portable_not_full_pass"), self.view.result_label.cget("text"))
        record["result"] = {"status": "passed", "full_suite_passed": True, "counts": {"proven": 107, "covered": 65, "assumption": 5}}
        self.view.refresh()
        self.assertIn(tr("portable_full_pass", proven=107, covered=65, assumptions=5), self.view.result_label.cget("text"))

    def test_registry_errors_never_downgrade_known_complete_package(self):
        """Transient registry errors preserve known links or disable unknown navigation."""
        source = FormalSessionView(self.root, self.app, "source-session")
        source.row = {"revision": 7, "state": "completed", "options": {"engine": "sby"}}
        source.portable_unavailable(ApiError("network unavailable"))
        self.assertEqual(str(source.buttons["migrate_formalmc"].cget("state")), "disabled")
        source.loaded_portable(self.service.call("/portable-formal")["items"])
        source.portable_unavailable(ApiError("HTTP 503: service unavailable"))
        source.buttons["migrate_formalmc"].invoke()
        self.app.show.assert_called_once_with("portable_formal_package", "test-package:formalmc")
        self.assertFalse(any(method == "POST" for _, method, _ in self.service.calls))
        source.destroy()

    def test_saved_response_preserves_newer_edits(self):
        """Typing while Save is in flight keeps the newer draft intact."""
        pending = []
        self.app.io = lambda owner, work, done, failed=None, **kwargs: pending.append((work, done)) or True
        self.view.fields["tool"].set("/first/FormalMC")
        self.view.save_config()
        self.view.fields["tool"].set("/second/FormalMC")
        work, done = pending[0]
        done(work())
        self.assertEqual(self.view.fields["tool"].get(), "/second/FormalMC")
        self.assertEqual(self.service.row["configs"]["formalmc"]["tool"], "/first/FormalMC")
        self.assertTrue(self.view.dirty())

    def test_invalid_timeout_does_not_submit(self):
        """Reject malformed timing budgets before any configuration mutation."""
        self.view.fields["timeout"].set("-1")
        self.view.buttons["save"].invoke()
        self.assertEqual(self.view.notice.cget("text"), tr("portable_bad_timeout"))
        self.assertFalse(any(method == "POST" for _, method, _ in self.service.calls))

    def test_package_list_opens_selected_backend(self):
        """The new sidebar view routes into the existing desktop shell."""
        listing = PortableFormalPackages(self.root, self.app)
        listing.refresh()
        listing.open("formalmc")
        self.app.show.assert_called_once_with("portable_formal_package", "test-package:formalmc")
        listing.destroy()

    def test_routes_reject_unknown_backend_and_traversal(self):
        """Only a registered-identifier shape and either named backend can enter the page."""
        for value in ("../../pkg:formalmc", "pkg:unknown", "pkg", "pkg:other:sby"):
            with self.assertRaises(ValueError):
                package_route(value)
        self.assertEqual(package_route("package_1:sby"), ("package_1", "sby"))


if __name__ == "__main__":
    unittest.main()
