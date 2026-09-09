-- ============================
--        BNG_DSX.lua
-- ============================
-- Vehicle-Lua DSX integration. The DSX class owns telemetry, effects and UDP
-- dsx/config.lua supplies defaults; the small GE bridge owns persistent settings/UI

require('auto/types')
local jsonEnc = require('libs/lunajson/lunajson').encode
local socket = require('socket')
local defaultConfig = require('dsx/config')
local settingSchema = require('dsx/settings')
local CONFIG = settingSchema.buildConfig(defaultConfig, settingSchema.getDefaults(defaultConfig))

local InstructionType = {
    Invalid = 0,
    TriggerUpdate = 1,
    RGBUpdate = 2,
    PlayerLED = 3,
    TriggerThreshold = 4,
    MicLED = 5
}
local Trigger = { Invalid = 0, Left = 1, Right = 2 }
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
local MicLEDMode = { On = 0, Pulse = 1, Off = 2 }

local math_min, math_max, math_floor = math.min, math.max, math.floor
local function clamp(n, low, high)
    return math_min(math_max(n, low), high)
end

-- Missing electrics are inactive. Some vehicles publish numbers and others booleans
local function toBoolean(value)
    return value == true or (type(value) == 'number' and value == value and value ~= 0)
end

local function number(value, fallback)
    if value == true then return 1 end
    if value == false then return 0 end
    if type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge then
        return value
    end
    return fallback or 0
end

local function HSVtoRGB(h, s, value)
    local i = math_floor(h * 6)
    local f = h * 6 - i
    local p = value * (1 - s)
    local q = value * (1 - f * s)
    local t = value * (1 - (1 - f) * s)
    local r, g, b
    i = i % 6
    if i == 0 then
        r, g, b = value, t, p
    elseif i == 1 then
        r, g, b = q, value, p
    elseif i == 2 then
        r, g, b = p, value, t
    elseif i == 3 then
        r, g, b = p, q, value
    elseif i == 4 then
        r, g, b = t, p, value
    else
        r, g, b = value, p, q
    end
    return math_floor(r * 255), math_floor(g * 255), math_floor(b * 255)
end

-- ============================
--          DSX CLASS
-- ============================

local requestSettings
local vehicleObject = rawget(_G, 'obj')
local serialize = rawget(_G, 'serialize')
local v = rawget(_G, 'v')
local DSX = {}
DSX.__index = DSX

function DSX:createInstruction(slot, p1, p2, p3, p4, p5, p6)
    local instruction = self.instructions[slot]
    local parameters = instruction.parameters
    parameters[1], parameters[2], parameters[3] = p1, p2, p3
    parameters[4], parameters[5], parameters[6] = p4, p5, p6
    return instruction
end

function DSX:new()
    local instance = setmetatable({}, self)
    instance.ip, instance.port = CONFIG.DSX_IP, CONFIG.DSX_PORT
    instance.instructions = {
        { type = InstructionType.RGBUpdate,     parameters = {} },
        { type = InstructionType.PlayerLED,     parameters = {} },
        { type = InstructionType.TriggerUpdate, parameters = {} },
        { type = InstructionType.TriggerUpdate, parameters = {} },
        { type = InstructionType.MicLED,        parameters = {} }
    }
    instance.lastSent = { {}, {}, {}, {}, {} }
    instance.outgoing, instance.outgoingSlots = {}, {}
    instance.packet = { instructions = instance.outgoing }
    instance.timer, instance.timeMs = 0, 0
    instance.lastChangedLed, instance.targetRPM = 0, 0
    instance.ledsOn, instance.stallLedsOn = true, false
    instance.settingsReady, instance.wasSeated = false, false
    instance.nextSendTime, instance.lastFullSendTime = 0, 0
    instance.nextSettingsRequest = 0
    instance.forceFull = true
    instance.failedAttempts = 0
    instance.engineCached = false
    instance.nextEngineLookup = 0
    instance.lastError = nil
    -- Open lazily after the GE bridge supplies saved settings and this vehicle is active
    return instance
end

function DSX:closeSocket()
    if self.udpDSXSocket then
        self.udpDSXSocket:close()
        self.udpDSXSocket = nil
    end
