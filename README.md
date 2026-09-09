# BNG_DSX - DualSense adaptive triggers and lighting for BeamNG.drive

[![BeamNG.drive](https://img.shields.io/badge/BeamNG.drive-Mod-blue)](https://beamng.com) [![DualSense](https://img.shields.io/badge/DualSense-Controller-informational)](https://www.playstation.com/en-us/accessories/dualsense-wireless-controller/) [![DSX](https://img.shields.io/badge/DSX-App-informational)](https://store.steampowered.com/app/1812620/DSX/)

- Throttle feedback from wheel slip and brake feedback from ABS.
- RPM lighting, rev-limiter flashes and turn signals.
- Gear indicators on supported controllers.
- Engine temperature, low-fuel, stall and check-engine warnings.
- In-game settings and custom profiles.

## Installation

Install **DualSense integration via DSX** from BeamNG's mod repository, or download it from [GitHub releases](https://github.com/faddix/BeamNG_DualSense/releases) or the [BeamNG mod page](https://www.beamng.com/resources/dualsense-integration-via-dsx.36016/).

For a manual install, put the ZIP in your BeamNG user folder's `mods` directory without extracting it. Keep only one copy enabled, then restart the game.

Connect your controller and open DSX. Under **Settings → Networking**, enable **Incoming UDP** and set the address to `127.0.0.1` and the port to `6969`.

## Settings

In BeamNG's **HUD Apps / UI Apps** editor, choose **Add App → DSX Settings**. Click the small DSX Settings button to open the panel.

Change the controls and click **Apply & Save**. **Reset to Defaults** fills the form with defaults; click Apply & Save to use them. **Discard & reload** clears unsaved edits.

Use **Collapse** to tuck the panel away while driving. To resize it, select DSX Settings in **HUD Apps → Edit Layout**, drag an edge or corner, then save the layout.

### Profiles

Open **Profiles**, enter a name and click **Save new** to save the current form. Profiles include the connection settings.

To use one, click the profile selector, choose a name, then click **Load → Apply & Save**. **Update selected** saves the current form over that profile. You can also rename or delete it.

Saving a profile does not activate it. Applying settings does not update a profile automatically.

## Troubleshooting

If there's no feedback:

- Check that DSX recognizes the controller and Incoming UDP is enabled.
- Make sure the address and port match in DSX and the mod's settings.
- Check that the mod is enabled, then try **Reconnect saved target**.

Report bugs or request features on [GitHub](https://github.com/faddix/BeamNG_DualSense/issues).

## Credits

- **[Paliverse](https://github.com/Paliverse)** — DSX.
- **Kirbyguy** — original adaptive trigger implementation.
- **[LuaJSON](https://github.com/harningt/luajson)** and **[LuaSocket](https://w3.impa.br/~diego/software/luasocket/)**.

## License

Distributed under the **MIT License**. See [LICENSE](LICENSE) for details.