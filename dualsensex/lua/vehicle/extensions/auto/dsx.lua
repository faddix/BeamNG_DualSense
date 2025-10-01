-- ============================
--           dsx.lua
-- ============================
--
-- DSX integration for BeamNG.drive
-- Provides adaptive triggers and LED control for PlayStation 5 DualSense controllers
-- by mapping vehicle telemetry to controller features.
--
-- Features:
-- - Adaptive triggers that respond to throttle, brake and engine state
-- - RPM-based LED bar visualization 
-- - Gear indicator lights
-- - Engine temperature warning via mic mute LED
-- - Engine stall and check engine status indicators
--
-- ============================
--         DEPENDENCIES
-- ============================
--
-- External Libraries:
-- - types: Type definitions and utilities
-- - config: Configuration settings for the DSX extension
-- - lunajson: A fast JSON encoding/decoding library
-- - socket: LuaSocket for networking (UDP communication)

require('auto/types')
local jsonEnc = require('libs/lunajson/lunajson').encode
local socket = require("socket")

local config = require('auto/config')
local CONFIG = config

-- ============================
--         ENUMERATIONS
-- ============================

local InstructionType = {
    Invalid = 0,
    TriggerUpdate = 1,
    RGBUpdate = 2,
    PlayerLED = 3,
    TriggerThreshold = 4,
    MicLED = 5
}

local Trigger = {
    Invalid = 0,
    Left = 1,
    Right = 2
}

local TriggerMode = {
    Normal = 0,
    GameCube = 1,
    VerySoft = 2,
    Soft = 3,
    Hard = 4,
    VeryHard = 5,
    Hardest = 6,
    Rigid = 7,
    VibrateTrigger = 8,
    Choppy = 9,
    Medium = 10,
    VibrateTriggerPulse = 11,
    CustomTriggerValue = 12,
    Resistance = 13,
    Bow = 14,
    Galloping = 15,
    SemiAutomaticGun = 16,
    AutomaticGun = 17,
    Machine = 18
}

local MicLEDMode = {
    On = 0,
    Pulse = 1,
    Off = 2
}

-- ============================
--          UTILITIES
-- ============================

-- Cache global functions and tables locally for performance
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local vec3 = vec3
local log = log
local settings = settings
local powertrain = powertrain
local playerInfo = playerInfo
local vehicle = v
local electrics = electrics

--- Clamps a number between a low and high value.
-- @param n Number to clamp.
-- @param low Lower bound.
-- @param high Upper bound.
-- @return Clamped number.
local function clamp(n, low, high)
    return math_min(math_max(n, low), high)
end

--- Converts a number to a boolean.
-- @param n Number to convert.
-- @return Boolean value.
local function toBoolean(n)
    if type(n) == "boolean" then return n
    else return n ~= 0 end
end

--- Validates IP address format.
-- @param ip IP address string.
-- @return Boolean indicating validity.
local function isValidIPAddress(ip)
    local pattern = "^%d+%.%d+%.%d+%.%d+$"
    return string.match(ip, pattern) ~= nil
end

--- Validates network configuration.
-- @param ip IP address.
-- @param port Port number.
-- @return Boolean indicating if configuration is valid.
local function isValidNetworkConfig(ip, port)
    if not (ip and port) then
        log("E", "dsx", "IP address or port number missing")
        return false
    end
    if not isValidIPAddress(ip) then
        log("E", "dsx", "Invalid IP address format")
        return false
    end
    if port < 1 or port > 65535 then
        log("E", "dsx", "Port number out of valid range (1-65535)")
        return false
    end
    return true
end