end

function DSX:invalidateState()
    self.forceFull = true
    self.nextSendTime = 0
    self.failedAttempts = 0
end

function DSX:recordSendFailure(now, err)
    self.lastError = tostring(err or 'UDP send failed')
    self.failedAttempts = self.failedAttempts + 1
    -- A failed burst backs off for at least one second. Retry attempts occur on later graphics frames
    local delay = math_max(CONFIG.NETWORK.RETRY_COOLDOWN, CONFIG.NETWORK.MIN_PACKET_INTERVAL)
    if self.failedAttempts >= CONFIG.MAX_RETRIES then
        self.failedAttempts = 0
        delay = math_max(delay, CONFIG.NETWORK.RESYNC_INTERVAL, 1)
    end
    self.nextSendTime = now + delay
    if not self.lastErrorLogTime or now - self.lastErrorLogTime >= 5 then
        self.lastErrorLogTime = now
        log('W', 'BNG_DSX', self.lastError)
    end
end

function DSX:openSocket(now)
    if self.udpDSXSocket then return true end
    local udp, err = socket.udp()
    if not udp then
        self:recordSendFailure(now, err or 'Could not create UDP socket')
        return false
    end
    local ok, timeoutError = udp:settimeout(0)
    if not ok then
        udp:close()
        self:recordSendFailure(now, timeoutError or 'Could not make UDP socket nonblocking')
        return false
    end
    self.udpDSXSocket = udp
    log("I", "dsx", string.format("DSX v%s initialized for: %s:%d", CONFIG.VERSION, self.ip, self.port))
    return true
end

-- Kept as a separate method, but one call makes exactly one nonblocking attempt
function DSX:sendWithRetries(socketObj, data, ip, port, now)
    local bytesSent, err = socketObj:sendto(data, ip, port)
    if not bytesSent then
        self:recordSendFailure(now, err)
        return false
    end
    self.lastPacketTime = now
    self.lastError = nil
    self.failedAttempts = 0
    self.nextSendTime = now + CONFIG.NETWORK.MIN_PACKET_INTERVAL
    return true
end

function DSX:sendInstructionPacket(instructions, now)
    local full = self.forceFull or not CONFIG.NETWORK.CACHE_STATE
        or now - self.lastFullSendTime >= CONFIG.NETWORK.RESYNC_INTERVAL
    local count = 0
    for slot = 1, #instructions do
        local current = instructions[slot].parameters
        local previous = self.lastSent[slot]
        local changed = full or #current ~= #previous
        if not changed then
            for index = 1, #current do
                if current[index] ~= previous[index] then
                    changed = true
                    break
                end
            end
        end
        if changed then
            count = count + 1
            self.outgoing[count] = instructions[slot]
            self.outgoingSlots[count] = slot
        end
    end
    for index = #self.outgoing, count + 1, -1 do
        self.outgoing[index], self.outgoingSlots[index] = nil, nil
    end
    if count == 0 then return false end
    if not self:openSocket(now) then return false end
    local encoded = jsonEnc(self.packet)
    -- Use the effective configured port, including changes from the UI
    if not self:sendWithRetries(self.udpDSXSocket, encoded, self.ip, self.port, now) then return false end
    -- Copy successful values; referring to the mutable desired table would hide changes
    for index = 1, count do
        local previous = self.lastSent[self.outgoingSlots[index]]
        local current = self.outgoing[index].parameters
        for parameter = 1, 6 do previous[parameter] = current[parameter] end
    end
    if full then self.lastFullSendTime = now end
    self.forceFull = false
    return true
end

function DSX:getEngineInfo()
    if not self.engineCached or (not self.engine and self.timer >= self.nextEngineLookup) then
        self.engine = powertrain.getDevice('mainEngine')
            or powertrain.getDevice('rearMotor') or powertrain.getDevice('frontMotor')
        self.engineCached = true
        -- An early load/status request can precede powertrain initialization
        self.nextEngineLookup = self.timer + 1
    end
    return self.engine
end

function DSX:isEngineStalled()
    local values = self.values
    return number(values.ignitionLevel) == 2
        and not toBoolean(values.engineRunning) and math_floor(number(values.rpm)) <= 0
