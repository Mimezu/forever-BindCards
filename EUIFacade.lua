local _, private = ...

local BindCards = _G.BindCards or private or {}
_G.BindCards = BindCards

-- BindCards ships the small skin surface it uses so every appearance is
-- identical whether EllesmereUI is present or not. This implementation uses
-- Blizzard primitives and BindCards' bundled shell artwork.
local S = { apiVersion = 1 }
BindCards.EUIFacade = S

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"

local FALLBACK_ACCENT = { 12 / 255, 210 / 255, 157 / 255 }
local CLASS_ACCENTS = {
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    DEMONHUNTER = { 0.64, 0.19, 0.79 },
    DRUID = { 1.00, 0.49, 0.04 },
    EVOKER = { 0.20, 0.58, 0.50 },
    HUNTER = { 0.67, 0.83, 0.45 },
    MAGE = { 0.25, 0.78, 0.92 },
    MONK = { 0.00, 1.00, 0.60 },
    PALADIN = { 0.96, 0.55, 0.73 },
    PRIEST = { 1.00, 1.00, 1.00 },
    ROGUE = { 1.00, 0.96, 0.41 },
    SHAMAN = { 0.00, 0.44, 0.87 },
    WARLOCK = { 0.53, 0.53, 0.93 },
    WARRIOR = { 0.78, 0.61, 0.43 },
}

