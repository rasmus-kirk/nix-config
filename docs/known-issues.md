# Known Issues

## Desktop: HDMI audio drops through the DP→HDMI adapter

At random times the TV stops playing sound, but video keeps working.

The cause is the DP→HDMI 2.1 adapter, which sometimes stops forwarding
audio. Linux keeps sending samples.

Fix: unplug the adapter on the PC side and plug it in again.

## Desktop: TV screen goes black

At random times the TV shows a black screen on the Desktop's HDMI input. The
TV does not show "No Signal".

Unplugging the adapter on the PC side does not fix it. The cause is unknown.

Fix: disconnect the TV from mains power and connect it again.

## COSMIC: Paste inserts an older clipboard entry

At random times a paste into a window in another tab or stack inserts an
older clipboard entry, not the text that was just copied. The bug is flaky.
The config runs no clipboard manager.

The cause is unknown.

Debug: while the bug is present, start a Claude session and point it at this
entry. Copy nothing else until the session has inspected the clipboard
state.
