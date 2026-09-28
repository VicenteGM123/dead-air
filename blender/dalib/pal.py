"""Port of src/core/config.js: T (tunables, verbatim), LAYERS, PAL (GDD §3.2 palette, exact strings) and BARS.

All three are JSObj (dict + attribute access): PAL['wztvBlue'] == PAL.wztvBlue == '#2F5BD3', T.player.hp == 150.
JS object keys are strings: numeric-looking keys (T.telly.channels) are kept as strings ('2', '4', ...), exactly as
JS stores them (look them up with str(n)). JS `1/20` is written as its value 0.05. Like the JS, PAL.BARS exists too.
Treat these as read-only (JS freezes PAL).
"""

from .mathutils3 import JSObj


def _o(d):
    if isinstance(d, dict):
        return JSObj({str(k): _o(v) for k, v in d.items()})
    if isinstance(d, list):
        return [_o(v) for v in d]
    return d


T = _o({
    'player': {'hp': 150, 'hpWobble': 300, 'regenDelay': 3.0, 'regenRate': 60, 'iframes': 0.25,
               'run': 4.6, 'sprint': 6.8, 'ads': 2.8, 'backpedal': 3.9, 'stamina': 4.0, 'staminaDelay': 1.0,
               'staminaRefill': 3.0,
               'jump': 1.1, 'gravity': 22, 'sprintToFire': 0.25, 'swap': 0.6,
               'melee': {'dmg': 150, 'cd': 0.7, 'reach': 1.6, 'lunge': 2.5},
               'startPoints': 500, 'grenadesStart': 2, 'grenadesPerRound': 2, 'grenadesMax': 4, 'teleMax': 3},
    'points': {'hit': 10, 'kill': 50, 'head': 100, 'melee': 130, 'special': 50, 'forecaster': 100, 'bigShot': 500,
               'board': 10, 'boardCap': 200, 'cancelled': 400, 'gaffer': 200, 'eeStep': 130},
    'doors': {'d1_lobby_newsroom': 750, 'd2_lobby_green': 1000, 'd3_newsroom_green': 750, 'd4_green_studio_a': 1250,
              'd5_newsroom_mc': 1250, 'd6_studio_a_b': 1000, 'd7_studio_b_mc': 1000, 'dy_mc_yard': 0},
    'wallbuys': {'pump_37': [500, 250], 'mp7': [1000, 500], 'm16a1': [1200, 600], 'upgradedAmmo': 2500,
                 'grenades': 250},
    'rounds': {'early': [6, 8, 12, 16, 20], 'countA': 2.4, 'countB': 0.06, 'countCap': 150,
               'hpEarlyBase': 150, 'hpEarlyStep': 100, 'hpMul': 1.1, 'hpCap': 40000,
               'speeds': {'walk': 1.1, 'jog': 2.4, 'sprint': 4.0, 'super': 4.5},
               'speedRoll': {'perRound': 8, 'jitter': 15, 'jog': 35, 'sprint': 70, 'super': 150, 'superCap': 0.6},
               'interval': {'base': 2.0, 'mul': 0.95, 'min': 0.5}, 'maxAlive': 24, 'intermission': 10,
               'firstRoundDelay': 3, 'firstSpawnDelay': 3,
               'hullabaloo': {'first': [5, 6], 'every': [4, 5], 'count': [8, 4, 24], 'hpFirst': 350, 'hpMul': 0.4,
                              'maxAlive': 10, 'interval': 0.8, 'intermission': 12},
               'forecasterFrom': 7, 'bigShotFrom': 10, 'bigShotEvery': 3, 'bigShotExtra': 0.10, 'sockMixFrom': 12,
               'sockMix': [0.10, 0.15]},
    'zombies': {'tunedIn': {'dmg': 50, 'range': 1.3, 'windup': 0.4, 'cd': 1.2},
                'sock': {'speed': 4.5, 'speed15': 5.0, 'dmg': 25, 'leap': 2.5, 'cd': 0.9, 'hpMix': 0.35},
                'forecaster': {'hpMul': 1.5, 'hpAdd': 150, 'strafe': 2.8, 'keep': [8, 14], 'castCd': 6,
                               'cloudSpeed': 9, 'telegraph': 1.0,
                               'strikeR': 1.5, 'strikeDmg': 40, 'cloudHp': [50, 10], 'sobStun': 3, 'sobMul': 2},
                'bigShot': {'hpMul': 6, 'hpMin': 2500, 'speed': 1.6,
                            'rush': {'range': 12, 'cd': 8, 'tele': 1.0, 'speed': 9, 'time': 1.5, 'dmg': 70,
                                     'knock': 4, 'dizzy': 2, 'dizzyMul': 1.5},
                            'flash': {'cd': 9, 'range': 20, 'windup': 1.0, 'cone': 60, 'dmg': 20, 'white': 1.5},
                            'front': 0.4, 'plug': 3},
                'screenTelegraph': 1.2, 'screenEmerge': 1.0, 'screenMul': 2, 'boardTear': 1.2, 'vault': 1.2,
                'fence': 1.5, 'gate': 0.8},
    'telly': {'cost': 950, 'window': 10, 'moveSafe': 3, 'moveBase': 0.12, 'moveStep': 0.04, 'moveCap': 0.36,
              'pity': 10, 'pityMul': 3,
              'weights': {'revolver_38': 8, 'pump_37': 8, 'mp7': 8, 'm16a1': 8, 'm60': 7, 'tiny_tele': 6,
                          'zapper': 3, 'boom_mic': 3, 'chroma_key': 3},
              'channels': {'2': 'revolver_38', '4': 'pump_37', '5': 'mp7', '7': 'm16a1', '8': 'm60',
                           '9': 'tiny_tele', '11': 'zapper', '12': 'boom_mic', '13': 'chroma_key'},
              'snow': [3, 6, 10], 'bumpWindow': 1.0, 'spinTime': 4.3, 'cameo': 1 / 20},
    'perks': {'limit': 4, 'replay_ade': 500, 'replayMax': 3, 'roller_boogie': 2000, 'double_vision': 2000,
              'wobble_up': 2500, 'jump_cut': 3000,
              'adLength': 3.2, 'markRadius': 1.0,
              'replay': {'rewind': 4.0, 'speed': 4, 'knock': 5, 'stun': 2, 'invuln': 2},
              'roller': {'speedMul': 1.08, 'sprintToFire': 0.10}, 'doubleVision': {'fireRate': 1.2, 'ghost': 0.5},
              'jumpCut': {'reload': 0.5, 'swap': 0.5}},
    'uplink': {'cost': 5000, 'reroll': 2500, 'alignHold': 3.0, 'collect': 15, 'flickerAt': 10,
               'signals': {'hot_mic': {'p': 0.10, 'cd': 3, 'dur': 3, 'burn': 0.35},
                           'laugh_track': {'p': 0.12, 'cd': 6, 'dur': 4, 'mul': 1.5},
                           'cold_open': {'p': 0.12, 'cd': 5, 'dur': 3, 'mul': 1.5, 'r': 3}}},
    'drops': {'chance': 0.02, 'threshold': 2000, 'thresholdMul': 1.14, 'perRound': 4, 'minGap': 15, 'life': 26,
              'blink': 6, 'timed': 30, 'freeze': 8, 'pickupR': 1.0},
    'boss': {'hpBase': 25000, 'hpPerRound': 2500, 'screenMul': 2, 'antennaMul': 3, 'bodyMul': 0.5,
             'p1': {'hopEvery': 7, 'ring': 9, 'balls': 3, 'ballEvery': 3.5, 'ballSpeed': 12, 'ballDmg': 35,
                    'addsEvery': 12, 'addsMax': 10},
             'p2': {'sweepEvery': 9, 'tele': 1.2, 'sweepTime': 2.5, 'beamTop': 0.6, 'beamR': 16, 'dmg': 60,
                    'socksEvery': 15},
             'p3': {'drift': 2.2, 'grabR': 2.5, 'grabWindup': 0.8, 'grabDmg': 80, 'throw': 5, 'offAirEvery': 15,
                    'offAir': 4, 'reveal': 1.5, 'addsEvery': 10, 'addsMax': 8}},
    'ee': {'chimeOrder': ['red', 'yellow', 'green', 'blue'], 'chimeGap': 3.0, 'puppetR': 0.45, 'applauseKills': 13,
           'applauseZone': [-6.5, -19.0, 14.5, -14.5],
           'storm': {'speed': 3.8, 'height': 3.0, 'life': 90, 'lostDist': 20, 'lostTime': 8, 'zap': 10,
                     'zapEvery': 4},
           'towerR': 6, 'stormNear': 8, 'tracking': {'detents': 13, 'beatPerStep': 2.5, 'hold': 3.0, 'radius': 4},
           'switchHold': 2.0, 'deadAir': 2.0},
})

