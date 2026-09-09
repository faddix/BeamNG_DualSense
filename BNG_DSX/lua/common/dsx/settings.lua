-- Shared by game-engine Lua and vehicle Lua; no UI, networking or settings globals
-- The menu uses these definitions, so validation limits only need to be maintained here
local M = {}

M.fields = {
    {key="DSX_IP", label="DSX IPv4 address", group="Connection", kind="text", description="Use 127.0.0.1 when DSX runs on this PC."},
    {key="DSX_PORT", label="UDP port", group="Connection", kind="number", min=1, max=65535, step=1},
    {key="CONTROLLER_INDEX", label="Controller index (first = 0)", group="Connection", kind="number", min=0, max=3, step=1},
    {key="ADAPTIVE_TRIGGERS_ENABLED", label="Enable adaptive triggers", group="Adaptive triggers", kind="boolean"},
    {key="TRIGGER_FORCE.RUNNING", label="Running-engine brake resistance", group="Adaptive triggers", kind="number", min=0, max=8, step=1},
    {key="TRIGGER_FORCE.NOT_RUNNING", label="Engine-off brake resistance", group="Adaptive triggers", kind="number", min=0, max=8, step=1},
    {key="TRIGGER_EFFECT.ABS_STRENGTH", label="ABS strength", group="Adaptive triggers", kind="number", min=0, max=8, step=1},
    {key="TRIGGER_EFFECT.SLIP_STRENGTH", label="Maximum wheel-slip strength", group="Adaptive triggers", kind="number", min=0, max=8, step=1},
    {key="TRIGGER_EFFECT.SLIP_SENSITIVITY", label="Wheel-slip sensitivity", group="Adaptive triggers", kind="number", min=0, max=5, step=0.05},
    {key="TRIGGER_EFFECT.ABS_FREQUENCY", label="ABS frequency (Hz)", group="Adaptive triggers", kind="number", min=1, max=255, step=1},
    {key="TRIGGER_EFFECT.SLIP_FREQUENCY", label="Wheel-slip base frequency (Hz)", group="Adaptive triggers", kind="number", min=1, max=255, step=1},
    {key="LED_CONFIG.ENABLED", label="Enable RPM lightbar", group="RPM lightbar", kind="boolean"},
    {key="LED_CONFIG.BRIGHTNESS", label="Brightness multiplier", group="RPM lightbar", kind="number", min=0, max=1, step=0.01},
    {key="LED_CONFIG.RPM_START", label="Start at fraction of maximum RPM", group="RPM lightbar", kind="number", min=0, max=0.95, step=0.01},
    {key="LED_CONFIG.RPM_HUE_FACTOR", label="Hue offset", group="RPM lightbar", kind="number", min=0, max=5, step=0.01},
    {key="LED_CONFIG.RPM_HUE_SCALE", label="Hue scaling", group="RPM lightbar", kind="number", min=0, max=5, step=0.01},
    {key="LED_CONFIG.RPM_CLAMP_LOW", label="Minimum hue", group="RPM lightbar", kind="number", min=0, max=1, step=0.01},
    {key="LED_CONFIG.RPM_CLAMP_HIGH", label="Maximum hue", group="RPM lightbar", kind="number", min=0, max=1, step=0.01},
    {key="LED_CONFIG.REV_LIMITER_ENABLED", label="Flash near the rev limiter", group="Rev limiter", kind="boolean"},
    {key="LED_CONFIG.TARGET_RPM_DECREMENT_ON", label="Flash entry margin below max RPM", group="Rev limiter", kind="number", min=0, max=0.5, step=0.001},
    {key="LED_CONFIG.TARGET_RPM_DECREMENT_OFF", label="Flash exit margin below max RPM", group="Rev limiter", kind="number", min=0, max=0.5, step=0.001},
    {key="REV_LIMITER_CUT_TIME.DEFAULT", label="Fallback flash interval (ms)", group="Rev limiter", kind="number", min=10, max=2000, step=1},
    {key="REV_LIMITER_CUT_TIME.MIN", label="Minimum engine flash interval (ms)", group="Rev limiter", kind="number", min=10, max=2000, step=1},
    {key="REV_LIMITER_CUT_TIME.MAX", label="Maximum engine flash interval (ms)", group="Rev limiter", kind="number", min=10, max=2000, step=1},
    {key="GEAR_LEDS_ENABLED", label="Enable gear player LEDs", group="Gear LEDs", kind="boolean", description="Keeps the existing five-light mapping, including reverse and gears above 10."},
    {key="TEMPERATURE.ENABLED", label="Enable temperature warning", group="Engine warnings", kind="boolean"},
    {key="TEMPERATURE.TEMP_PULSE", label="Pulse above temperature (C)", group="Engine warnings", kind="number", min=0, max=300, step=1},
    {key="TEMPERATURE.TEMP_WARNING", label="Solid warning above temperature (C)", group="Engine warnings", kind="number", min=0, max=300, step=1},
    {key="STALL_LED_CONFIG.ENABLED", label="Flash when stalled", group="Engine warnings", kind="boolean"},
    {key="STALL_LED_CONFIG.FLASH_INTERVAL_MS", label="Stall flash interval (ms)", group="Engine warnings", kind="number", min=20, max=5000, step=1},
    {key="CHECK_ENGINE_LED_CONFIG.ENABLED", label="Fade for check-engine/dead engine", group="Engine warnings", kind="boolean"},
    {key="CHECK_ENGINE_LED_CONFIG.FADE_INTERVAL_MS", label="Check-engine fade cycle (ms)", group="Engine warnings", kind="number", min=20, max=5000, step=1},
    {key="LOW_FUEL_CONFIG.ENABLED", label="Enable low-fuel warning", group="Engine warnings", kind="boolean", description="Temperature warnings take priority over low fuel."},
    {key="LOW_FUEL_CONFIG.FLASH_INTERVAL_MS", label="Low-fuel flash interval (ms)", group="Engine warnings", kind="number", min=20, max=5000, step=1},
    {key="TURN_SIGNALS_ENABLED", label="Show turn signals on the lightbar", group="Turn signals", kind="boolean", description="Uses the vehicle's indicator timing; overrides driving RPM colors."},
    {key="LED_CONFIG.TURN_SIGNAL_COLOR", label="Turn-signal color", group="Turn signals", kind="color"},
    {key="NETWORK.CACHE_STATE", label="Skip unchanged controller commands", group="Network", kind="boolean", description="Turn off to restore continuous full packets if your DSX version needs them."},
    {key="NETWORK.RESYNC_INTERVAL", label="Full-state refresh interval (seconds)", group="Network", kind="number", min=0.1, max=10, step=0.1},
    {key="NETWORK.MIN_PACKET_INTERVAL", label="Minimum packet interval (seconds)", group="Network", kind="number", min=0.008333333333333333, max=1, step=0.001, description="Default is 1/60 second: at most 60 packets per second."},
    {key="MAX_RETRIES", label="Send attempts before a longer cooldown", group="Network", kind="number", min=1, max=10, step=1},
    {key="NETWORK.RETRY_COOLDOWN", label="Retry cooldown (seconds)", group="Network", kind="number", min=0.01, max=5, step=0.01},
}

