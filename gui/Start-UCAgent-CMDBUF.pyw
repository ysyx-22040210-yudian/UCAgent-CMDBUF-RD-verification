"""Open the updated UCAgent desktop on this project's existing SBY task."""

import argparse
from pathlib import Path
import sys
import tkinter as tk


def main():
    """Use the active local SSH forwarding address without storing VM credentials."""
    parser = argparse.ArgumentParser()
    parser.add_argument('--server', default='http://127.0.0.1:18814')
    parser.add_argument('--session', default='90855753a21f4dc7a0dc29b7892e38f3')
    args = parser.parse_args()
    root_dir = Path(__file__).resolve().parent
    sys.path.insert(0, str(root_dir / 'UCAgent-Desktop.pyz'))
    from ucagent_tk.app import Application
    from ucagent_tk.model import Preferences
    window = tk.Tk()
    app = Application(window, args.server, Preferences(root_dir / 'desktop_preferences.json'))
    app.show('formal_session', args.session)
    window.mainloop()


if __name__ == '__main__':
    main()
