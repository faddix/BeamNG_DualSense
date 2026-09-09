-- Game-engine Lua: owns preferences and forwards validated snapshots to vehicle Lua
-- The vehicle extension and the UI app both load this bridge on demand
local M = {}
local defaults = require("dsx/config")
local schema = require("dsx/settings")
local settingsKey = "BNG_DSX_CONFIG"
local profilesKey = "BNG_DSX_PROFILES"
local profiles, profilesLoaded
local values, loadErrors
local be = rawget(_G, "be")
local serialize = rawget(_G, "serialize")
local settings = rawget(_G, "settings")
local log = rawget(_G, "log")
local guihooks = rawget(_G, "guihooks")
local setExtensionUnloadMode = rawget(_G, "setExtensionUnloadMode")

local function readSettings()
    local saved = settings.getValue(settingsKey)
    if saved == nil then
        saved = {}
        saved.DSX_IP = settings.getValue("BNG_DSX_IP", settings.getValue("dsxIP"))
        saved.DSX_PORT = settings.getValue("BNG_DSX_PORT", settings.getValue("dsxPort"))
    end
    local valid, errors = schema.validate(defaults, saved)
    if valid then
        values, loadErrors = valid, {}
        return
    end

    -- Invalid stored values fall back safely, without silently rewriting the user's file
    -- Keep valid independent overrides; restore related invalid fields as a group
    local repaired, factory = {}, schema.getDefaults(defaults)
    if type(saved) == "table" then
        for _, field in ipairs(schema.fields) do repaired[field.key] = saved[field.key] end
    end
    for key in pairs(errors) do repaired[key] = factory[key] end
    values = schema.validate(defaults, repaired) or schema.validate(defaults, factory)
    loadErrors = errors
    log("W", "BNG_DSX", "Invalid saved DSX settings; using defaults for invalid fields. Open DSX Settings to review.")
end

local function ensureSettings()
    if not values then readSettings() end
end

local function currentVehicle()
    return be:getPlayerVehicle(0)
end

local function pushSettings(vehicle)
    if vehicle and values then
        -- Automatic loading of the auto directory uses its basename, BNG_DSX
        vehicle:queueLuaCommand("local dsx = extensions.BNG_DSX; if dsx then dsx.applySettings(" ..
            serialize(values) .. ") end")
    end
end

-- Profiles are independent saved snapshots. Loading one only fills the UI draft
-- Apply & Save remains the single operation that changes the running vehicle
local function readProfiles()
    profiles = settings.getValue(profilesKey)
    if profiles == nil then profiles = {} end
    profilesLoaded = true
end

local function ensureProfiles()
    if not profilesLoaded then readProfiles() end
end

local function normalizeProfileName(name)
    if type(name) ~= "string" or name:find("%c") then
        return nil, "Use a name without control characters."
    end
    name = name:match("^%s*(.-)%s*$")
    if #name == 0 then return nil, "Enter a profile name." end
    if #name > 40 then return nil, "Use a shorter profile name." end
    return name
end

local function profileNames()
    ensureProfiles()
    local names = {}
    if type(profiles) ~= "table" then return names end
    for name in pairs(profiles) do
        -- Keep broken snapshots visible, so they can still be replaced or deleted
        if normalizeProfileName(name) == name and type(name) == "string" then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

local function profileWarning()
    ensureProfiles()
    if type(profiles) ~= "table" then
        return "Saved profiles are not a valid object. They have been preserved; profile changes are unavailable until the saved data is repaired."
    end
    local seen = {}
    for name, snapshot in pairs(profiles) do
        local normalized = normalizeProfileName(name)
        local valid = schema.validate(defaults, snapshot)
        if not normalized or normalized ~= name or not valid or seen[normalized:lower()] then
            return "Some saved profiles are invalid or have duplicate names. They have been preserved; replace or delete the affected profiles when possible."
        end
        seen[normalized:lower()] = true
    end
    return ""
end

-- Echo each caller's optional ID so delayed replies or other app instances cannot replace the wrong form
-- Older direct callers can continue to omit the ID
local function profileResult(requestId, action, ok, name, message, errors, snapshot)
    guihooks.trigger("DSXProfileResult", {
        action = action,
        requestId = requestId,
        ok = ok,
        name = name,
        names = profileNames(),
        values = snapshot,
        message = message or "",
        errors = errors,
        profileWarning = profileWarning()
    })
    return ok