--- Converts a color from HSV (Hue, Saturation, Value) to RGB (Red, Green, Blue) color space.
-- This function takes the HSV color components and outputs the corresponding RGB color vector.
-- @param h Hue component, should be in range [0, 1].
-- @param s Saturation component, should be in range [0, 1].
-- @param v Value component, should be in range [0, 1].
-- @return RGB vector with components in range [0, 255].
--
-- The conversion algorithm is based on the Wikipedia article on HSL and HSV color spaces.
-- It first calculates the chroma (maximum intensity of the color), then calculates the intermediate values q and t.
-- Depending on the value of the hue, it then calculates the RGB values.
local function HSVtoRGB(h, s, v)
    local r, g, b
    local i = math_floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6

    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    elseif i == 5 then r, g, b = v, p, q
    else r, g, b = 0, 0, 0 end

    return vec3(math_floor(r * 255), math_floor(g * 255), math_floor(b * 255))
end

-- ============================
--          DSX CLASS
-- ============================

local DSX = {}
DSX.__index = DSX

-- Reuse tables to reduce garbage collection
DSX.instructionCache = {
    rgbUpdate = { type = InstructionType.RGBUpdate, parameters = {} },
    playerLED = { type = InstructionType.PlayerLED, parameters = {} },
    triggerUpdate = { type = InstructionType.TriggerUpdate, parameters = {} },
    micLED = { type = InstructionType.MicLED, parameters = {} }
}

function DSX:createInstruction(type, params)
    local cache = self.instructionCache[type]
    if cache then
        cache.parameters = params
        return cache
    end
    return { type = type, parameters = params }
end

--- Creates a new DSX instance.
-- @return New DSX object.
function DSX:new()
    local obj = setmetatable({}, self)

    -- Validate configuration before proceeding
    if not obj:validateConfig() then
        log("E", "dsx", "Configuration validation failed")
        return nil
    end

    -- Initialize configuration
    obj.ip = settings.getValue("dsxIP", CONFIG.DSX_IP)
    obj.port = tonumber(settings.getValue("dsxPort", CONFIG.DSX_PORT)) or CONFIG.DSX_PORT
    obj.id = 0
    obj.timer = 0
    obj.lastChangedLed = 0
    obj.targetRPM = 0
    obj.alternatePacket = false
    obj.ledsOn = true
    obj.stallLedsOn = false
    obj.checkEngineLedsOn = false

    -- Add packet timing tracking
    obj.lastPacketTime = 0
    obj.lastPacketData = nil

    -- Initialize DSX socket
    obj.udpDSXSocket = socket.udp()
    if not obj.udpDSXSocket then
        log("E", "dsx", "Failed to create UDP socket for DSX")
        return nil
    end
    obj.udpDSXSocket:settimeout(0)

    -- Validate network configuration
    if not isValidNetworkConfig(obj.ip, obj.port) then
        log("E", "dsx", "Invalid network configuration. DSX disabled.")
        return nil
    end

    log("I", "dsx", string.format("DSX v%s initialized for: %s:%d", CONFIG.VERSION, obj.ip, obj.port))

    return obj
end

--- Sends data with rate limiting and retries.
-- @param socketObj The socket to use.
-- @param data The data to send.
-- @param ip Destination IP.
-- @param port Destination port.
-- @return Boolean indicating success.
function DSX:sendWithRetries(socketObj, data, ip, port)
    if not socketObj then
        log("E", "dsx", "Invalid socket object")
        return false
    end

    -- Check if enough time has passed since last packet
    local currentTime = socket.gettime()
    if currentTime - self.lastPacketTime < CONFIG.NETWORK.MIN_PACKET_INTERVAL then
        return true -- Skip sending but don't count as error
    end

    for attempt = 1, CONFIG.MAX_RETRIES do
        local bytesSent, err = socketObj:sendto(data, ip, port)
        if bytesSent then
            self.lastPacketTime = currentTime
            self.lastPacketData = data
            return true
        else
            log("W", "dsx", string.format("Send attempt %d failed: %s", attempt, tostring(err)))
            -- Add delay between retries
            socket.sleep(CONFIG.NETWORK.RETRY_COOLDOWN)
        end
    end
    log("E", "dsx", "Failed to send data after maximum retries")
    return false
end