local THEMES = {
    violetmist = {
        -- Exact source colors anchor the identity; darkened surface mixes and
        -- a lighter mint ink keep small labels legible without flattening states.
        texture = WHITE, crop = { 0, 1, 0, 1 },
        base = { 45/255, 34/255, 55/255 }, wash = 0, band = 0.12,
        panel = { 57/255, 44/255, 67/255, 1 }, inset = { 45/255, 34/255, 55/255, 1 },
        input = { 30/255, 23/255, 38/255, 1 }, inputText = { 242/255, 238/255, 238/255 },
        raised = { 79/255, 63/255, 91/255, 1 },
        headerTop = { 57/255, 44/255, 67/255, 1 }, top = { 75/255, 45/255, 69/255, 1 },
        border = { 186/255, 175/255, 196/255, 0.48 }, accent = { 182/255, 105/255, 160/255 },
        palette = {
            window = { 45/255, 34/255, 55/255, 1 }, panel = { 57/255, 44/255, 67/255, 1 },
            paper = { 45/255, 34/255, 55/255, 1 }, paperAlt = { 39/255, 30/255, 48/255, 1 },
            slot = { 30/255, 23/255, 38/255, 1 }, raised = { 79/255, 63/255, 91/255, 1 },
            border = { 186/255, 175/255, 196/255, 0.48 }, faint = { 186/255, 175/255, 196/255, 0.20 },
            hover = { 89/255, 59/255, 82/255, 1 },
            blue = { 182/255, 105/255, 160/255, 1 }, blueSoft = { 75/255, 45/255, 69/255, 1 },
            teal = { 143/255, 180/255, 180/255, 1 }, drop = { 90/255, 131/255, 131/255, 1 },
            amber = { 225/255, 188/255, 139/255, 1 }, amberMuted = { 170/255, 139/255, 108/255, 1 },
            amberFaint = { 170/255, 139/255, 108/255, 0.30 }, red = { 231/255, 139/255, 153/255, 1 },
            text = { 242/255, 238/255, 238/255, 1 }, topText = { 242/255, 238/255, 238/255, 1 },
            muted = { 186/255, 175/255, 196/255, 1 }, shortcutInactive = { 186/255, 175/255, 196/255, 1 },
        },
    },
    eui = {
        texture = "Interface\\AddOns\\BindCards\\Assets\\SuiteWindowBackdrop.png",
        crop = { 0.25, 1, 0, 0.75 }, wash = 0.62, band = 0.50,
        panel = { 0.08, 0.08, 0.08, 0.92 }, inset = { 0.04, 0.04, 0.04, 0.85 },
        input = { 0.02, 0.02, 0.02, 1 }, raised = { 0.08, 0.08, 0.08, 0.92 },
        border = { 0.20, 0.20, 0.20, 1 }, classAccent = true,
        palette = {
            window = { 0.035, 0.041, 0.052, 0.985 }, panel = { 0.055, 0.063, 0.078, 1 },
            paper = { 0.073, 0.082, 0.098, 1 }, paperAlt = { 0.060, 0.069, 0.084, 1 },
            slot = { 0.060, 0.069, 0.084, 1 },
            raised = { 0.095, 0.108, 0.129, 1 }, border = { 0.20, 0.235, 0.28, 0.72 },
            hover = { 0.12, 0.14, 0.17, 1 },
            faint = { 0.18, 0.21, 0.25, 0.25 }, blueSoft = { 0.18, 0.36, 0.52, 1 },
            drop = { 0.25, 0.90, 0.55, 1 }, amber = { 0.93, 0.66, 0.25, 1 },
            amberMuted = { 0.58, 0.45, 0.25, 0.82 }, amberFaint = { 0.55, 0.40, 0.20, 0.34 },
            red = { 0.88, 0.31, 0.34, 1 }, text = { 0.91, 0.93, 0.96, 1 },
            muted = { 0.59, 0.64, 0.71, 1 }, shortcutInactive = { 0.70, 0.74, 0.81, 1 },
        },
    },
    mimezu = {
        texture = "Interface\\AddOns\\BindCards\\Assets\\SuiteWindowBackdropMimezu.png",
        crop = { 0, 1, 0, 1 }, wash = 0.40, band = 0.42,
        panel = { 0.055, 0.063, 0.078, 1 }, inset = { 0.060, 0.069, 0.084, 1 },
        input = { 0.035, 0.041, 0.052, 0.985 }, raised = { 0.095, 0.108, 0.129, 1 },
        border = { 0.20, 0.235, 0.28, 0.72 }, accent = { 0.27, 0.58, 0.82 },
        palette = {
            window = { 0.035, 0.041, 0.052, 0.985 }, panel = { 0.055, 0.063, 0.078, 1 },
            paper = { 0.073, 0.082, 0.098, 1 }, paperAlt = { 0.060, 0.069, 0.084, 1 },
            slot = { 0.060, 0.069, 0.084, 1 },
            raised = { 0.095, 0.108, 0.129, 1 }, border = { 0.20, 0.235, 0.28, 0.72 },
            hover = { 0.12, 0.14, 0.17, 1 },
            faint = { 0.18, 0.21, 0.25, 0.25 }, blue = { 0.27, 0.58, 0.82, 1 },
            blueSoft = { 0.18, 0.36, 0.52, 1 }, teal = { 0.18, 0.76, 0.70, 1 },
            drop = { 0.25, 0.90, 0.55, 1 }, amber = { 0.93, 0.66, 0.25, 1 },
            amberMuted = { 0.58, 0.45, 0.25, 0.82 }, amberFaint = { 0.55, 0.40, 0.20, 0.34 },
            red = { 0.88, 0.31, 0.34, 1 }, text = { 0.91, 0.93, 0.96, 1 },
            muted = { 0.59, 0.64, 0.71, 1 }, shortcutInactive = { 0.70, 0.74, 0.81, 1 },
        },
    },
    luminous = {
        texture = "Interface\\AddOns\\BindCards\\Assets\\SuiteWindowBackdropLuminous.png",
        crop = { 0, 1, 0, 1 }, wash = 0.22, band = 0.30,
        panel = { 0.14, 0.15, 0.18, 0.94 }, inset = { 0.105, 0.115, 0.14, 0.94 },
        input = { 0.07, 0.075, 0.095, 1 }, raised = { 0.18, 0.195, 0.23, 0.98 },
        border = { 0.36, 0.39, 0.46, 0.92 }, classAccent = true,
        palette = {
            window = { 0.07, 0.075, 0.095, 1 }, panel = { 0.14, 0.15, 0.18, 0.94 },
            paper = { 0.14, 0.15, 0.18, 0.94 }, paperAlt = { 0.105, 0.115, 0.14, 0.94 },
            slot = { 0.105, 0.115, 0.14, 0.94 },
            raised = { 0.18, 0.195, 0.23, 0.98 }, border = { 0.36, 0.39, 0.46, 0.92 },
            hover = { 0.23, 0.245, 0.285, 1 },
            faint = { 0.36, 0.39, 0.46, 0.30 },
            drop = { 0.25, 0.90, 0.55, 1 }, amber = { 0.96, 0.72, 0.31, 1 },
            amberMuted = { 0.66, 0.52, 0.30, 0.88 }, amberFaint = { 0.62, 0.47, 0.25, 0.38 },
            red = { 0.94, 0.38, 0.42, 1 }, text = { 0.96, 0.97, 0.99, 1 },
            muted = { 0.72, 0.75, 0.81, 1 }, shortcutInactive = { 0.79, 0.81, 0.86, 1 },
        },
    },
    charcoal = {
        texture = WHITE,
        crop = { 0, 1, 0, 1 }, wash = 0.792, band = 0.18,
        panel = { 0.290, 0.267, 0.271, 0.98 }, inset = { 0.208, 0.212, 0.188, 0.99 },
        input = { 0.141, 0.145, 0.129, 1 }, raised = { 0.357, 0.318, 0.329, 1 },
        border = { 0.616, 0.608, 0.671, 0.82 }, accent = { 0.616, 0.608, 0.671 },
        palette = {
            window = { 0.208, 0.212, 0.188, 0.99 }, panel = { 0.290, 0.267, 0.271, 0.98 },
            paper = { 0.286, 0.282, 0.306, 0.98 }, paperAlt = { 0.251, 0.235, 0.239, 0.98 },
            slot = { 0.251, 0.235, 0.239, 0.98 },
            raised = { 0.357, 0.318, 0.329, 1 }, border = { 0.616, 0.608, 0.671, 0.82 },
            hover = { 0.529, 0.463, 0.490, 1 }, faint = { 0.737, 0.737, 0.718, 0.26 },
            blue = { 0.616, 0.608, 0.671, 1 }, blueSoft = { 0.529, 0.463, 0.490, 1 },
            teal = { 0.616, 0.608, 0.671, 1 }, drop = { 0.74, 0.78, 0.68, 1 },
            amber = { 0.737, 0.737, 0.718, 1 }, amberMuted = { 0.529, 0.463, 0.490, 0.88 },
            amberFaint = { 0.529, 0.463, 0.490, 0.36 }, red = { 0.90, 0.42, 0.43, 1 },
            text = { 0.929, 0.933, 0.933, 1 }, muted = { 0.737, 0.737, 0.718, 1 },
            shortcutInactive = { 0.737, 0.737, 0.718, 1 },
        },
    },
    chalk = {
        texture = WHITE,
        crop = { 0, 1, 0, 1 }, wash = 0.071, band = 0.055,
        panel = { 0.851, 0.855, 0.835, 0.99 }, inset = { 0.929, 0.933, 0.933, 1 },
        input = { 0.965, 0.968, 0.965, 1 }, raised = { 0.616, 0.608, 0.671, 1 },
        inputText = { 0.208, 0.212, 0.188 },
        border = { 0.529, 0.463, 0.490, 0.82 }, accent = { 0.616, 0.608, 0.671 },
        palette = {
            window = { 0.929, 0.933, 0.933, 1 }, panel = { 0.851, 0.855, 0.835, 0.99 },
            paper = { 0.965, 0.968, 0.965, 1 }, paperAlt = { 0.737, 0.737, 0.718, 1 },
            slot = { 0.737, 0.737, 0.718, 1 },
            raised = { 0.616, 0.608, 0.671, 1 }, border = { 0.529, 0.463, 0.490, 0.82 },
            hover = { 0.529, 0.463, 0.490, 1 }, faint = { 0.208, 0.212, 0.188, 0.22 },
            blue = { 0.408, 0.396, 0.459, 1 }, blueSoft = { 0.616, 0.608, 0.671, 1 },
            teal = { 0.435, 0.424, 0.482, 1 }, drop = { 0.23, 0.48, 0.32, 1 },
            amber = { 0.435, 0.396, 0.416, 1 }, amberMuted = { 0.529, 0.463, 0.490, 0.90 },
            amberFaint = { 0.529, 0.463, 0.490, 0.28 }, red = { 0.67, 0.18, 0.21, 1 },
            text = { 0.208, 0.212, 0.188, 1 }, muted = { 0.529, 0.463, 0.490, 1 },
            shortcutInactive = { 0.529, 0.463, 0.490, 1 },
        },
    },
    tungsten = {
        texture = WHITE,
        crop = { 0, 1, 0, 1 }, wash = 0.98, band = 0.30,
        panel = { 0.318, 0.298, 0.271, 0.96 }, inset = { 0.105, 0.105, 0.092, 0.98 },
        input = { 0.020, 0.020, 0.008, 1 }, raised = { 0.365, 0.342, 0.310, 1 },
        border = { 0.588, 0.475, 0.502, 0.86 }, accent = { 0.337, 0.471, 0.498 },
        palette = {
            window = { 0.020, 0.020, 0.008, 0.99 }, panel = { 0.318, 0.298, 0.271, 0.96 },
            paper = { 0.105, 0.105, 0.092, 0.98 }, paperAlt = { 0.075, 0.075, 0.063, 0.98 },
            slot = { 0.075, 0.075, 0.063, 0.98 },
            raised = { 0.365, 0.342, 0.310, 1 }, border = { 0.588, 0.475, 0.502, 0.86 },
            hover = { 0.405, 0.380, 0.345, 1 }, faint = { 0.875, 0.882, 0.855, 0.18 },
            blue = { 0.337, 0.471, 0.498, 1 }, blueSoft = { 0.210, 0.310, 0.330, 1 },
            teal = { 0.337, 0.471, 0.498, 1 }, drop = { 0.46, 0.67, 0.58, 1 },
            amber = { 0.79, 0.63, 0.33, 1 }, amberMuted = { 0.58, 0.47, 0.28, 0.86 },
            amberFaint = { 0.50, 0.39, 0.22, 0.34 }, red = { 0.82, 0.34, 0.38, 1 },
            text = { 0.875, 0.882, 0.855, 1 }, muted = { 0.588, 0.475, 0.502, 1 },
            shortcutInactive = { 0.588, 0.620, 0.610, 1 },
        },
    },
    editorial = {
        texture = WHITE,
        crop = { 0, 1, 0, 1 }, wash = 0.902, band = 0.34,
        panel = { 0.125, 0.149, 0.157, 0.98 }, inset = { 0.086, 0.106, 0.114, 0.99 },
        input = { 0.055, 0.067, 0.071, 1 }, raised = { 0.510, 0.478, 0.376, 1 },
        border = { 0.745, 0.741, 0.702, 0.84 }, accent = { 0.647, 0.569, 0.455 },
        palette = {
            window = { 0.086, 0.106, 0.114, 0.99 }, panel = { 0.125, 0.149, 0.157, 0.98 },
            paper = { 0.157, 0.180, 0.184, 0.98 }, paperAlt = { 0.105, 0.129, 0.137, 0.99 },
            slot = { 0.105, 0.129, 0.137, 0.99 },
            raised = { 0.510, 0.478, 0.376, 1 }, border = { 0.745, 0.741, 0.702, 0.84 },
            hover = { 0.647, 0.569, 0.455, 1 }, faint = { 0.745, 0.741, 0.702, 0.20 },
            blue = { 0.647, 0.569, 0.455, 1 }, blueSoft = { 0.322, 0.282, 0.224, 1 },
            teal = { 0.647, 0.569, 0.455, 1 }, drop = { 0.66, 0.76, 0.62, 1 },
            amber = { 0.78, 0.62, 0.34, 1 }, amberMuted = { 0.510, 0.478, 0.376, 0.90 },
            amberFaint = { 0.510, 0.478, 0.376, 0.34 }, red = { 0.83, 0.36, 0.38, 1 },
            text = { 0.929, 0.922, 0.918, 1 }, muted = { 0.745, 0.741, 0.702, 1 },
            shortcutInactive = { 0.745, 0.741, 0.702, 1 },
        },
    },
    snes = {
        texture = WHITE,
        crop = { 0, 1, 0, 1 }, base = { 0.835, 0.827, 0.784 }, wash = 0.018, band = 0.055,
        panel = { 0.790, 0.784, 0.745, 0.99 }, inset = { 0.710, 0.698, 0.690, 1 },
        input = { 0.245, 0.239, 0.255, 1 }, raised = { 0.630, 0.615, 0.640, 1 },
        top = { 0.596, 0.565, 0.765, 1 },
        border = { 0.275, 0.196, 0.565, 0.96 }, accent = { 0.275, 0.196, 0.565 },
        palette = {
            window = { 0.690, 0.678, 0.650, 0.99 }, panel = { 0.790, 0.784, 0.745, 0.99 },
            paper = { 0.835, 0.827, 0.784, 1 }, paperAlt = { 0.742, 0.731, 0.706, 1 },
            slot = { 0.245, 0.239, 0.255, 1 },
            raised = { 0.630, 0.615, 0.640, 1 }, border = { 0.275, 0.196, 0.565, 0.96 },
            hover = { 0.596, 0.565, 0.765, 1 }, faint = { 0.275, 0.196, 0.565, 0.24 },
            blue = { 0.275, 0.196, 0.565, 1 }, blueSoft = { 0.596, 0.565, 0.765, 1 },
            teal = { 0.275, 0.196, 0.565, 1 }, drop = { 0.25, 0.48, 0.34, 1 },
            amber = { 0.455, 0.396, 0.690, 1 }, amberMuted = { 0.596, 0.565, 0.765, 0.94 },
            amberFaint = { 0.596, 0.565, 0.765, 0.32 }, red = { 0.66, 0.18, 0.25, 1 },
            text = { 0.125, 0.118, 0.145, 1 }, muted = { 0.335, 0.318, 0.365, 1 },
            shortcutInactive = { 0.455, 0.396, 0.690, 1 },
        },
    },
    famicom = {
        texture = WHITE,
        crop = { 0, 1, 0, 1 }, base = { 0.945, 0.890, 0.775 }, wash = 0.012, band = 0.035,
        panel = { 0.910, 0.842, 0.710, 0.99 }, inset = { 0.965, 0.920, 0.825, 1 },
        input = { 0.125, 0.120, 0.110, 1 }, raised = { 0.860, 0.780, 0.645, 1 },
        headerTop = { 0.945, 0.890, 0.775, 1 }, top = { 0.545, 0.055, 0.105, 1 },
        border = { 0.350, 0.035, 0.065, 0.96 }, accent = { 0.545, 0.055, 0.105 },
        palette = {
            window = { 0.945, 0.890, 0.775, 0.99 }, panel = { 0.910, 0.842, 0.710, 0.99 },
            paper = { 0.965, 0.920, 0.825, 1 }, paperAlt = { 0.860, 0.780, 0.645, 1 },
            slot = { 0.125, 0.120, 0.110, 1 },
            raised = { 0.860, 0.780, 0.645, 1 }, border = { 0.350, 0.035, 0.065, 0.96 },
            hover = { 0.675, 0.145, 0.175, 1 }, faint = { 0.350, 0.035, 0.065, 0.24 },
            blue = { 0.545, 0.055, 0.105, 1 }, blueSoft = { 0.675, 0.145, 0.175, 1 },
            teal = { 0.180, 0.390, 0.245, 1 }, drop = { 0.260, 0.520, 0.310, 1 },
            amber = { 0.690, 0.455, 0.120, 1 }, amberMuted = { 0.560, 0.390, 0.165, 0.92 },
            amberFaint = { 0.560, 0.390, 0.165, 0.30 }, red = { 0.690, 0.080, 0.105, 1 },
            text = { 0.250, 0.055, 0.055, 1 }, muted = { 0.390, 0.285, 0.225, 1 },
            shortcutInactive = { 0.390, 0.285, 0.225, 1 },
            topText = { 0.985, 0.940, 0.835, 1 },
        },
    },
}
-- A separate, higher-color variant; never mutate the original Violet Mist.
-- Readability pass: keep palette accents, but separate quiet control surfaces
-- from selected tabs and give secondary labels their own contrasting ink.
THEMES.chalk.raised = { 0.80, 0.785, 0.835, 1 }
THEMES.chalk.palette.raised = THEMES.chalk.raised
THEMES.chalk.palette.hover = { 0.73, 0.71, 0.78, 1 }
THEMES.chalk.palette.blueSoft = { 0.77, 0.75, 0.82, 1 }
THEMES.chalk.palette.muted = { 0.28, 0.25, 0.29, 1 }
THEMES.chalk.palette.teal = { 0.30, 0.28, 0.36, 1 }
THEMES.chalk.tabSelection = { 0.39, 0.36, 0.46, 1 }
THEMES.chalk.tabInk = { 0.98, 0.98, 0.98, 1 }