end

local function findProfile(name)
    -- Prefer the exact spelling in an existing library, then match without case
    if profiles[name] ~= nil then return name end
    for _, storedName in ipairs(profileNames()) do
        if normalizeProfileName(storedName):lower() == name:lower() then return storedName end
    end
end

local function editableProfiles(requestId, action)
    ensureProfiles()
    if type(profiles) == "table" then return true end
    profileResult(requestId, action, false, nil, "No profiles changed.", {_general = profileWarning()})
    return false
end

local function copyProfiles()
    local copy = {}
    -- Copy the outer map only: no operation mutates an existing snapshot
    -- This also retains unrelated malformed entries instead of silently losing them
    for name, snapshot in pairs(profiles) do copy[name] = snapshot end
    return copy
end

local function saveProfiles(requestId, action, updated, name, message)
    local ok, err = pcall(settings.setState, {[profilesKey] = updated})
    if not ok then
        return profileResult(requestId, action, false, name, "BeamNG could not save the profiles.", {_general = tostring(err)})
    end
    -- Commit local copy only after BeamNG accepts the persistent settings update
    profiles = updated
    return profileResult(requestId, action, true, name, message)
end

function M.requestProfiles(requestId)
    return profileResult(requestId, "list", true)
end

function M.saveProfile(name, input, overwrite, requestId)
    if not editableProfiles(requestId, "save") then return false end
    local normalized, nameError = normalizeProfileName(name)
    if not normalized then
        return profileResult(requestId, "save", false, nil, "Profile was not saved.", {_name = nameError})
    end
    local existing = findProfile(normalized)
    if overwrite == true and not existing then
        return profileResult(requestId, "save", false, normalized, "The selected profile no longer exists.", {_name = "Choose an existing profile to update, or use Save new."})
    end
    if existing and overwrite ~= true then
        return profileResult(requestId, "save", false, existing, "A profile with that name already exists.", {_name = "Choose another name, or use Update selected to replace this profile."})
    end
    if not existing and #profileNames() >= 32 then
        return profileResult(requestId, "save", false, normalized, "Profile was not saved.", {_general = "You can save up to 32 profiles. Delete a profile first."})
    end
    local valid, errors = schema.validate(defaults, input)
    if not valid then
        return profileResult(requestId, "save", false, normalized, "Profile was not saved. Please fix the highlighted settings.", errors)
    end
    local updated = copyProfiles()
    local storedName = existing or normalized
    -- Store every validated field, including current defaults, to keep a snapshot
    updated[storedName] = valid
    return saveProfiles(requestId, "save", updated, storedName, "Profile saved. Active settings are unchanged; use Apply & Save to apply the draft.")
end

function M.loadProfile(name, requestId)
    ensureProfiles()
    local normalized, nameError = normalizeProfileName(name)
    if not normalized then
        return profileResult(requestId, "load", false, nil, "Profile was not loaded.", {_name = nameError})
    end
    if type(profiles) ~= "table" then
        return profileResult(requestId, "load", false, normalized, "Profile was not loaded.", {_general = profileWarning()})
    end
    local existing = findProfile(normalized)
    if not existing then
        return profileResult(requestId, "load", false, normalized, "Profile was not found.", {_name = "Choose an existing profile."})
    end
    local valid, errors = schema.validate(defaults, profiles[existing])
    if not valid then
        return profileResult(requestId, "load", false, existing, "This saved profile contains invalid settings and was not loaded.", errors)
    end
    return profileResult(requestId, "load", true, existing, "Profile loaded into the form. Use Apply & Save to activate it.", nil, valid)
end

function M.renameProfile(oldName, newName, requestId)
    if not editableProfiles(requestId, "rename") then return false end
    local oldNormalized, oldError = normalizeProfileName(oldName)
    local normalized, nameError = normalizeProfileName(newName)
    if not oldNormalized or not normalized then
        return profileResult(requestId, "rename", false, nil, "Profile was not renamed.", {_name = oldError or nameError})
    end
    local existing = findProfile(oldNormalized)
    if not existing then
        return profileResult(requestId, "rename", false, oldNormalized, "Profile was not found.", {_name = "Choose an existing profile."})
    end
    local collision = findProfile(normalized)
    if collision and collision ~= existing then
        return profileResult(requestId, "rename", false, existing, "A profile with that name already exists.", {_name = "Choose another profile name."})
    end
    local updated = copyProfiles()
    updated[normalized] = updated[existing]
    if normalized ~= existing then updated[existing] = nil end
    return saveProfiles(requestId, "rename", updated, normalized, "Profile renamed.")
