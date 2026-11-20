"""Render signing options for the app and its widget without reading credentials."""
import os
from pathlib import Path
import plistlib
import sys

data = plistlib.loads(Path(__file__).with_name("ExportOptions.plist").read_bytes())
data["teamID"] = os.environ["TEAM_ID"]
app_id = os.environ.get("APP_ID", "com.hgsldswk.daycount")
data["provisioningProfiles"] = {
    app_id: os.environ.get("APP_PROFILE", "DayCount AppStore"),
    app_id + ".widget": os.environ.get("WIDGET_PROFILE", "DayCount Widget AppStore"),
}
sys.stdout.buffer.write(plistlib.dumps(data))