THEMES.tungsten.panel = { 0.23, 0.215, 0.20, 1 }
THEMES.tungsten.palette.panel = THEMES.tungsten.panel
THEMES.tungsten.raised = { 0.29, 0.26, 0.25, 1 }
THEMES.tungsten.palette.raised = THEMES.tungsten.raised
THEMES.tungsten.palette.hover = { 0.35, 0.29, 0.31, 1 }
THEMES.tungsten.palette.muted = { 0.86, 0.80, 0.81, 1 }
THEMES.tungsten.palette.blue = { 0.58, 0.76, 0.77, 1 }
THEMES.tungsten.palette.teal = { 0.58, 0.76, 0.77, 1 }
THEMES.tungsten.tabSelection = { 0.40, 0.55, 0.57, 1 }
THEMES.tungsten.tabInk = { 0.025, 0.025, 0.02, 1 }

THEMES.editorial.raised = { 0.27, 0.28, 0.25, 1 }
THEMES.editorial.palette.raised = THEMES.editorial.raised
THEMES.editorial.palette.hover = { 0.30, 0.29, 0.25, 1 }
THEMES.editorial.palette.blue = { 0.82, 0.74, 0.60, 1 }
THEMES.editorial.palette.teal = { 0.82, 0.74, 0.60, 1 }
THEMES.editorial.tabSelection = { 0.647, 0.569, 0.455, 1 }
THEMES.editorial.tabInk = { 0.055, 0.065, 0.065, 1 }