end

function DSX:setRGB(r, g, b)
    self:createInstruction(1, CONFIG.CONTROLLER_INDEX, r, g, b)
end

function DSX:setPlayerLEDs(one, two, three, four, five)
    self:createInstruction(2, CONFIG.CONTROLLER_INDEX, one, two, three, four, five)
end

function DSX:setLeftTrigger(mode, start, strength, frequency)
    self:createInstruction(3, CONFIG.CONTROLLER_INDEX, Trigger.Left, mode, start, strength, frequency)
end

function DSX:setRightTrigger(mode, start, strength, frequency)
    self:createInstruction(4, CONFIG.CONTROLLER_INDEX, Trigger.Right, mode, start, strength, frequency)
end

function DSX:setMicLED(mode)
    self:createInstruction(5, CONFIG.CONTROLLER_INDEX, mode)
end

function DSX:generatePlayerNotSeatedPacket()
    local rgb, leds = CONFIG.ND_RGB, CONFIG.ND_PLAYER_LED
    self:setRGB(rgb.x, rgb.y, rgb.z)
    self:setPlayerLEDs(leds.light1, leds.light2, leds.light3, leds.light4, leds.light5)
    self:setLeftTrigger(TriggerMode.Normal, 0, 0, 0)
    self:setRightTrigger(TriggerMode.Normal, 0, 0, 0)
    self:setMicLED(MicLEDMode.Off)
    return self.instructions
end

function DSX:toggleLED(config, ledState, lastChanged, flashInterval)
    if self.timeMs - lastChanged > flashInterval then
        lastChanged, ledState = self.timeMs, not ledState
    end
    return ledState, lastChanged, ledState and config.RGB_ON or config.RGB_OFF
end

function DSX:calculateFade(timeMs, interval)
    local phase = (timeMs % interval) / interval
    return (math.sin(phase * 2 * math.pi) + 1) / 2
end

function DSX:generateEngineDeadPacket()
    local config = CONFIG.CHECK_ENGINE_LED_CONFIG
    local fade = self:calculateFade(self.timeMs, config.FADE_INTERVAL_MS)
    self:setRGB(config.RGB_MIN.x + (config.RGB_MAX.x - config.RGB_MIN.x) * fade,
        config.RGB_MIN.y + (config.RGB_MAX.y - config.RGB_MIN.y) * fade,
        config.RGB_MIN.z + (config.RGB_MAX.z - config.RGB_MIN.z) * fade)
    self:setLeftTrigger(TriggerMode.Resistance, 0, CONFIG.TRIGGER_FORCE.NOT_RUNNING)
    self:setRightTrigger(TriggerMode.Normal, 0, 0, 0)
    self:setMicLED(self:checkEngineTemperature())
    self:generateGearLightsPacket(self.values.gearIndex)
    return self.instructions
end

function DSX:generateEngineStalledPacket()
    local rgb
    self.stallLedsOn, self.lastChangedLed, rgb = self:toggleLED(CONFIG.STALL_LED_CONFIG,
        self.stallLedsOn, self.lastChangedLed, CONFIG.STALL_LED_CONFIG.FLASH_INTERVAL_MS)
    self:setRGB(rgb.x, rgb.y, rgb.z)
    self:setLeftTrigger(TriggerMode.Resistance, 0, CONFIG.TRIGGER_FORCE.NOT_RUNNING)
    self:setRightTrigger(TriggerMode.Normal, 0, 0, 0)
    self:setMicLED(self:checkEngineTemperature())
    self:generateGearLightsPacket(self.values.gearIndex)
    return self.instructions
end

