"""Shared face defaults for character definitions (port of src/art/chars/_face.js; eye anchor fields consumed by the
attachments). EYE: head-local center of the LEFT eye (x mirrored for both eyes), r = eyeball radius, iris/pupil
colors, lid color and resting openness (0 closed .. 1 wide open)."""
from ..jsutil import O

EYE_DEFAULTS = O(
    x=0.056, y=0.18, z=-0.1, r=0.034,
    iris='#5A3420', irisSize=0.56, pupilSize=0.42, sclera='#FBF6EE',
    lid='#F2B58F', lash='#2A1A14', lidOpen=0.7, lowerLid=0.25, tilt=0,
)
