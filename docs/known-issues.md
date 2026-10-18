# Known Issues

## Desktop: HDMI audio drops through the DP→HDMI adapter

At random times the TV stops playing sound, but video keeps working.

The cause is the DP→HDMI 2.1 adapter, which sometimes stops forwarding
audio. Linux keeps sending samples.

Fix: unplug the adapter on the PC side and plug it in again.