local vivid = {}
-- Console plastics stay neutral; saturated controls carry selection/priority.
THEMES.snes.base = { 0.83, 0.83, 0.84 }
THEMES.snes.panel = { 0.77, 0.77, 0.79, 1 }
THEMES.snes.inset = { 0.70, 0.70, 0.73, 1 }
THEMES.snes.raised = { 0.68, 0.65, 0.81, 1 }
THEMES.snes.border = { 0.43, 0.43, 0.48, 1 }
THEMES.snes.headerTop = THEMES.snes.panel
THEMES.snes.top = { 0.70, 0.70, 0.73, 1 }
THEMES.snes.palette.window = { 0.69, 0.69, 0.72, 1 }
THEMES.snes.palette.panel = THEMES.snes.panel
THEMES.snes.palette.paper = { 0.83, 0.83, 0.84, 1 }
THEMES.snes.palette.paperAlt = THEMES.snes.top
THEMES.snes.palette.raised = THEMES.snes.raised
THEMES.snes.palette.border = THEMES.snes.border
THEMES.snes.palette.faint = { 0.43, 0.43, 0.48, 0.45 }
THEMES.snes.palette.muted = { 0.29, 0.28, 0.34, 1 }
THEMES.snes.tabSelection = { 0.275, 0.196, 0.565, 1 }
THEMES.snes.tabInk = { 0.98, 0.98, 1, 1 }
THEMES.snes.primaryHover = { 0.36, 0.27, 0.64, 1 }
THEMES.snes.palette.blueSoft = THEMES.snes.tabSelection

THEMES.famicom.raised = { 0.92, 0.86, 0.75, 1 }
THEMES.famicom.palette.raised = THEMES.famicom.raised
THEMES.famicom.top = THEMES.famicom.raised
THEMES.famicom.palette.paperAlt = THEMES.famicom.raised
THEMES.famicom.border = { 0.57, 0.48, 0.36, 1 }
THEMES.famicom.palette.border = THEMES.famicom.border
THEMES.famicom.palette.hover = { 0.86, 0.77, 0.63, 1 }
THEMES.famicom.tabSelection = { 0.545, 0.055, 0.105, 1 }
THEMES.famicom.tabInk = { 0.985, 0.940, 0.835, 1 }
THEMES.famicom.primaryHover = { 0.64, 0.09, 0.15, 1 }
THEMES.famicom.palette.blueSoft = THEMES.famicom.tabSelection
THEMES.famicom.palette.topText = nil

for key, value in pairs(THEMES.violetmist) do vivid[key] = value end
vivid.palette = {}
for key, value in pairs(THEMES.violetmist.palette) do vivid.palette[key] = value end
vivid.headerTop = { 57/255, 94/255, 94/255, 1 }
vivid.nativeTop = true
vivid.top = { 182/255, 105/255, 160/255, 1 }
vivid.panel = { 45/255, 67/255, 71/255, 1 }
vivid.raised = { 115/255, 55/255, 98/255, 1 }
vivid.border = { 90/255, 131/255, 131/255, 1 }
vivid.palette.panel = vivid.panel
vivid.palette.raised = vivid.raised
vivid.palette.border = vivid.border
vivid.palette.paperAlt = { 46/255, 68/255, 72/255, 1 }
vivid.palette.hover = { 130/255, 63/255, 111/255, 1 }
vivid.palette.blueSoft = vivid.raised
vivid.palette.topText = { 26/255, 17/255, 32/255, 1 }
THEMES.violetbloom = vivid

local activeTheme = "eui"
-- Console-inspired colors, tuned for UI contrast rather than colorimetry of
-- photographed plastic. Each theme owns its palette and restores independently.
local function RGB(hex)
    return { tonumber(hex:sub(1,2),16)/255, tonumber(hex:sub(3,4),16)/255,
        tonumber(hex:sub(5,6),16)/255, 1 }
end
local function ConsoleTheme(spec)
    local theme = { texture = WHITE, crop = {0,1,0,1}, wash = 0, band = 0.08, palette = {} }
    for key, color in pairs(THEMES.mimezu.palette) do theme.palette[key] = color end
    for key, hex in pairs(spec) do theme.palette[key] = RGB(hex) end
    local p = theme.palette
    theme.base, theme.panel, theme.inset = p.window, p.panel, p.paperAlt
    theme.input, theme.raised, theme.border = p.slot, p.raised, p.border
    theme.accent, theme.headerTop, theme.top = p.blue, p.panel, p.paperAlt
    theme.tabSelection, theme.tabInk, theme.primaryHover = p.blueSoft, p.topText, p.drop
    return theme