local function getPath(config, path)
    local value = config
    for key in path:gmatch("[^.]+") do value = value[key] end
    return value
end

local function setPath(config, path, value)
    local parent = config
    local prefix, name = path:match("^(.*)%.([^.]+)$")
    if prefix then
        for key in prefix:gmatch("[^.]+") do parent = parent[key] end
    else
        name = path
    end
    parent[name] = value
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

function M.getDefaults(config)
    local values = {}
    for _, field in ipairs(M.fields) do
        local value = getPath(config, field.key)
        if field.kind == "color" then
            value = string.format("#%02x%02x%02x", value.x, value.y, value.z)
        end
        values[field.key] = value
    end
    return values
end

local function normalizeIP(value)
    if type(value) ~= "string" then return nil end
    local a, b, c, d = value:match("^%s*(%d+)%.(%d+)%.(%d+)%.(%d+)%s*$")
    if not a then return nil end
    local parts = {a, b, c, d}
    for index, part in ipairs(parts) do
        if #part > 3 or tonumber(part) > 255 then return nil end
        parts[index] = tostring(tonumber(part))
    end
    return table.concat(parts, ".")
end

function M.validate(config, input)
    if type(input) ~= "table" then return nil, {_general="Settings must be an object."} end
    local result, errors, known = M.getDefaults(config), {}, {}
    for _, field in ipairs(M.fields) do
        local key = field.key
        known[key] = true
        local value = input[key]
        if value == nil then value = result[key] end
        if key == "DSX_IP" then
            value = normalizeIP(value)
            if not value then errors[key] = "Enter four IPv4 numbers from 0 to 255, for example 127.0.0.1." end
        elseif field.kind == "number" then
            if type(value) == "string" then value = tonumber(value) end
            if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
                errors[key] = "Enter a finite number."
            elseif value < field.min or value > field.max or (field.step == 1 and value % 1 ~= 0) then
                errors[key] = "Enter " .. (field.step == 1 and "an integer" or "a number") .. " from " .. field.min .. " to " .. field.max .. "."
            end
        elseif field.kind == "boolean" then
            if type(value) ~= "boolean" then errors[key] = "Choose enabled or disabled." end
        elseif field.kind == "color" then
            if type(value) ~= "string" or not value:match("^#%x%x%x%x%x%x$") then
                errors[key] = "Enter a color as #RRGGBB."
            else
                value = value:lower()
            end
        end
        result[key] = value
    end
    for key in pairs(input) do
        if not known[key] then errors._general = "Unknown setting: " .. tostring(key) end
    end
    -- Related values must agree. Reject the entire Apply to avoid partial updates
    local function ordered(low, high, strict, message)
        if errors[low] or errors[high] then return end
        if result[low] > result[high] or (strict and result[low] == result[high]) then
            errors[low], errors[high] = message, message
        end
    end
    ordered("TEMPERATURE.TEMP_PULSE", "TEMPERATURE.TEMP_WARNING", true, "Solid warning must be higher than pulse temperature.")
    ordered("REV_LIMITER_CUT_TIME.MIN", "REV_LIMITER_CUT_TIME.MAX", true, "Maximum flash interval must be higher than minimum.")
    ordered("LED_CONFIG.RPM_CLAMP_LOW", "LED_CONFIG.RPM_CLAMP_HIGH", false, "Maximum hue must be at least minimum hue.")
    ordered("LED_CONFIG.TARGET_RPM_DECREMENT_ON", "LED_CONFIG.TARGET_RPM_DECREMENT_OFF", false, "Exit margin must be at least the entry margin.")
    if next(errors) then return nil, errors end
    return result, {}
end

function M.buildConfig(defaultConfig, values)
    local config = copy(defaultConfig)
    for _, field in ipairs(M.fields) do
        local value = values[field.key]
        if field.kind == "color" then
            -- Replace the whole vector so cached vec3 defaults are never mutated
            value = {x=tonumber(value:sub(2,3),16), y=tonumber(value:sub(4,5),16), z=tonumber(value:sub(6,7),16)}
        end
        setPath(config, field.key, value)
    end
    return config
end

function M.getOverrides(config, values)
    local defaults, overrides = M.getDefaults(config), {}
    for key, value in pairs(values) do
        if value ~= defaults[key] then overrides[key] = value end
    end
    return overrides
end

return M
