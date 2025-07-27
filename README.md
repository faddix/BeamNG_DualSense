# 🎮 DSX - DualSense Adaptive Triggers & Haptics for BeamNG.drive

[![BeamNG.drive](https://img.shields.io/badge/BeamNG.drive-Mod-blue)](https://beamng.com)
[![DualSense](https://img.shields.io/badge/DualSense-Controller-informational)](https://www.playstation.com/en-us/accessories/dualsense-wireless-controller/)

Enhance your driving immersion in **BeamNG.drive** with full support for the PlayStation 5 **DualSense** controller. This mod integrates with the **DSX App** to bring real-time adaptive trigger feedback, RPM-reactive LEDs, gear indicators, and thermal alerts — all mapped from your vehicle's telemetry.

---

## 🚗 Features

### 🎯 Adaptive Triggers

* **Throttle Feedback:** Simulates traction loss and wheel slip on the right trigger.
* **Brake Resistance:** Variable resistance with ABS and brake locking feedback on the left trigger.
* Configurable modes based on engine and brake state.

### 💡 LED Indicators

* **RPM LED Bar:** Displays RPM levels using the controller’s lightbar with color gradients.
* **Gear Indicator Lights:** Player LEDs reflect the current gear (V1, V2, and Edge models).
* **Engine Temperature Alerts:** Microphone LED pulses or lights up when overheating.
* **Stall & Check Engine Warnings:** Visual feedback on critical engine conditions.

---

## 📦 Installation

1. **Install DSX:**
   Get DSX from the [Steam store page](https://store.steampowered.com/app/1812620/DSX/).

2. **Download from BeamNG Mod Repository (Preferred):**
   Search for the **DualSense integration via DSX** mod in the BeamNG Mod Repository menu;
   **Manual Installation (Alternative):**  
   To avoid confusion about the mod folder location, **open the mod folder directly from BeamNG.drive**:  
   * Launch BeamNG.drive.  
   * From the main menu, click **Mods**.
   * Click **Open Mod folder** — this will open the correct mods directory for your current BeamNG installation and version.
   * Download this repo and extract the `BeamNG_DualSense` folder.
   * Place the `BeamNG_DualSense` folder inside the `unpacked` subfolder in this directory.

3. **Enable UDP Communication in DSX:**
   * Open the DSX app.
   * Go to **Settings > Networking**.
   * Enable **Incoming UDP Server**.
   * Set the **Address** to `127.0.0.1` and the **Port** to `6969` (the mod’s defaults).

4. **(Optional) Customize Behavior:**
   Edit the `config.lua` file to tweak trigger modes, LED hues, timing, and thresholds.

---

## ⚙️ Configuration

You can tweak behavior via the `config.lua` file:

```lua
CONFIG.DSX_IP = "127.0.0.1"
CONFIG.DSX_PORT = 6969
CONFIG.CONTROLLER_INDEX = 0
CONFIG.TEMPERATURE.TEMP_WARNING = 115  -- °C
CONFIG.TRIGGER_FORCE.RUNNING = 1
CONFIG.LED_CONFIG.RPM_HUE_FACTOR = 1.2
-- and more...
```

Key options:

* `DSX_IP` / `DSX_PORT`: Address of your DSX UDP server.
* `TRIGGER_FORCE`: Adjust brake resistance based on engine state.
* `LED_CONFIG`: Customize RPM color hue scaling.
* `TEMPERATURE`: Set overheat warning thresholds.
* `PLAYER_LED`, `RGB`, `STALL`, and `CHECK_ENGINE` configs to fully tailor visual feedback.

---

## 🧰 Dependencies

* [DSX Windows Driver (Steam)](https://store.steampowered.com/app/1812620/DSX/)

All required libraries are included with BeamNG:

* [LuaSocket (UDP Networking)](https://w3.impa.br/~diego/software/luasocket/)
* [LuaJSON (Encoding)](https://github.com/harningt/luajson)

---

## 🧠 How It Works

* Reads telemetry from BeamNG vehicle systems in real time.
* Sends UDP packets to the DSX server using **LuaSocket**.
* Translates signals into:

  * Trigger resistance
  * LED color values (via HSV→RGB)
  * Player LED states
  * Mic mute LED status

Everything runs in BeamNG’s Lua environment under the vehicle’s `updateGFX()` loop for high-frequency feedback (60Hz).

---

## 🧹 Troubleshooting

**Controller Not Detected?**

* Make sure the DualSense is properly connected and visible in DSX.

**No Feedback?**

* Double-check IP and port settings in `config.lua`.
* Ensure DSX is running in UDP Server mode.

**Performance Drops?**

* Increase `MIN_PACKET_INTERVAL` to reduce update frequency.

**Brake/Trigger Feels Wrong?**

* Tune `TRIGGER_FORCE` and `TriggerMode` for left/right triggers.

---

## 🙌 Credits

* [LuaJSON](https://github.com/harningt/luajson) — JSON parser
* [LuaSocket](https://w3.impa.br/~diego/software/luasocket/) — Networking
* [**Paliverse**](https://github.com/Paliverse) — Creator of DSX
* **Kirbyguy** — for the original DSX adaptive triggers integration

Special thanks to the BeamNG modding community.

---

## 📄 License

Distributed under the **MIT License**. See the [LICENSE](LICENSE) file for more information.

[![BeamNG.drive](https://img.shields.io/badge/BeamNG.drive-Mod-blue)](https://beamng.com)
[![DualSense](https://img.shields.io/badge/DualSense-Controller-informational)](https://www.playstation.com/en-us/accessories/dualsense-wireless-controller/)

Enhance your driving immersion in **BeamNG.drive** with full support for the PlayStation 5 **DualSense** controller. This mod integrates with the **DSX Windows driver** to bring real-time adaptive trigger feedback, RPM-reactive LEDs, gear indicators, and thermal alerts — all mapped from your vehicle's telemetry.

---

## 🚗 Features

### 🎯 Adaptive Triggers

* **Throttle Feedback:** Simulates traction loss and wheel slip on the right trigger.
* **Brake Resistance:** Variable resistance with ABS feedback on the left trigger.
* Configurable modes based on engine and brake state.

### 💡 LED Indicators

* **RPM LED Bar:** Displays RPM levels using the controller’s lightbar with color gradients.
* **Gear Indicator Lights:** Player LEDs reflect the current gear (V1, V2, and Edge models).
* **Engine Temperature Alerts:** Microphone LED pulses or lights up when overheating.
* **Stall & Check Engine Warnings:** Visual feedback on critical engine conditions.

---

## 📦 Installation

1. **Install DSX:**
   Get DSX from the [Steam store page](https://store.steampowered.com/app/1812620/DSX/).

2. **Download from BeamNG Mod Repository (Preferred):**
   Search for the **DualSense integration via DSX** mod in the BeamNG Mod Repository menu;
   **Manual Installation (Alternative):**  
   
   To avoid confusion about the mod folder location, **open the mod folder directly from BeamNG.drive**:  
   * Launch BeamNG.drive.  
   * From the main menu, click **Mods**.
   * Click **Open Mod folder** — this will open the correct mods directory for your current BeamNG installation and version.
   * Download this repo and extract the `BeamNG_DualSense` folder.
   * Place the `BeamNG_DualSense` folder inside the `unpacked` subfolder in this directory.

3. **Enable UDP Communication in DSX:**

   * Open the DSX app.
   * Go to **Settings > Networking**.
   * Enable **Incoming UDP Server**.
   * Set the **Address** to `127.0.0.1` and the **Port** to `6969` (the mod’s defaults).

4. **(Optional) Customize Behavior:**
   Edit the `config.lua` file to tweak trigger modes, LED hues, timing, and thresholds.

---

## ⚙️ Configuration

You can tweak behavior via the `config.lua` file:

```lua
CONFIG.DSX_IP = "127.0.0.1"
CONFIG.DSX_PORT = 6969
CONFIG.CONTROLLER_INDEX = 0
CONFIG.TEMPERATURE.TEMP_WARNING = 115  -- °C
CONFIG.TRIGGER_FORCE.RUNNING = 1
CONFIG.LED_CONFIG.RPM_HUE_FACTOR = 1.2
-- and more...
```

Key options:

* `DSX_IP` / `DSX_PORT`: Address of your DSX UDP server.
* `TRIGGER_FORCE`: Adjust brake resistance based on engine state.
* `LED_CONFIG`: Customize RPM color hue scaling.
* `TEMPERATURE`: Set overheat warning thresholds.
* `PLAYER_LED`, `RGB`, `STALL`, and `CHECK_ENGINE` configs to fully tailor visual feedback.

---

## 🧰 Dependencies

* [DSX Windows Driver (Steam)](https://store.steampowered.com/app/1812620/DSX/)

All required libraries are included with BeamNG:

* [LuaSocket (UDP Networking)](https://w3.impa.br/~diego/software/luasocket/)
* [LuaJSON (Encoding)](https://github.com/harningt/luajson)

---

## 🧠 How It Works

* Reads telemetry from BeamNG vehicle systems in real time.
* Sends UDP packets to the DSX server using **LuaSocket**.
* Translates signals into:

  * Trigger resistance
  * LED color values (via HSV→RGB)
  * Player LED states
  * Mic mute LED status

Everything runs in BeamNG’s Lua environment under the vehicle’s `updateGFX()` loop for high-frequency feedback (60Hz).

---

## 🧹 Troubleshooting

**Controller Not Detected?**

* Make sure the DualSense is properly connected and visible in DSX.

**No Feedback?**

* Double-check IP and port settings in `config.lua`.
* Ensure DSX is running in UDP Server mode.

**Performance Drops?**

* Increase `MIN_PACKET_INTERVAL` to reduce update frequency.

**Brake/Trigger Feels Wrong?**

* Tune `TRIGGER_FORCE` and `TriggerMode` for left/right triggers.

---

## 🙌 Credits

* [LuaJSON](https://github.com/harningt/luajson) — JSON parser
* [LuaSocket](https://w3.impa.br/~diego/software/luasocket/) — Networking
* [**Paliverse**](https://github.com/Paliverse) — Creator of DSX
* **Kirbyguy** — for the original DSX adaptive triggers integration

Special thanks to the BeamNG modding community.

---

## 📄 License

Distributed under the **MIT License**. See the [LICENSE](LICENSE) file for more information.