end
THEMES.legacy = ConsoleTheme({
    window="17110B", panel="21190F", paper="21190F", paperAlt="17110B",
    slot="100C08", raised="302314", hover="46321C", border="79603A",
    faint="493923", blue="FFD100", blueSoft="59401B", teal="8FBF78",
    drop="83DB95", amber="E4B767", amberMuted="A18550", amberFaint="675335",
    red="E55B50", text="EEE3CE", muted="BBA98C", shortcutInactive="BAA88A", topText="FFF3CC",
})
-- Blizzard Legacy marks active cards and tabs in the class color (gold stays
-- the selection color).
THEMES.legacy.classActiveAccent = true
THEMES.legacy.classActiveBlend = 0.45
THEMES.gamecube = ConsoleTheme({
    window="30244F", panel="49376F", paper="382956", paperAlt="292236",
    slot="17151D", raised="554578", hover="665188", border="9A94AD",
    text="F0EFF4", muted="E0DCE8", shortcutInactive="C7C3D2",
    blue="B9ACEE", blueSoft="CBCBD1", topText="251D36", drop="DEDEE3",
    teal="7CC9AE", amber="F1CF58", red="F08E96", faint="625673",
})
THEMES.genesis = ConsoleTheme({
    window="050505", panel="111111", paper="090909", paperAlt="191919",
    slot="000000", raised="292929", hover="393939", border="626262",
    text="F4F4F4", muted="C7C7C7", shortcutInactive="C7C7C7",
    blue="CB6355", blueSoft="801C12", topText="FFF5F0", drop="9D291B",
    teal="D3D3D3", amber="E4BE65", red="FFA18C", faint="424242",
})
THEMES.ps1 = ConsoleTheme({
    window="94959F", panel="A7A7B0", paper="B7B7BF", paperAlt="9697A1",
    slot="35363E", raised="A6A7B2", hover="B6B7C0", border="696A77",
    text="22232A", muted="2C2D35", shortcutInactive="C3C5D5",
    blue="4C6289", blueSoft="575863", topText="F4F4F7", drop="656671",
    teal="235A4F", amber="6B4918", red="913E4A", faint="777987",
})
THEMES.ps2 = ConsoleTheme({
    window="101112", panel="202123", paper="171719", paperAlt="27272B",
    slot="08090B", raised="333338", hover="42434B", border="60626B",
    text="F0F0F4", muted="C3C4CE", shortcutInactive="C3C4CE",
    blue="7D9CCF", blueSoft="303C63", topText="F2F3F7", drop="3C4B78",
    teal="83BFC3", amber="E9C06D", red="F092AE", faint="414248",
})
THEMES.xbox = ConsoleTheme({
    window="090C0A", panel="141A16", paper="101512", paperAlt="1D231F",
    slot="050706", raised="282F2A", hover="333D35", border="5C755E",
    text="EDF4EA", muted="BACDB5", shortcutInactive="BACDB5",
    blue="A3E743", blueSoft="8DD52D", topText="15200D", drop="B0EE50",
    teal="A3E743", amber="E7CB76", red="F0978A", faint="3C5140",
})
THEMES.xbox360 = ConsoleTheme({
    window="D7DAD5", panel="E8EBE5", paper="F2F4EF", paperAlt="CED4CA",
    slot="30382F", raised="CCD5C6", hover="B7C7AD", border="7A8970",
    text="253020", muted="43513B", shortcutInactive="C6D8BC",
    blue="647F25", blueSoft="9DBD48", topText="202812", drop="B0CE60",
    teal="356322", amber="78551B", red="9A3E39", faint="98A88C",
})

local function Theme(theme)
    return THEMES[theme] or THEMES[activeTheme]
end

-- The player's class color ({r, g, b, 1}); Blizzard's table first.
local function ClassColor()
    local classFile = UnitClass and select(2, UnitClass("player"))
    if issecretvalue and issecretvalue(classFile) then classFile = nil end
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color and color.r then return { color.r, color.g, color.b, 1 } end
    local accent = classFile and CLASS_ACCENTS[classFile]
    return accent and { accent[1], accent[2], accent[3], 1 } or nil
end

-- "Active" accent (tab dots, active bars, Active labels): the class color on
-- themes with classActiveAccent, otherwise the palette's teal. Pure class
-- colors are loud on dark bronze, so blend toward the theme's muted tone.
local function ActiveAccent(theme)
    local color = theme.classActiveAccent and ClassColor()
    if not color then return theme.palette.teal end
    local tone, amount = theme.palette.amberMuted, theme.classActiveBlend or 0
    if tone and amount > 0 then
        for index = 1, 3 do color[index] = color[index] * (1 - amount) + tone[index] * amount end
    end
    return color
end

local function Accent(themeName)
    local theme = Theme(themeName)
    if theme.accent then return theme.accent end
    local classFile = UnitClass and select(2, UnitClass("player"))
    if issecretvalue and issecretvalue(classFile) then classFile = nil end
    return classFile and CLASS_ACCENTS[classFile] or FALLBACK_ACCENT
end

local function ApplyColor(texture, color)
    if texture and texture.SetColorTexture then texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1) end
end

local function TabStyle(theme, selected, active, disabled)
    if theme.tabSelection then
        if selected and not disabled then return theme.tabSelection, theme.tabInk, theme.palette.blue end
        return theme.palette.paperAlt, active and not disabled and theme.palette.text or theme.palette.muted,
            active and not disabled and ActiveAccent(theme) or theme.palette.border
    end
    if theme ~= vivid then return end
    if disabled then return theme.palette.paperAlt, theme.palette.muted, theme.palette.faint end
    if selected then return theme.top, theme.palette.topText, theme.palette.muted end
    return theme.palette.window, active and theme.palette.text or theme.palette.muted,
        active and theme.palette.teal or theme.palette.faint
end

local function TopSurfaceColor(theme, kind, tabState)
    if kind == "header" and theme.headerTop then return theme.headerTop end
    if tabState then
        local color = TabStyle(theme, tabState.selected, tabState.active, tabState.disabled)
        if color then return color end
    end
    return theme.top or theme.raised
end

function S.GetTabStyle(selected, active, disabled)
    return TabStyle(Theme(), selected, active, disabled)
end

function S.GetAbilityLabelColor()
    if Theme().tabSelection then return { 0.98, 0.98, 0.98, 1 } end
end

function S.GetPrimaryButtonStyle(hovered)
    local theme = Theme()
    if theme.primaryHover then
        return hovered and theme.primaryHover or theme.tabSelection, theme.tabInk
    end
end

function S.GetNativeTopColor(kind)
    local theme = Theme()
    if theme.nativeTop then return TopSurfaceColor(theme, kind) end
end

local state = setmetatable({}, { __mode = "k" })
function S.GetVisualState(frame)
    return state[frame] or {}
end
local lookCallbacks = {}
local shadowFont

local function Data(object)
    local data = state[object]
    if not data then data = {}; state[object] = data end
    return data
end

local function Forbidden(object)
    return not object or (object.IsForbidden and object:IsForbidden())
end

local function Texture(parent, layer, r, g, b, a, sublevel)
    if not (parent and parent.CreateTexture) then return nil end
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
    if texture and texture.SetColorTexture and r then texture:SetColorTexture(r, g, b, a or 1) end
    return texture
end

local function DisablePixelSnap(texture)
    if texture and texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
    if texture and texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
end

local function OnePixel(frame)
    local physicalSize = _G.GetPhysicalScreenSize
    local physicalHeight = physicalSize and select(2, physicalSize())
    local effectiveScale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    if issecretvalue and (issecretvalue(physicalHeight) or issecretvalue(effectiveScale)) then return 1 end
    if type(physicalHeight) ~= "number" or physicalHeight <= 0 or
        type(effectiveScale) ~= "number" or effectiveScale <= 0 then
        return 1
    end
    return (768 / physicalHeight) / effectiveScale
end

local function FadeRegions(frame, keep)
    if Forbidden(frame) or not frame.GetRegions then return end
    for index = 1, select("#", frame:GetRegions()) do
        local region = select(index, frame:GetRegions())
        if region and region.IsObjectType and region:IsObjectType("Texture") and
            not (keep and keep[region]) and region.SetAlpha then
            region:SetAlpha(0)
        end
    end
    if frame.NineSlice then FadeRegions(frame.NineSlice, keep) end
end
S.FadeRegions = FadeRegions

