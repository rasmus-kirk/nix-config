import json
from dataclasses import dataclass
from pathlib import Path
from typing import Annotated

import daemon
import typer

app = typer.Typer(help="Keeps an HDMI-CEC TV in step with activity on an always-on box.")

@dataclass(frozen=True)
class KeepAwake:
    """The kirk.cec.keepAwake options."""

    enable: bool
    silenceMinutes: int
    pulseSeconds: int
    amplitude: float
    frequency: int
    threshold: float

    @property
    def silence_seconds(self):
        """Returns silenceMinutes in seconds."""
        return self.silenceMinutes * 60

@dataclass(frozen=True)
class ControllerVolume:
    """The kirk.cec.controllerVolume options."""

    enable: bool
    referencePercent: int
    stepPercent: int

@dataclass(frozen=True)
class Config:
    """The kirk.cec options, as the JSON file that Nix writes."""

    device: str
    osdName: str
    idleMinutes: int
    tvLogicalAddress: int
    audioSystemLogicalAddress: int
    sink: str | None
    audioKeepsAwake: bool
    debug: bool
    keepAwake: KeepAwake
    controllerVolume: ControllerVolume

    @property
    def idle_seconds(self):
        """Returns idleMinutes in seconds."""
        return self.idleMinutes * 60

    @classmethod
    def from_json(cls, text):
        """Makes a Config from JSON text. Unknown or missing keys raise TypeError."""
        data = json.loads(text)
        data["keepAwake"] = KeepAwake(**data["keepAwake"])
        data["controllerVolume"] = ControllerVolume(**data["controllerVolume"])
        return cls(**data)

@app.command()
def main(config: Annotated[Path, typer.Argument(exists=True, dir_okay=False, help="JSON settings file.")]):
    """
    Runs the daemon with the settings in CONFIG, the kirk.cec options as
    JSON.

    Puts the TV in standby after idleMinutes without activity and wakes it on
    input. The daemon polls the real TV power state over CEC, so it also wakes
    a TV that went to standby by its own timer or by the TV remote.

    Activity is a sleep key press, sound on the TV sink, or a powered Steam
    controller. The sleep key toggles the TV. SIGUSR1 has the same effect, so
    the system suspend action can toggle the TV instead of suspending the box.
    A controller that connects wakes the TV. Sound only keeps the TV awake, so
    a manual standby holds while audio plays. The power key is not handled,
    because acpid owns it.

    The daemon never reads keyboards. It can open only the input nodes that
    udev gives to its group, and those nodes have no letter keys. It grabs
    the volume key node, so volume and mute go to the AVR over CEC and the
    compositor does not also change the sink.

    Controller presence is data on a Valve hidraw node. Steam reads the
    controller over hidraw, so evdev never sees its input. A controller sends
    reports for as long as it is on, in every input layout. After a controller
    disconnects, the receiver leaves one hidraw node at EOF. select() reports
    that node as readable forever and read() returns no bytes. Only a
    non-empty read counts as activity, and a node at EOF is closed and opened
    again on the next scan.

    With keepAwake.enable, the daemon records the TV sink monitor. After
    silenceMinutes of silence it plays a tone for pulseSeconds, so the
    speakers do not go to standby. It ignores the monitor while the tone
    plays and for a short time after.

    With controllerVolume.enable, the daemon holds the TV sink at
    referencePercent. Controller volume keys change only the sink, so each stepPercent of
    change becomes one CEC volume step to the AVR and the sink returns to
    referencePercent.
    """
    daemon.Daemon(Config.from_json(config.read_text())).run()

if __name__ == "__main__":
    app()
