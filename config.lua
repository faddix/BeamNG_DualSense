-- ============================
--        CONFIGURATION
-- ============================

-- Configuration variables for the DSX extension
return {
    VERSION = "2.38",           -- Extension version
    DSX_IP = "127.0.0.1",       -- IP address of the DSX server
    DSX_PORT = 6969,            -- Port number of the DSX server
    CONTROLLER_INDEX = 0,       -- Controller index (0 for first controller, 1 for second controller, etc.)
    TRIGGER_FORCE = {           -- Brake trigger force (to simulate power brakes)
        NOT_RUNNING = 8,        -- Brake trigger force when engine is not running
        RUNNING = 1,            -- Brake trigger force when engine is running
    },
    REV_LIMITER_CUT_TIME = {
        DEFAULT = 100,          -- Default rev limiter cut time
        MIN = 30,               -- Minimum rev limiter cut time
        MAX = 200               -- Maximum rev limiter cut time
    },
    LED_CONFIG = {
        RPM_HUE_FACTOR = 1.2,               -- Factor to multiply RPM by to get hue
        RPM_HUE_SCALE = 1.3,                -- Scale to apply to hue
        RPM_CLAMP_LOW = 0,                  -- Lower bound for RPM clamping
        RPM_CLAMP_HIGH = 0.33,              -- Upper bound for RPM clamping
        TARGET_RPM_DECREMENT_OFF = 0.06,    -- Decrement for target RPM after threshold is met
        TARGET_RPM_DECREMENT_ON = 0.053     -- Decrement for target RPM before threshold is met
    },
    STALL_LED_CONFIG = {                    -- Configuration for Stalling LEDs
        FLASH_INTERVAL_MS = 500,            -- Interval for flashing stalling LEDs in milliseconds
        RGB_ON = vec3(255, 255, 255),       -- RGB color when LEDs are on (white)
        RGB_OFF = vec3(0, 0, 0)             -- RGB color when LEDs are off
    },
    CHECK_ENGINE_LED_CONFIG = {
        FADE_INTERVAL_MS = 750,             -- Time for one complete fade cycle in milliseconds
        RGB_MAX = vec3(255, 0, 0),          -- Maximum RGB color (red)
        RGB_MIN = vec3(0, 0, 0)             -- Minimum RGB color (off)
    },
    ND_RGB = vec3(0, 64, 128),  -- RGB color when the player is not driving
    ND_PLAYER_LED = {           -- Player LEDs state when player is not driving
        light1 = false,
        light2 = false,
        light3 = true,
        light4 = false,
        light5 = false
    },
    NE_RGB = vec3(128, 0, 0),   -- RGB color when no engine is present (gray)
    NE_PLAYER_LED = {           -- Player LEDs state when no engine is present
        light1 = false,
        light2 = false,
        light3 = false,
        light4 = false,
        light5 = false
    },
    TIMER_MAX = 36000,          -- Maximum timer value
    MAX_RETRIES = 3,            -- Maximum number of retries for network sends
    TEMPERATURE = {
        TEMP_WARNING = 115,     -- Temperature critical threshold (°C)
        TEMP_PULSE = 108,       -- Temperature warning threshold (°C)
    },
    NETWORK = {
        MIN_PACKET_INTERVAL = 1/60, -- Minimum time between packets (60hz max)
        RETRY_COOLDOWN = 0.1,       -- Time to wait between retries
    }
}