local NINE_SLICE_PARTS = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}
function S.FadeNineSlice(nineSlice)
    if not nineSlice then return end
    FadeRegions(nineSlice)
    for _, key in ipairs(NINE_SLICE_PARTS) do
        local part = nineSlice[key]
        if part and part.SetAlpha then part:SetAlpha(0) end
    end
    if nineSlice.SetAlpha then nineSlice:SetAlpha(0) end
end

local function AddBorder(frame, color)
    if Forbidden(frame) then return end
    local data = Data(frame)
    if data.border then return end
    local c = color or Theme().border
    local pixel = OnePixel(frame)
    local container = CreateFrame and CreateFrame("Frame", nil, frame)
    if not container then return end
    container:SetAllPoints(frame)
    if container.SetFrameLevel and frame.GetFrameLevel then container:SetFrameLevel(frame:GetFrameLevel()) end
    local function BorderTexture()
        local texture = Texture(container, "BORDER", nil, nil, nil, nil, -7)
        if texture then
            texture:SetTexture(WHITE)
            texture:SetVertexColor(c[1], c[2], c[3], c[4])
            DisablePixelSnap(texture)
        end
        return texture
    end
    local top = BorderTexture()
    local bottom = BorderTexture()
    local left = BorderTexture()
    local right = BorderTexture()
    if not (top and bottom and left and right) then return end
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(pixel)
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(pixel)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -pixel)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, pixel); left:SetWidth(pixel)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -pixel)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, pixel); right:SetWidth(pixel)
    data.border = container
    data.borderTextures = { top, bottom, left, right }
    data.borderColor = color
end

function S.GetStyle()
    return activeTheme
end

function S.GetAccentColor()
    local color = Accent()
    return color[1], color[2], color[3]
end

function S.GetPanelColor()
    local panel = Theme().panel
    return panel[1], panel[2], panel[3], panel[4]
end

function S.GetInputTextColor()
    local color = Theme().inputText
    if color then return color[1], color[2], color[3], 1 end
    return 1, 1, 1, 1
end

function S.GetPalette(themeName)
    local theme = Theme(themeName)
    local source, result = theme.palette, {}
    for key, color in pairs(source) do
        result[key] = { color[1], color[2], color[3], color[4] }
    end
    if theme.classAccent then
        local accent = Accent(themeName)
        result.blue = { accent[1], accent[2], accent[3], 1 }
        result.teal = { accent[1], accent[2], accent[3], 1 }
        if theme == THEMES.luminous then
            result.blueSoft = { accent[1] * 0.48, accent[2] * 0.48, accent[3] * 0.48, 1 }
        end
    end
    if theme.classActiveAccent then
        local color = ActiveAccent(theme)
        if color then result.teal = { color[1], color[2], color[3], 1 } end
    end
    return result
end

function S.GetFont()
    return FONT, ""
end

function S.IsEnabled()
    return true
end