--- Sends an instruction packet.
-- @param instructions Table of instructions.
function DSX:sendInstructionPacket(instructions)
    local packet = { instructions = instructions }
    local encoded = jsonEnc(packet)
    self:sendWithRetries(self.udpDSXSocket, encoded, self.ip, CONFIG.DSX_PORT)
end

--- Retrieves engine information.
-- @return Engine device and type string.
function DSX:getEngineInfo()
    if powertrain.getDevice("mainEngine") then
        return powertrain.getDevice("mainEngine")
    elseif powertrain.getDevice("rearMotor") then
        return powertrain.getDevice("rearMotor")
    elseif powertrain.getDevice("frontMotor") then
        return powertrain.getDevice("frontMotor")
    else
        return nil
    end
end

--- Determines if the engine is currently stalled.
-- @param engine The engine device.
-- @return Boolean indicating if the engine is stalled.
function DSX:isEngineStalled()
    return electrics.values.ignitionLevel == 2
        and not toBoolean(electrics.values.engineRunning)
        and math_floor(electrics.values.rpm) <= 0
end

--- Generates a packet for the player not being seated and using the unicycle.
-- @return Table of instructions.
function DSX:generatePlayerNotSeatedPacket()
    local ndRGB = CONFIG.ND_RGB
    local ndPlayerLED = CONFIG.ND_PLAYER_LED
    local instructions = {
        {
            type = InstructionType.RGBUpdate,
            parameters = {CONFIG.CONTROLLER_INDEX, ndRGB.x, ndRGB.y, ndRGB.z}
        },
        {
            type = InstructionType.PlayerLED,
            parameters = {
                CONFIG.CONTROLLER_INDEX,
                ndPlayerLED.light1,
                ndPlayerLED.light2,
                ndPlayerLED.light3,
                ndPlayerLED.light4,
                ndPlayerLED.light5
            }
        },
        {
            type = InstructionType.TriggerUpdate,
            parameters = {CONFIG.CONTROLLER_INDEX, Trigger.Left, TriggerMode.Normal, 0, 0, 0}
        },
        {
            type = InstructionType.TriggerUpdate,
            parameters = {CONFIG.CONTROLLER_INDEX, Trigger.Right, TriggerMode.Normal, 0, 0, 0}
        },
        {
            type = InstructionType.MicLED,
            parameters = {CONFIG.CONTROLLER_INDEX, MicLEDMode.Off}
        }
    }
    return instructions
end

--- Toggles LEDs based on configuration and returns the new state and RGB values.
-- @param config LED configuration table.
-- @param ledState Current state of the LED (on/off).
-- @param lastChanged Timestamp of the last LED state change.
-- @param flashInterval Flash interval in milliseconds.
-- @return Table containing the new LED state, updated timestamp, and RGB values.
function DSX:toggleLED(config, ledState, lastChanged, flashInterval)
    if self.timeMs - lastChanged > flashInterval then
        lastChanged = self.timeMs
        ledState = not ledState
    end

    local rgb = ledState and config.RGB_ON or config.RGB_OFF
    return { ledState = ledState, lastChanged = lastChanged, rgb = rgb }
end

--- Calculates fade value using a sine wave
-- @param timeMs Current time in milliseconds
-- @param interval Fade interval in milliseconds
-- @return Fade value between 0 and 1
function DSX:calculateFade(timeMs, interval)
    local phase = (timeMs % interval) / interval
    return (math.sin(phase * 2 * math.pi) + 1) / 2
end