end

function M.deleteProfile(name, requestId)
    if not editableProfiles(requestId, "delete") then return false end
    local normalized, nameError = normalizeProfileName(name)
    if not normalized then
        return profileResult(requestId, "delete", false, nil, "Profile was not deleted.", {_name = nameError})
    end
    local existing = findProfile(normalized)
    if not existing then
        return profileResult(requestId, "delete", false, normalized, "Profile was not found.", {_name = "Choose an existing profile."})
    end
    local updated = copyProfiles()
    updated[existing] = nil
    return saveProfiles(requestId, "delete", updated, existing, "Profile deleted. Active settings are unchanged.")
end

function M.requestState(message, errors)
    ensureSettings()
    guihooks.trigger("DSXSettingsState", {
        values = values or schema.getDefaults(defaults),
        defaults = schema.getDefaults(defaults),
        fields = schema.fields,
        profileNames = profileNames(),
        profileWarning = profileWarning(),
        errors = errors or loadErrors or {},
        message = message or
            (next(loadErrors or {}) and "Some saved values were invalid and reverted to defaults. Review and Apply & Save." or "")
    })
end

function M.apply(input)
    local valid, errors = schema.validate(defaults, input)
    if not valid then
        M.requestState("Nothing changed. Please fix the highlighted settings.", errors)
        return false
    end
    -- Only overrides are saved, so config.lua remains the source of future defaults
    -- The installed GE settings service saves unknown keys in /settings/settings.json
    local overrides = schema.getOverrides(defaults, valid)
    local ok, err = pcall(settings.setState, { [settingsKey] = overrides })
    if not ok then
        M.requestState("BeamNG could not save the settings.", { _general = tostring(err) })
        return false
    end
    values, loadErrors = valid, {}
    pushSettings(currentVehicle())
    M.requestState("Saved. Settings apply to the active vehicle and future vehicles.", {})
    M.requestStatus()
    return true
end

function M.requestVehicleSettings(vehicleId)
    ensureSettings()
    if type(vehicleId) ~= "number" or vehicleId % 1 ~= 0 then return end
    -- A newly loaded vehicle may request settings before it becomes the player vehicle
    pushSettings(be:getObjectByID(vehicleId))
end

function M.receiveStatus(vehicleId, status)
    local vehicle = currentVehicle()
    -- Ignore delayed replies from the vehicle the player has just left
    if vehicle and vehicle:getID() == vehicleId and type(status) == "table" then
        guihooks.trigger("DSXSettingsStatus", status)
    end
end

function M.requestStatus()
    ensureSettings()
    local vehicle = currentVehicle()
    if not vehicle then
        guihooks.trigger("DSXSettingsStatus", {
            active = false,
            socketActive = false,
            engine = "No player vehicle",
            rpm = 0,
            gear = 0,
            ip = values and values.DSX_IP or defaults.DSX_IP,
            port = values and values.DSX_PORT or defaults.DSX_PORT
        })
        return
    end
    local missing = "if extensions.dsxSettings then extensions.dsxSettings.receiveStatus("
        ..
        vehicle:getID() ..
        ", {active=false, socketActive=false, error='DSX vehicle extension is not loaded. Reload the vehicle.'}) end"
    vehicle:queueLuaCommand(
        "local dsx = extensions.BNG_DSX; if dsx then dsx.requestStatus() else obj:queueGameEngineLua("
        .. string.format("%q", missing) .. ") end")
end

function M.reconnect()
    ensureSettings()
    local vehicle = currentVehicle()
    if vehicle then
        pushSettings(vehicle)
        vehicle:queueLuaCommand("local dsx = extensions.BNG_DSX; if dsx then dsx.reconnect(); dsx.requestStatus() end")
    else
        M.requestStatus()
    end
end

function M.onVehicleSwitched(oldId, newId, player)
    if player ~= 0 then return end
    ensureSettings()
    pushSettings(currentVehicle())
    M.requestStatus()
end

function M.onExtensionLoaded()
    -- Preferences belong to the session, so retain the bridge across level changes
    setExtensionUnloadMode(M, "manual")
    readSettings()
    readProfiles()
    return true
end

return M
