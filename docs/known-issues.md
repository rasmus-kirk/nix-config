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