--- Generates a packet when the engine is dead (check engine light is on).
-- @return Table of instructions.
function DSX:generateEngineDeadPacket()
    -- Calculate fade value between 0 and 1
    local fadeValue = self:calculateFade(self.timeMs, CONFIG.CHECK_ENGINE_LED_CONFIG.FADE_INTERVAL_MS)

    -- Interpolate between min and max RGB values
    local rgb = vec3(
        CONFIG.CHECK_ENGINE_LED_CONFIG.RGB_MIN.x + (CONFIG.CHECK_ENGINE_LED_CONFIG.RGB_MAX.x - CONFIG.CHECK_ENGINE_LED_CONFIG.RGB_MIN.x) * fadeValue,
        CONFIG.CHECK_ENGINE_LED_CONFIG.RGB_MIN.y + (CONFIG.CHECK_ENGINE_LED_CONFIG.RGB_MAX.y - CONFIG.CHECK_ENGINE_LED_CONFIG.RGB_MIN.y) * fadeValue,
        CONFIG.CHECK_ENGINE_LED_CONFIG.RGB_MIN.z + (CONFIG.CHECK_ENGINE_LED_CONFIG.RGB_MAX.z - CONFIG.CHECK_ENGINE_LED_CONFIG.RGB_MIN.z) * fadeValue
    )

    local instructions = {
        {
            type = InstructionType.RGBUpdate,
            parameters = {CONFIG.CONTROLLER_INDEX, rgb.x, rgb.y, rgb.z}
        },
        {
            type = InstructionType.TriggerUpdate,
            parameters = {CONFIG.CONTROLLER_INDEX, Trigger.Left, TriggerMode.Resistance, 0, CONFIG.TRIGGER_FORCE.NOT_RUNNING}
        },
        {
            type = InstructionType.TriggerUpdate,
            parameters = {CONFIG.CONTROLLER_INDEX, Trigger.Right, TriggerMode.Normal, 0, 0, 0}
        },
        {
            type = InstructionType.MicLED,
            parameters = {CONFIG.CONTROLLER_INDEX, self:checkEngineTemperature()}
        }
    }

    local gearInstructions = self:generateGearLightsPacket(electrics.values.gearIndex or 0)
    for _, instr in ipairs(gearInstructions) do
        table.insert(instructions, instr)
    end

    return instructions
end

--- Generates a packet when the engine is stalled.
-- @return Table of instructions.
function DSX:generateEngineStalledPacket()
    local toggleResult = self:toggleLED(
        CONFIG.STALL_LED_CONFIG,
        self.stallLedsOn,
        self.lastChangedLed,
        CONFIG.STALL_LED_CONFIG.FLASH_INTERVAL_MS
    )
    self.stallLedsOn = toggleResult.ledState
    self.lastChangedLed = toggleResult.lastChanged
    local instructions = {
        {
            type = InstructionType.RGBUpdate,
            parameters = {CONFIG.CONTROLLER_INDEX, toggleResult.rgb.x, toggleResult.rgb.y, toggleResult.rgb.z}
        },
        {
            type = InstructionType.TriggerUpdate,
            parameters = {CONFIG.CONTROLLER_INDEX, Trigger.Left, TriggerMode.Resistance, 0, CONFIG.TRIGGER_FORCE.NOT_RUNNING}
        },
        {
            type = InstructionType.TriggerUpdate,
            parameters = {CONFIG.CONTROLLER_INDEX, Trigger.Right, TriggerMode.Normal, 0, 0, 0}
        },
        {
            type = InstructionType.MicLED,
            parameters = {CONFIG.CONTROLLER_INDEX, self:checkEngineTemperature()}
        }
    }

    local gearInstructions = self:generateGearLightsPacket(electrics.values.gearIndex or 0)
    for _, instr in ipairs(gearInstructions) do
        table.insert(instructions, instr)
    end

    return instructions
end

