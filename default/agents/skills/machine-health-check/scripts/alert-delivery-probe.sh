#!/usr/bin/env bash
# Alert-delivery probe — proves a cron job's DELIVERY path (scheduler -> Slack/chat)
# without touching any real watcher. Non-empty stdout is the entire point: an empty one
# is swallowed by the no_agent watchdog pattern and proves nothing.
#
# Recipe:
#   1. create a one-shot, no_agent job with the SAME `deliver` target the real watcher
#      uses, schedule 'in 2m', script 'alert-delivery-probe.sh'
#   2. wait past the fire time, then read the job list:
#      last_status: ok AND last_delivery_error: null  ==  the path works
#   3. remove the probe job (a manual chat/DM test proves the bot can post, not that the
#      scheduler delivers — different code paths)
set -euo pipefail

echo "Delivery probe (scheduled path): if this line is readable at the far end, the"
echo "alert path for this host's watchers works. Nothing is wrong — ignore this."