function DSX:generateDrivingPacket(maxRPM, cutTime)
    local values = self.values
    local maxLongSlip = 0
    if CONFIG.ADAPTIVE_TRIGGERS_ENABLED and drivetrain and drivetrain.wheels then
        for _, wheel in pairs(drivetrain.wheels) do
            if toBoolean(wheel.isPropulsed) then
                maxLongSlip = math_max(maxLongSlip, number(wheel.lastSlip))
            end
        end
    end
    local effects = CONFIG.TRIGGER_EFFECT
    local slip = math_max(maxLongSlip - 1, 0) * effects.SLIP_SENSITIVITY
    local slipScale = effects.SLIP_STRENGTH / 7
    local running, hasABS = toBoolean(values.engineRunning), toBoolean(values.hasABS)
    local rightStrength = toBoolean(values.clutch) and 0
        or (toBoolean(values.gearIndex) and running and clamp(slip, 0, 7) * slipScale or 0)
    local leftStrength = hasABS and clamp(number(values.absActive), 0, 1) * effects.ABS_STRENGTH
        or clamp(slip * 2, 0, 7) * slipScale
    local slipFrequency = clamp(effects.SLIP_FREQUENCY + math_floor(maxLongSlip), 1, 255)
    local leftFrequency = hasABS and effects.ABS_FREQUENCY or slipFrequency
    if leftStrength > 1 then
        self:setLeftTrigger(TriggerMode.AutomaticGun, 0, leftStrength, leftFrequency)
    else
        self:setLeftTrigger(TriggerMode.Resistance, 0,
            running and CONFIG.TRIGGER_FORCE.RUNNING or CONFIG.TRIGGER_FORCE.NOT_RUNNING)
    end
    self:setRightTrigger(TriggerMode.AutomaticGun, 0, rightStrength, slipFrequency)
    self:setMicLED(self:checkEngineTemperature())
    -- Some engines have no maxRPM or report zero. Their LEDs stay off without division by zero
    local rpmPercent = maxRPM > 0 and clamp(number(values.rpm) / maxRPM, 0, 1) or 0
    self:generateRPMLEDs(rpmPercent, maxRPM, cutTime)
    self:generateGearLightsPacket(values.gearIndex)
    return self.instructions
end

function DSX:generateNoEnginePresentPacket()
    local rgb, leds = CONFIG.NE_RGB, CONFIG.NE_PLAYER_LED
    self:setRGB(rgb.x, rgb.y, rgb.z)
    self:setPlayerLEDs(leds.light1, leds.light2, leds.light3, leds.light4, leds.light5)
    self:setLeftTrigger(TriggerMode.Resistance, 1, CONFIG.TRIGGER_FORCE.NOT_RUNNING)
    self:setRightTrigger(TriggerMode.Normal, 0, 0, 0)
    self:setMicLED(MicLEDMode.Off)
    return self.instructions
end

function DSX:generateRPMLEDs(rpmPercent, maxRPM, cutTime)
    local values, led = self.values, CONFIG.LED_CONFIG
    local turnSignal = CONFIG.TURN_SIGNALS_ENABLED
        and (toBoolean(values.signal_left_input) or toBoolean(values.signal_right_input))
    if turnSignal then
        local rgb = led.TURN_SIGNAL_COLOR
        if toBoolean(values.signal_L) or toBoolean(values.signal_R) then
            self:setRGB(rgb.x, rgb.y, rgb.z)
        else
            self:setRGB(0, 0, 0)
        end
        return
    end
    if not led.ENABLED or maxRPM <= 0 then
        self:setRGB(0, 0, 0)
        return
    end
    local scaledRPM = clamp((rpmPercent - led.RPM_START) / (1 - led.RPM_START), 0, 1)
    local hue = clamp(led.RPM_HUE_FACTOR - scaledRPM * led.RPM_HUE_SCALE, led.RPM_CLAMP_LOW, led.RPM_CLAMP_HIGH)
    if self.ledsOn or not led.REV_LIMITER_ENABLED then
        self:setRGB(HSVtoRGB(hue, 1, scaledRPM * led.BRIGHTNESS))
    else
        self:setRGB(0, 0, 0)
    end
    if led.REV_LIMITER_ENABLED and number(values.rpm) >= self.targetRPM then
        self.targetRPM = maxRPM - maxRPM * led.TARGET_RPM_DECREMENT_OFF
        if self.timeMs - self.lastChangedLed > cutTime then
            self.lastChangedLed, self.ledsOn = self.timeMs, not self.ledsOn
        end
    else
        self.ledsOn = true
        self.targetRPM = maxRPM - maxRPM * led.TARGET_RPM_DECREMENT_ON
    end