--- Generates a packet for the player being seated and driving.
-- @param engine The engine device.
-- @param maxRPM Maximum RPM of the engine.
-- @param cutTime Rev limiter cut time.
-- @return Table of instructions.
function DSX:generateDrivingPacket(maxRPM, cutTime)
    -- Calculate maximum slip values for wheels
    local maxLongSlip, maxSlip = 0, 0
    for _, wheel in ipairs(drivetrain.wheels) do
        local lastSlip = wheel.lastSlip or 0
        maxSlip = math_max(maxSlip, lastSlip)
        if wheel.isPropulsed then
            maxLongSlip = math_max(maxLongSlip, lastSlip)
        end
    end

    -- Trigger Logic:
    --  Left Trigger:   ABS active -> pulsing resistance based on ABS
    --                  No ABS -> resistance based on wheel slip
    -- Right Trigger: Resistance based on clutch and propulsion slip

    -- Determine trigger strength and frequency
    local rTrigStr = toBoolean(electrics.values.clutch) and 0 or (toBoolean(electrics.values.gearIndex) and toBoolean(electrics.values.engineRunning) and clamp((maxLongSlip or 0) - 1, 0, 7) or 0)
    local lTrigStr = toBoolean(electrics.values.hasABS) and electrics.values.absActive * 7 or clamp(((maxLongSlip or 0) - 1) * 2, 0, 7)
    local lTrigFreq = toBoolean(electrics.values.hasABS) and 10 or 30 + math_floor(maxLongSlip or 0)

    local lTrigParams
    if lTrigStr > 1 then
        lTrigParams = {CONFIG.CONTROLLER_INDEX, Trigger.Left, TriggerMode.AutomaticGun, 0, lTrigStr, lTrigFreq}
    elseif toBoolean(electrics.values.engineRunning) then
        lTrigParams = {CONFIG.CONTROLLER_INDEX, Trigger.Left, TriggerMode.Resistance, 0, CONFIG.TRIGGER_FORCE.RUNNING}
    else
        lTrigParams = {CONFIG.CONTROLLER_INDEX, Trigger.Left, TriggerMode.Resistance, 0, CONFIG.TRIGGER_FORCE.NOT_RUNNING}
    end

    local instructions = {
        {
            type = InstructionType.TriggerUpdate,
            parameters = lTrigParams
        },
        {
            type = InstructionType.TriggerUpdate,
            parameters = {CONFIG.CONTROLLER_INDEX, Trigger.Right, TriggerMode.AutomaticGun, 0, rTrigStr, 30 + math_floor(maxLongSlip or 0)}
        }
    }

    -- Insert MicLED instruction for temperature warning
    table.insert(instructions, {
        type = InstructionType.MicLED,
        parameters = {CONFIG.CONTROLLER_INDEX, self:checkEngineTemperature()}
    })

    -- Determine RPM percentage
    local rpmPercent = (electrics.values.rpm or 0) / maxRPM
    rpmPercent = clamp(rpmPercent, 0, 1)

    -- Handle RPM LEDs
    local rpmInstructions = self:generateRPMLEDs(rpmPercent, maxRPM, cutTime)
    for _, instr in ipairs(rpmInstructions) do
        table.insert(instructions, instr)
    end

    local gear = electrics.values.gearIndex
    local gearInstructions = self:generateGearLightsPacket(gear)

    -- Append Gear Lights Instructions
    for _, instr in ipairs(gearInstructions) do
        table.insert(instructions, instr)
    end

    return instructions
end

--- Generates a packet when no engine is present.
-- @return Table of instructions.
function DSX:generateNoEnginePresentPacket()
    local neRGB = CONFIG.NE_RGB
    local nePlayerLED = CONFIG.NE_PLAYER_LED
    local instructions = {
        {
            type = InstructionType.RGBUpdate,
            parameters = {CONFIG.CONTROLLER_INDEX, neRGB.x, neRGB.y, neRGB.z}
        },
        {
            type = InstructionType.PlayerLED,
            parameters = {
                CONFIG.CONTROLLER_INDEX,
                nePlayerLED.light1,
                nePlayerLED.light2,
                nePlayerLED.light3,
                nePlayerLED.light4,
                nePlayerLED.light5
            }
        },
        {
            type = InstructionType.TriggerUpdate,
            parameters = {CONFIG.CONTROLLER_INDEX, Trigger.Left, TriggerMode.Resistance, 1, CONFIG.TRIGGER_FORCE.NOT_RUNNING}
        },
        {
            type = InstructionType.TriggerUpdate,
            parameters = {CONFIG.CONTROLLER_INDEX, Trigger.Right, TriggerMode.Normal, 0, 0, 0}
        },
        {
            type = InstructionType.MicLED,
            parameters = {CONFIG.CONTROLLER_INDEX, MicLEDMode.Off}
        }
    }

    return instructions