function S.OnLooksChanged(callback)
    if type(callback) == "function" then lookCallbacks[#lookCallbacks + 1] = callback end
end

local BG_ASPECT = 561 / 433
local function UpdateShellCrop(frame, texture)
    if not (frame and frame.GetSize and texture and texture.SetTexCoord) then return end
    local width, height = frame:GetSize()
    if issecretvalue and (issecretvalue(width) or issecretvalue(height)) then return end
    if not width or width == 0 or not height or height == 0 then return end
    local crop = Theme().crop
    local baseLeft, baseRight, baseTop, baseBottom = crop[1], crop[2], crop[3], crop[4]
    local frameAspect = width / height
    local visibleU, visibleV = baseRight - baseLeft, baseBottom - baseTop
    if frameAspect > BG_ASPECT then
        local croppedV = visibleV * (BG_ASPECT / frameAspect)
        local trim = (visibleV - croppedV) / 2
        texture:SetTexCoord(baseLeft, baseRight, baseTop + trim, baseBottom - trim)
    else
        local croppedU = visibleU * (frameAspect / BG_ASPECT)
        local trim = (visibleU - croppedU) / 2
        texture:SetTexCoord(baseLeft + trim, baseRight - trim, baseTop, baseBottom)
    end
end

local function Repaint()
    local theme = Theme()
    for object, data in pairs(state) do
        if activeTheme == "eui" and
            (data.shell or data.panel or data.button or data.editBox or data.checkbox or data.dropdown) then
            local keep = {}
            for _, key in ipairs({
                "background", "overlay", "modernBackground", "topBar", "bottomBar",
                "panelBackground", "buttonBackground", "buttonHover", "editBackground",
                "checkboxBackground", "dropdownBackground", "dropdownArrow", "closeGlyph",
            }) do
                if data[key] then keep[data[key]] = true end
            end
            for region in pairs(data.buttonKeep or {}) do keep[region] = true end
            if data.checked then keep[data.checked] = true end
            -- SetBackdropColor can re-enable the BackdropTemplate textures
            -- that Shell/Panel/Button originally stripped. Re-strip native
            -- regions before reasserting our owned translucent layers.
            FadeRegions(object, keep)
        end
        if data.background then
            data.background:SetTexture(theme.texture)
            if data.background.SetVertexColor then
                local base = theme.base or { 1, 1, 1 }
                data.background:SetVertexColor(base[1], base[2], base[3], base[4] or 1)
            end
            if activeTheme == "eui" and data.background.SetAlpha then data.background:SetAlpha(1) end
            UpdateShellCrop(object, data.background)
        end
        if data.overlay then
            data.overlay:SetColorTexture(0, 0, 0, theme.wash)
            if activeTheme == "eui" and data.overlay.SetAlpha then data.overlay:SetAlpha(1) end
        end
        if data.topBar then data.topBar:SetColorTexture(0, 0, 0, theme.band) end
        if data.bottomBar then data.bottomBar:SetColorTexture(0, 0, 0, theme.band) end
        if data.panelBackground then
            local color = data.panelShade and { 0, 0, 0, 0.25 } or
                (data.topSurface and TopSurfaceColor(theme, data.topSurface, data.tabState) or
                    (data.panelInset and theme.inset or theme.panel))
            ApplyColor(data.panelBackground, color)
        end
        if data.buttonBackground then
            ApplyColor(data.buttonBackground,
                data.topSurface and TopSurfaceColor(theme, data.topSurface, data.tabState) or
                    (object.bindCardsButtonKind == "primary" and theme.primaryHover and theme.tabSelection) or theme.raised)
        end
        if data.editBackground then ApplyColor(data.editBackground, theme.input) end
        if data.checkboxBackground then ApplyColor(data.checkboxBackground, theme.input) end
        if data.dropdownBackground then ApplyColor(data.dropdownBackground, theme.panel) end
        if data.closeGlyph then
            local color = theme.palette.text
            data.closeGlyph:SetVertexColor(color[1], color[2], color[3], data.closeHovered and 1 or 0.75)
        end
        if data.borderTextures then
            local color = data.borderColor or theme.border
            for _, texture in ipairs(data.borderTextures) do
                texture:SetVertexColor(color[1], color[2], color[3], color[4])
            end
        end
        if data.checked and data.checked.SetVertexColor then data.checked:SetVertexColor(S.GetAccentColor()) end
    end
end

function S.SetTheme(theme)
    activeTheme = THEMES[theme] and theme or "eui"
    Repaint()
    for _, callback in ipairs(lookCallbacks) do pcall(callback, activeTheme) end
    return activeTheme
end

function S.RefreshLooks()
    Repaint()
    for _, callback in ipairs(lookCallbacks) do pcall(callback, activeTheme) end
end

function S.Shell(frame, options)
    if Forbidden(frame) then return end
    local data = Data(frame)
    if data.shell then return end
    data.shell = true
    FadeRegions(frame)

    local background = Texture(frame, "BACKGROUND", nil, nil, nil, nil, -8)
    if background then
        background:SetTexture(Theme().texture)
        if background.SetVertexColor then
            local base = Theme().base or { 1, 1, 1 }
            background:SetVertexColor(base[1], base[2], base[3], base[4] or 1)
        end
        background:SetAllPoints(frame)
        data.background = background
        UpdateShellCrop(frame, background)
        if hooksecurefunc then
            hooksecurefunc(frame, "SetSize", function() UpdateShellCrop(frame, background) end)
            hooksecurefunc(frame, "SetWidth", function() UpdateShellCrop(frame, background) end)
            hooksecurefunc(frame, "SetHeight", function() UpdateShellCrop(frame, background) end)
        end
    end
    local overlay = Texture(frame, "BACKGROUND", 0, 0, 0, Theme().wash, -7)
    if overlay then overlay:SetAllPoints(frame); data.overlay = overlay end
    local modernBackground = Texture(frame, "BACKGROUND", 0, 0, 0, 0, -6)
    if modernBackground then modernBackground:SetAllPoints(frame); data.modernBackground = modernBackground end
    if not (options and options.noTopBar) then
        local topBar = Texture(frame, "BACKGROUND", 0, 0, 0, Theme().band, -5)
        if topBar then
            topBar:SetPoint("TOPLEFT"); topBar:SetPoint("TOPRIGHT"); topBar:SetHeight(25)
            data.topBar = topBar
        end
    end
    local bottomHeight = options and options.bottomBar
    if bottomHeight then
        local bottomBar = Texture(frame, "BACKGROUND", 0, 0, 0, Theme().band, -5)
        if bottomBar then
            bottomBar:SetPoint("BOTTOMLEFT"); bottomBar:SetPoint("BOTTOMRIGHT")
            bottomBar:SetHeight(type(bottomHeight) == "number" and bottomHeight or 25)
            data.bottomBar = bottomBar
        end
    end
    if not (options and options.noBorder) then
        local textureAPI = _G.C_Texture
        local atlasAvailable = textureAPI and textureAPI.GetAtlasInfo and
            textureAPI.GetAtlasInfo("AdventureMap_TopBorder")
        local borderHost
        if atlasAvailable and CreateFrame then
            borderHost = CreateFrame("Frame", nil, frame)
            if borderHost and borderHost.SetAllPoints then borderHost:SetAllPoints(frame) end
            if borderHost and borderHost.SetFrameLevel and frame.GetFrameLevel then
                borderHost:SetFrameLevel(frame:GetFrameLevel() + 6)
            end
        end
        local border = Texture(borderHost or frame, "OVERLAY", nil, nil, nil, nil, 7)
        if border and atlasAvailable and border.SetAtlas then
            border:SetAtlas("AdventureMap_TopBorder")
            border:SetAllPoints(borderHost or frame)
            data.shellBorderHost = borderHost
            data.shellBorder = border
        else
            AddBorder(frame)
        end
    end
end

function S.Panel(frame, options)
    if Forbidden(frame) then return end
    options = options or {}
    local data = Data(frame)
    local keep = data.panelBackground and { [data.panelBackground] = true } or nil
    FadeRegions(frame, keep)
    if not data.panelBackground and not options.noBg then
        local color = options.inset and Theme().inset or Theme().panel
        if options.shade then color = { 0, 0, 0, 0.25 } end
        local background = Texture(frame, "BACKGROUND", color[1], color[2], color[3], color[4], -6)
        if background then background:SetAllPoints(frame); data.panelBackground = background end
    end
    if not options.noBorder then AddBorder(frame) end
    data.panel = true
    data.panelInset = options.inset == true
    data.panelShade = options.shade == true
end

function S.Inset(inset)
    if Forbidden(inset) then return end
    FadeRegions(inset)
    if inset.Bg and inset.Bg.SetAlpha then inset.Bg:SetAlpha(0) end
    if inset.NineSlice then S.FadeNineSlice(inset.NineSlice) end
end

function S.Font(fontString, r, g, b)
    if Forbidden(fontString) or not (fontString.GetFont and fontString.SetFont) then return end
    local _, size = fontString:GetFont()
    local justifyH = fontString.GetJustifyH and fontString:GetJustifyH()
    local justifyV = fontString.GetJustifyV and fontString:GetJustifyV()
    if issecretvalue and issecretvalue(size) then return end
    local createFont = _G.CreateFont
    if fontString.SetFontObject and createFont then
        if not shadowFont then
            shadowFont = _G.BindCardsEUISkinShadowFont or createFont("BindCardsEUISkinShadowFont")
            shadowFont:SetFont(FONT, 12, "")
            shadowFont:SetShadowColor(0, 0, 0, 1)
            shadowFont:SetShadowOffset(1, -1)
        end
        fontString:SetFontObject(shadowFont)
    end
    fontString:SetFont(FONT, size or 12, "")
    if justifyH then fontString:SetJustifyH(justifyH) end
    if justifyV then fontString:SetJustifyV(justifyV) end
    if r and fontString.SetTextColor then fontString:SetTextColor(r, g, b or r) end
end

function S.White(fontString, r, g, b)
    if fontString and fontString.SetTextColor then fontString:SetTextColor(r or 1, g or 1, b or 1) end
end

function S.Button(button, keepKeys)
    if Forbidden(button) then return end
    local data = Data(button)
    if data.button then return end
    data.button = true
    local keep = {}
    for _, key in ipairs(keepKeys or {}) do if button[key] then keep[button[key]] = true end end
    data.buttonKeep = keep
    FadeRegions(button, keep)
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local method = button[getter]
        local texture = method and method(button)
        if texture and not keep[texture] and texture.SetAlpha then texture:SetAlpha(0) end
    end
    for _, key in ipairs({ "Left", "Middle", "Right", "LeftSeparator", "RightSeparator" }) do
        local region = button[key]
        if region and not keep[region] and region.SetAlpha then region:SetAlpha(0) end
    end
    local color = button.bindCardsButtonKind == "primary" and S.GetPrimaryButtonStyle(false) or Theme().raised
    local background = Texture(button, "BACKGROUND", color[1], color[2], color[3], color[4])
    if background then background:SetAllPoints(button); data.buttonBackground = background end
    AddBorder(button)
    local hover = Texture(button, "HIGHLIGHT", 1, 1, 1, 0.10)
    if hover then hover:SetAllPoints(button); data.buttonHover = hover end
end

function S.TopSurface(frame, kind)
    if Forbidden(frame) then return end
    local data = Data(frame)
    data.topSurface = kind or true
    local color = TopSurfaceColor(Theme(), data.topSurface)
    if data.panelBackground then ApplyColor(data.panelBackground, color) end
    if data.buttonBackground then ApplyColor(data.buttonBackground, color) end
end

function S.StyleTab(frame, selected, active, disabled)
    local color = S.GetTabStyle(selected, active, disabled)
    if not color then return end
    local data = Data(frame)
    data.tabState = { selected = selected, active = active, disabled = disabled }
    if data.panelBackground then ApplyColor(data.panelBackground, color) end
    if data.buttonBackground then ApplyColor(data.buttonBackground, color) end
end

function S.WhiteButtonLabel(button)
    local label = button and (button.Text or (button.GetFontString and button:GetFontString()))
    S.White(label)
end

function S.StateButtonLabel(button)
    if not button then return end
    local label = button.Text or (button.GetFontString and button:GetFontString())
    local function Update()
        if not label then return end
        if not button.IsEnabled or button:IsEnabled() then S.White(label)
        else label:SetTextColor(0.5, 0.5, 0.5) end
    end
    if button.HookScript then
        button:HookScript("OnEnable", Update)
        button:HookScript("OnDisable", Update)
    end
    Update()
end

function S.EditBox(editBox)
    if Forbidden(editBox) then return end
    local data = Data(editBox)
    if data.editBox then return end
    data.editBox = true
    FadeRegions(editBox)
    for _, key in ipairs({ "Left", "Right", "Middle", "Mid" }) do
        local region = editBox[key]
        if region and region.SetAlpha then region:SetAlpha(0) end
    end
    local input = Theme().input
    local background = Texture(editBox, "BACKGROUND", input[1], input[2], input[3], input[4])
    if background then background:SetAllPoints(editBox); data.editBackground = background end
    AddBorder(editBox)
end

function S.Checkbox(checkbox, options)
    if Forbidden(checkbox) then return end
    local data = Data(checkbox)
    if data.checkbox then return end
    data.checkbox = true
    local checked = checkbox.GetCheckedTexture and checkbox:GetCheckedTexture()
    FadeRegions(checkbox, checked and { [checked] = true } or nil)
    local input = Theme().input
    local box = Texture(checkbox, "BACKGROUND", input[1], input[2], input[3], input[4])
    if box then
        box:SetPoint("TOPLEFT", 4, -4); box:SetPoint("BOTTOMRIGHT", -4, 4)
        data.checkboxBackground = box
    end
    AddBorder(checkbox, { 0.25, 0.25, 0.25, 1 })
    if checked and not (options and options.stockCheck) and checked.SetVertexColor then
        checked:SetVertexColor(S.GetAccentColor())
        data.checked = checked
    end
end

function S.Dropdown(dropdown)
    if Forbidden(dropdown) then return end
    local data = Data(dropdown)
    if data.dropdown then return end
    data.dropdown = true
    FadeRegions(dropdown)
    local color = Theme().panel
    local background = Texture(dropdown, "BACKGROUND", color[1], color[2], color[3], color[4])
    if background then background:SetAllPoints(dropdown); data.dropdownBackground = background end
    AddBorder(dropdown, { 0.25, 0.25, 0.25, 1 })
    local arrow = Texture(dropdown, "OVERLAY")
    if arrow and arrow.SetAtlas then
        arrow:SetAtlas("Azerite-PointingArrow"); arrow:SetSize(14, 10); arrow:SetPoint("RIGHT", -6, 0)
        data.dropdownArrow = arrow
    end
    S.White(dropdown.Text or (dropdown.GetFontString and dropdown:GetFontString()))
end

function S.ScrollBar(scrollBar)
    if Forbidden(scrollBar) then return end
    local data = Data(scrollBar)
    if data.scrollBar then return end
    data.scrollBar = true
    local track = scrollBar.Track
    if track then FadeRegions(track) end
    local thumb = (track and track.Thumb) or (scrollBar.GetThumb and scrollBar:GetThumb())
    if thumb then
        FadeRegions(thumb)
        local strip = Texture(thumb, "ARTWORK", 1, 1, 1, 0.30)
        if strip then
            strip:SetPoint("TOP"); strip:SetPoint("BOTTOM"); strip:SetWidth(4)
        end
    end
end

function S.Tab(tab)
    -- BindCards uses button-shaped card tabs; the public Tab entry remains
    -- compatible and intentionally shares that same neutral plate here.
    S.Button(tab)
end

function S.CloseButton(button)
    if Forbidden(button) then return end
    local data = Data(button)
    if data.close then return end
    data.close = true
    if button.SetNormalTexture then button:SetNormalTexture("") end
    if button.SetPushedTexture then button:SetPushedTexture("") end
    if button.SetHighlightTexture then button:SetHighlightTexture("") end
    if button.SetDisabledTexture then button:SetDisabledTexture("") end
    local keep = {}
    if data.buttonBackground then keep[data.buttonBackground] = true end
    if data.buttonHover then keep[data.buttonHover] = true end
    FadeRegions(button, keep)
    local glyph = Texture(button, "OVERLAY")
    if glyph then
        if glyph.SetAtlas then glyph:SetAtlas("uitools-icon-close") end
        glyph:SetSize(14, 14); glyph:SetPoint("CENTER", -2, 0)
        local color = Theme().palette.text
        glyph:SetVertexColor(color[1], color[2], color[3], 0.75)
        data.closeGlyph = glyph
    end
    if button.HookScript and glyph then
        local function Update(hovered)
            data.closeHovered = hovered
            local color = Theme().palette.text
            glyph:SetVertexColor(color[1], color[2], color[3], hovered and 1 or 0.75)
        end
        button:HookScript("OnEnter", function() Update(true) end)
        button:HookScript("OnLeave", function() Update(false) end)
    end
end

function S.PageButton(button, character, size)
    S.Button(button)
    local label = button and button.CreateFontString and button:CreateFontString(nil, "OVERLAY")
    if label then
        label:SetFont(FONT, size or 14, ""); label:SetPoint("CENTER")
        label:SetText(character); label:SetTextColor(1, 1, 1, 0.9)
    end
end

local function BorderIcon(parent, icon)
    if not (parent and icon) or Data(icon).iconBorder then return end
    Data(icon).iconBorder = true
    local function Line()
        return Texture(parent, "OVERLAY", 0, 0, 0, 1)
    end
    local top, bottom, left, right = Line(), Line(), Line(), Line()
    if not (top and bottom and left and right) then return end
    top:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1); top:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 1, 1); top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", -1, -1); bottom:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1); bottom:SetHeight(1)
    left:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1); left:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", -1, -1); left:SetWidth(1)
    right:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 1, 1); right:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1); right:SetWidth(1)
end

function S.SquareIcon(icon, parent)
    if not (icon and icon.SetTexCoord) then return end
    if icon.GetNumMaskTextures and icon:GetNumMaskTextures() > 0 then return end
    if not pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92) then return end
    if parent then BorderIcon(parent, icon) end
    return true
end

function S.SortHeaderBar(list)
    if list and list.HeaderContainer then S.Panel(list.HeaderContainer, { noBorder = true }) end
end

function S.ApplyBarFill(statusBar)
    if statusBar and statusBar.SetStatusBarColor then statusBar:SetStatusBarColor(S.GetAccentColor()) end
end
