# 🎮 DSX - DualSense Adaptive Triggers & Haptics for BeamNG.drive

[![BeamNG.drive](https://img.shields.io/badge/BeamNG.drive-Mod-blue)](https://beamng.com) [![DualSense](https://img.shields.io/badge/DualSense-Controller-informational)](https://www.playstation.com/en-us/accessories/dualsense-wireless-controller/)
Enhance your driving immersion in **BeamNG.drive** with full support for the PlayStation 5 **DualSense** controller. This mod integrates with the **DSX App** to bring real-time adaptive trigger feedback, RPM-reactive LEDs, gear indicators, and thermal alerts — all mapped from your vehicle's telemetry.

> **Note:** This mod is currently in beta, feel free to open feature requests and provide feedback on the GitHub [issues](https://github.com/faddix/BeamNG_DualSense/issues) page.
---

## 🚗 Features

### 🎯 Adaptive Triggers
- **Throttle Feedback:** Simulates traction loss and wheel slip on the right trigger with automatic gun mode
- **Brake Resistance:** Variable resistance with ABS feedback on the left trigger, with simulation for power brakes
- **Dynamic Modes:** Trigger behavior adapts based on engine state, clutch engagement, and wheel slip

### 💡 LED Indicators
- **RPM LED Bar:** Real-time RPM visualization using HSV color mapping with rev-limiter flash effects
- **Gear Indicator Lights:** Player LEDs show current gear with support for reverse and multi-gear configurations
  - *Note: Only available on DualSense V1 and Edge models due to hardware limitations*
- **Engine Temperature Alerts:** Microphone LED indicates overheating with pulse and warning modes
- **Engine Status:** Visual feedback for stall conditions and check engine warnings with fade effects

---

## 📦 Installation

### 1. Install DSX
Get DSX from the [Steam store page](https://store.steampowered.com/app/1812620/DSX/).

### 2. Install the Mod
**Via BeamNG Mod Repository (Recommended):**
- Search for "DualSense integration via DSX" in the in-game mod repository

**Manual Installation (Alternative):**
  - A. Download the [BNG_DSX.zip](https://github.com/faddix/BeamNG_DualSense/releases) file from GitHub and extract it into your `mods/repo` folder
  - B. Download the latest version from the BeamNG Mod Page [here](https://www.beamng.com/resources/dualsense-integration-via-dsx.36016/), then move the `BNG_DSX.zip` folder into your `mods/repo` folder (you can find it by clicking the "Open Mod folder" button in the BeamNG Mods Page)
### 3. Configure DSX
- Open the DSX app
- Go to **Settings > Networking**
- Enable **Incoming UDP**
- Set **IP Address** to `127.0.0.1` and **Port number** to `6969`

### 4. Customize (Optional)
Edit `config.lua` to adjust trigger forces, LED colors, temperature thresholds, and network settings.

---

## ⚙️ Configuration

Key settings in `config.lua`:

```lua
CONFIG.DSX_IP = "127.0.0.1"       -- DSX server IP
CONFIG.DSX_PORT = 6969            -- DSX server port
CONFIG.CONTROLLER_INDEX = 0       -- Controller number (0-3)
```

**Network Settings:**
- `MIN_PACKET_INTERVAL`: Minimum time between packets (default: 1/60 for 60Hz max)
- `MAX_RETRIES`: Number of retry attempts for failed sends

---

## 🧰 Dependencies

- **[DSX Windows Driver](https://store.steampowered.com/app/1812620/DSX/)** (Required)
- **LuaSocket** - UDP networking (included with BeamNG)
- **LuaJSON** - JSON encoding/decoding (included with BeamNG)

---

## 🧠 How It Works

The mod runs in BeamNG's Lua environment with these components:

1. **Telemetry Reading:** Monitors vehicle systems including engine, electrics, and drivetrain
2. **State Processing:** Determines appropriate controller responses based on:
   - Engine RPM and temperature
   - Gear position and wheel slip
   - ABS status and stall conditions
3. **Packet Generation:** Creates instruction packets for triggers, LEDs, and audio indicators
4. **UDP Transmission:** Sends JSON packets to DSX at 60Hz with rate limiting and retry logic

**Performance Optimizations:**
- Caches frequently used functions and tables
- Implements packet timing controls to prevent network flooding
- Uses efficient table reuse to minimize garbage collection

---

## 🧹 Troubleshooting

**Controller Not Detected?**
- Verify DualSense is connected and recognized in DSX
- Check Windows device manager for controller drivers

**No Feedback?**
- Confirm DSX UDP server is enabled and IP/port match `config.lua`
- If using wireless mode, 
- Check BeamNG console for error messages
- Ensure mod is loaded in BeamNG (check Mods menu)

**Performance Issues?**
- Increase `MIN_PACKET_INTERVAL` in `config.lua` to reduce update frequency
- Close unnecessary background applications

**Network Errors?**
- Verify firewall isn't blocking UDP traffic on port 6969
- Ensure DSX and BeamNG are on the same machine (127.0.0.1)

---

## 🙌 Credits

- **[Paliverse](https://github.com/Paliverse)** - DSX creator
- **Kirbyguy** - Original DSX adaptive triggers implementation
- **[LuaJSON](https://github.com/harningt/luajson)** - JSON parsing
- **[LuaSocket](https://w3.impa.br/~diego/software/luasocket/)** - Network communication

Special thanks to the BeamNG modding community for their support and feedback.

---

## 📄 License

Distributed under the **MIT License**. See [LICENSE](LICENSE) for details.