end

--- Generates RPM LED instructions.
-- @param rpmPercent Percentage of RPM relative to maxRPM, clamped between 0 and 1.
-- @param maxRPM Maximum RPM of the engine.
-- @param cutTime Rev limiter cut time.
-- @return Table of RPM instructions.
function DSX:generateRPMLEDs(rpmPercent, maxRPM, cutTime)
    -- Validate inputs
    if type(rpmPercent) ~= "number" or type(maxRPM) ~= "number" or type(cutTime) ~= "number" then
        log("E", "dsx", "Invalid parameters passed to generateRPMLEDs")
        return {}
    end

    if maxRPM <= 0 then
        log("W", "dsx", "Invalid maxRPM value")
        return {}
    end

    local ledHue = clamp(CONFIG.LED_CONFIG.RPM_HUE_FACTOR - (rpmPercent * CONFIG.LED_CONFIG.RPM_HUE_SCALE), CONFIG.LED_CONFIG.RPM_CLAMP_LOW, CONFIG.LED_CONFIG.RPM_CLAMP_HIGH)
    local ledRGB = self.ledsOn and HSVtoRGB(ledHue, 1, clamp(rpmPercent, 0, 1)) or vec3(0, 0, 0)

    if (electrics.values.rpm or 0) >= self.targetRPM then
        self.targetRPM = maxRPM - (maxRPM * CONFIG.LED_CONFIG.TARGET_RPM_DECREMENT_OFF)
        if self.timeMs - self.lastChangedLed > cutTime then
            self.lastChangedLed = self.timeMs
            self.ledsOn = not self.ledsOn
        end
    else
        self.ledsOn = true
        self.targetRPM = maxRPM - (maxRPM * CONFIG.LED_CONFIG.TARGET_RPM_DECREMENT_ON)
    end

    local instructions = {
        {
            type = InstructionType.RGBUpdate,
            parameters = {CONFIG.CONTROLLER_INDEX, ledRGB.x, ledRGB.y, ledRGB.z}
        }
    }

    return instructions
end

--- Generates gear light instructions based on current gear.
-- @param gear Current gear index.
-- @return Table of instructions.
function DSX:generateGearLightsPacket(gear)
    if gear > 10 then
        gear = gear % 10
    end

    local lightStatus = {
        light1 = (gear >= 1 and gear <= 5) or gear <= -1,
        light2 = (gear >= 2 and gear <= 6) or gear < -1,
        light3 = (gear >= 3 and gear <= 7) or gear == 10,
        light4 = (gear >= 4 and gear <= 8) or gear < -1,
        light5 = (gear >= 5 and gear <= 9) or gear <= -1
    }

    local instructions = {
        {
            type = InstructionType.PlayerLED,
            parameters = {
                CONFIG.CONTROLLER_INDEX,
                lightStatus.light1,
                lightStatus.light2,
                lightStatus.light3,
                lightStatus.light4,
                lightStatus.light5
            }
        }
    }

    return instructions
end

--- Checks if the engine temperature is above the warning threshold.
-- @return Boolean indicating if the engine temperature is above the warning threshold.
function DSX:checkEngineTemperature()
    -- Use water temperature for all engines
    local temp = electrics.values.watertemp or 0

    if temp >= CONFIG.TEMPERATURE.TEMP_WARNING then
        return MicLEDMode.On
    elseif temp >= CONFIG.TEMPERATURE.TEMP_PULSE then
        return MicLEDMode.Pulse
    else
        return MicLEDMode.Off
    end
end