end

function DSX:generateGearLightsPacket(gear)
    gear = number(gear)
    if gear > 10 then gear = gear % 10 end
    self:setPlayerLEDs((gear >= 1 and gear <= 5) or gear <= -1,
        (gear >= 2 and gear <= 6) or gear < -1,
        (gear >= 3 and gear <= 7) or gear == 10,
        (gear >= 4 and gear <= 8) or gear < -1,
        (gear >= 5 and gear <= 9) or gear <= -1)
end

function DSX:checkEngineTemperature()
    local temp = number(self.values.watertemp)
    if CONFIG.TEMPERATURE.ENABLED and temp >= CONFIG.TEMPERATURE.TEMP_WARNING then
        return MicLEDMode.On
    elseif CONFIG.TEMPERATURE.ENABLED and temp >= CONFIG.TEMPERATURE.TEMP_PULSE then
        return MicLEDMode.Pulse
    elseif CONFIG.LOW_FUEL_CONFIG.ENABLED and toBoolean(self.values.lowfuel) then
        local interval = CONFIG.LOW_FUEL_CONFIG.FLASH_INTERVAL_MS
        return self.timeMs % (interval * 2) < interval and MicLEDMode.On or MicLEDMode.Off
    end
    return MicLEDMode.Off
end

function DSX:processDSXInstructions(now)
    local engine = self:getEngineInfo()
    local maxRPM, cutTime = 0, CONFIG.REV_LIMITER_CUT_TIME.DEFAULT
    if engine then
        maxRPM = math_max(0, number(engine.maxRPM))
        if type(engine.revLimiterCutTime) == 'number' then
            cutTime = clamp(number(engine.revLimiterCutTime) * 1000,
                CONFIG.REV_LIMITER_CUT_TIME.MIN, CONFIG.REV_LIMITER_CUT_TIME.MAX)
        end
    end
    local vehicleName = v and v.config and v.config.mainPartName
    if vehicleName == 'unicycle' then
        self:generatePlayerNotSeatedPacket()
    elseif engine and CONFIG.CHECK_ENGINE_LED_CONFIG.ENABLED and toBoolean(self.values.checkengine) then
        self:generateEngineDeadPacket()
    elseif engine and CONFIG.STALL_LED_CONFIG.ENABLED and self:isEngineStalled() then
        self:generateEngineStalledPacket()
    elseif engine then
        self:generateDrivingPacket(maxRPM, cutTime)
    else
        self:generateNoEnginePresentPacket()
    end
    if not CONFIG.ADAPTIVE_TRIGGERS_ENABLED then
        self:setLeftTrigger(TriggerMode.Normal, 0, 0, 0)
        self:setRightTrigger(TriggerMode.Normal, 0, 0, 0)
    end
    if not CONFIG.GEAR_LEDS_ENABLED then self:setPlayerLEDs(false, false, false, false, false) end
    return self:sendInstructionPacket(self.instructions, now)
end

function DSX:sendPackage(now)
    if not self.settingsReady or not playerInfo.firstPlayerSeated then return end
    self.values = electrics and electrics.values
    if not self.values then return end
    -- Test time before wheel scans, effect generation and JSON encoding, including idle states
    if now < self.nextSendTime then return end
    self.nextSendTime = now + CONFIG.NETWORK.MIN_PACKET_INTERVAL
    return self:processDSXInstructions(now)
end

function DSX:updateGFX(dt)
    self.timer = self.timer + math_max(0, number(dt))
    self.timeMs = math_floor(self.timer * 1000)
    local now = socket.gettime()
    if self.lastClockTime and now < self.lastClockTime then
        self:invalidateState()
        self.lastErrorLogTime = nil
    end
    if not self.settingsReady and playerInfo.firstPlayerSeated and now >= self.nextSettingsRequest then
        requestSettings()
    end
    self.lastClockTime = now
    self:sendPackage(now)
end