# Render layers (ARCHITECTURE §12). Main camera: WORLD+ZOMBIES. Feed cams: 0,1,2. Sponsor cams: 0. Insert cam: 3.
LAYERS = JSObj({'WORLD': 0, 'ZOMBIES': 1, 'TV_ONLY': 2, 'INSERT': 3})

# GDD §3.2 palette. Strings work for Color, canvas and CSS alike.
PAL = JSObj({
    # Brand
    'wztvBlue': '#2F5BD3', 'channelRed': '#E23B3B', 'capWhite': '#F4F1E8', 'cream': '#F6E7C8',
    # 70s base
    'harvestGold': '#E8A92E', 'burntOrange': '#E3662B', 'avocado': '#8C9A3A', 'mustard': '#D9A520',
    'chocolate': '#5A3A22',
    'walnut': '#7A4A2A', 'teak': '#B07A45', 'rust': '#B5472A', 'teal': '#2E8C8C', 'plum': '#6B3A6E',
    'shagOrange': '#D9602B',
    # Emissive
    'onAirRed': '#FF3B30', 'crtCyan': '#7FE7FF', 'tungsten': '#FFC98A', 'neonPink': '#FF5FA2',
    'marqueeGold': '#FFC23A',
    # Gels
    'gelMagenta': '#FF4FA0', 'gelAmber': '#FFB347', 'gelCyan': '#5FE3FF',
    # Cartoonized SMPTE color bars, left to right
    'barWhite': '#EDEDED', 'barYellow': '#F4E03A', 'barCyan': '#3FD6E0', 'barGreen': '#52D24A',
    'barMagenta': '#D64FD6', 'barRed': '#E4473A', 'barBlue': '#3A58E4',
    # Neon logo letters
    'neonW': '#FF3B30', 'neonZ': '#FFD23A', 'neonT': '#52E04A', 'neonV': '#3A7BFF',
    # Zombies
    'zSkin': '#A9C7A4', 'zShadow': '#7FA08A', 'zUnderEye': '#7A5C8E', 'zMouth': '#3B2340',
    'zEye': '#F2FBFF', 'zEyeRim': '#8FF3FF', 'zFeedSkin': '#E8B896',
    # Sock Hopper stripes
    'sockRed': '#E23B3B', 'sockYellow': '#F4E03A', 'sockBlue': '#3A58E4', 'sockBase': '#F4F1E8',
    # Night
    'skyTop': '#1B1E4A', 'horizon': '#2A2F6B', 'moon': '#FFF4D6', 'moonlight': '#9FB6FF', 'sodium': '#FFB347',
    # Dawn
    'dawn1': '#FF7E5F', 'dawn2': '#FFB36B', 'dawn3': '#FFE3A3',
    # Wonder / upgrade
    'chromaBlue': '#1E5BFF', 'greenScreen': '#39E75F', 'perpetua': '#9CFF57',
    # Signal colors
    'hotMic': '#FF5A3C', 'laughTrack': '#52E04A', 'coldOpen': '#7FD4FF',
    # Rim lights (GDD §3.5)
    'rimHero': '#FFD9A0', 'rimZombie': '#8FF3FF',
    # Shadows: tinted purple, never pure black
    'shadow': '#3A2A5A',
})

BARS = [PAL.barWhite, PAL.barYellow, PAL.barCyan, PAL.barGreen, PAL.barMagenta, PAL.barRed, PAL.barBlue]
PAL['BARS'] = BARS

__all__ = ['T', 'LAYERS', 'PAL', 'BARS']