--- Processes DSX instructions based on the current vehicle state.
-- This function checks the vehicle state and generates the appropriate packets.
function DSX:processDSXInstructions()
    -- Retrieve engine information
    local engine = self:getEngineInfo()
    local maxRPM, cutTime = 0, CONFIG.REV_LIMITER_CUT_TIME.DEFAULT
    if engine then
        maxRPM = engine.maxRPM
        if engine.revLimiterCutTime then
            cutTime = clamp(engine.revLimiterCutTime * 1000, CONFIG.REV_LIMITER_CUT_TIME.MIN, CONFIG.REV_LIMITER_CUT_TIME.MAX)
        end
    end

    local packet = {}
    -- Retrieve vehicle information
    local vehicleName = vehicle.config.mainPartName

    if vehicleName == "unicycle" then
        table.insert(packet, self:generatePlayerNotSeatedPacket())
    elseif engine and toBoolean(electrics.values.checkengine) then
        table.insert(packet, self:generateEngineDeadPacket())
    elseif engine and self:isEngineStalled() then
        table.insert(packet, self:generateEngineStalledPacket())
    elseif engine then
        table.insert(packet, self:generateDrivingPacket(maxRPM, cutTime))
    else
        table.insert(packet, self:generateNoEnginePresentPacket())
    end

    self:sendPacket(packet)
end

--- Sends packet to DSX.
-- @param packet A table containing all instruction tables.
function DSX:sendPacket(packet)
    local combinedInstructions = {}
    for _, pkt in ipairs(packet) do
        for _, instruction in ipairs(pkt) do
            table.insert(combinedInstructions, instruction)
        end
    end

    self:sendInstructionPacket(combinedInstructions)
end

--- Generates and sends a DSX package.
-- @return Boolean indicating if the package was sent successfully.
function DSX:sendPackage()
    -- Check if the vehicle is completely initialized by verifying rpm
    if not electrics.values.rpm then
        -- Vehicle not completely initialized, skip sending package
        return
    end

    -- Log vehicle name and its current seating status
    -- log("I", "dsx", string.format("Vehicle: %s, Seated: %s", vehicle.config.mainPartName, playerInfo.firstPlayerSeated))

    if not playerInfo.firstPlayerSeated then
        return
    end

    -- Handle DSX instructions
    self:processDSXInstructions()
end

--- Updates graphics and sends DSX package periodically.
-- @param dt Delta time since last update.
function DSX:updateGFX(dt)

    -- Increment the timer with delta time and reset if it exceeds TIMER_MAX
    self.timer = (self.timer + dt) % CONFIG.TIMER_MAX
    self.timeMs = math_floor(self.timer * 1000)

    -- Send the DSX data package
    self:sendPackage()
end

function DSX:validateConfig()
    -- Validate temperature thresholds
    if CONFIG.TEMPERATURE.TEMP_WARNING <= CONFIG.TEMPERATURE.TEMP_PULSE then
        log("E", "dsx", "Invalid temperature thresholds: warning must be higher than pulse")
        return false
    end

    -- Validate rev limiter times
    if CONFIG.REV_LIMITER_CUT_TIME.MIN >= CONFIG.REV_LIMITER_CUT_TIME.MAX then
        log("E", "dsx", "Invalid rev limiter cut time range")
        return false
    end

    return true
end

-- ============================
--       PUBLIC INTERFACE
-- ============================

local M = {}

--- Handles extension loading.
-- @return Boolean indicating if extension loaded successfully.
function M.onExtensionLoaded()
    local dsx = DSX:new()
    if not dsx then
        log("E", "dsx", "DSX failed to initialize.")
        return false
    end

    -- Expose the DSX instance for use in updateGFX
    M.dsx = dsx
    return true
end

--- Handles extension unloading.
function M.onExtensionUnloaded()
    if M.dsx then
        if M.dsx.udpDSXSocket then
            M.dsx.udpDSXSocket:close()
        end
        M.dsx = nil
    end
end

--- Updates graphics. To be called periodically.
-- @param dt Delta time since last update.
function M.updateGFX(dt)
    if M.dsx then
        M.dsx:updateGFX(dt)
    end
end

return M