-- Send one best-effort neutral packet to the old target before changing controller, or unloading while still seated
-- Never retry it after another vehicle takes over
function DSX:releaseController()
    if not self.settingsReady or not playerInfo.firstPlayerSeated or not self.udpDSXSocket then return end
    self:setRGB(0, 0, 0)
    self:setPlayerLEDs(false, false, false, false, false)
    self:setLeftTrigger(TriggerMode.Normal, 0, 0, 0)
    self:setRightTrigger(TriggerMode.Normal, 0, 0, 0)
    self:setMicLED(MicLEDMode.Off)
    for slot = 1, 5 do self.outgoing[slot] = self.instructions[slot] end
    self.udpDSXSocket:sendto(jsonEnc(self.packet), self.ip, self.port)
end

-- ============================
--       PUBLIC INTERFACE
-- ============================

local M = {}

requestSettings = function()
    if M.dsx then M.dsx.nextSettingsRequest = socket.gettime() + 1 end
    -- Vehicle Lua has no GE settings owner. BeamNG's supported queue crosses VMs
    vehicleObject:queueGameEngineLua("extensions.load('dsxSettings'); extensions.dsxSettings.requestVehicleSettings(" ..
        vehicleObject:getID() .. ")")
end

function M.applySettings(values)
    local normalized, errors = settingSchema.validate(defaultConfig, values)
    if not normalized then return false, errors end
    local effective = settingSchema.buildConfig(defaultConfig, normalized)
    local dsx = M.dsx
    if dsx then
        local targetChanged = effective.DSX_IP ~= dsx.ip or effective.DSX_PORT ~= dsx.port
            or effective.CONTROLLER_INDEX ~= CONFIG.CONTROLLER_INDEX
        if targetChanged then
            dsx:releaseController()
            dsx:closeSocket()
        end
        CONFIG = effective
        dsx.ip, dsx.port = CONFIG.DSX_IP, CONFIG.DSX_PORT
        dsx.settingsReady = true
        dsx:invalidateState()
    else
        CONFIG = effective
    end
    return true
end

function M.reconnect()
    if not M.dsx then return end
    M.dsx:closeSocket()
    M.dsx:invalidateState()
end

function M.requestStatus()
    local dsx = M.dsx
    local values = electrics and electrics.values or {}
    local engine = dsx and dsx:getEngineInfo()
    local status = {
        active = dsx ~= nil and dsx.settingsReady and playerInfo.firstPlayerSeated,
        socketActive = dsx ~= nil and dsx.udpDSXSocket ~= nil,
        engine = engine and (engine.name or engine.type or 'engine') or 'none',
        rpm = number(values.rpm),
        gear = number(values.gearIndex),
        ip = dsx and dsx.ip or CONFIG.DSX_IP,
        port = dsx and dsx.port or CONFIG.DSX_PORT,
        error = dsx and dsx.lastError or nil
    }
    vehicleObject:queueGameEngineLua('if extensions.dsxSettings then extensions.dsxSettings.receiveStatus('
        .. vehicleObject:getID() .. ',' .. serialize(status) .. ') end')
end

function M.onExtensionLoaded()
    if M.dsx then
        M.dsx:releaseController(); M.dsx:closeSocket()
    end
    M.dsx = DSX:new()
    M.dsx.wasSeated = playerInfo.firstPlayerSeated
    requestSettings()
    return true
end

function M.onExtensionUnloaded()
    if M.dsx then
        M.dsx:releaseController()
        M.dsx:closeSocket()
        M.dsx = nil
    end
end

function M.onPlayersChanged()
    local dsx = M.dsx
    if not dsx then return end
    local seated = playerInfo.firstPlayerSeated
    if seated == dsx.wasSeated then return end
    dsx.wasSeated = seated
    dsx:invalidateState()
    dsx:closeSocket()
    if seated then
        dsx.settingsReady = false
        dsx.engineCached = false
        requestSettings()
    end
end

function M.onReset()
    if M.dsx then
        M.dsx.engineCached = false
        M.dsx.engine = nil
        M.dsx.targetRPM, M.dsx.lastChangedLed = 0, M.dsx.timeMs
        M.dsx.ledsOn, M.dsx.stallLedsOn = true, false
        M.dsx:invalidateState()
    end
end

function M.updateGFX(dt)
    if M.dsx then M.dsx:updateGFX(dt) end
end

return M
