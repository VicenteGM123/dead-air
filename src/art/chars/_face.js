// Shared face defaults for character definitions (eye anchor fields consumed by charRuntime attachments).
// EYE: head-local center of the LEFT eye (x > 0 is the character's left? no: x is mirrored for both eyes),
// r = eyeball radius, iris/pupil colors, lid color and resting openness (0 closed .. 1 wide open).
export const EYE_DEFAULTS = {
  x: 0.056, y: 0.18, z: -0.1, r: 0.034,
  iris: '#5A3420', irisSize: 0.56, pupilSize: 0.42, sclera: '#FBF6EE',
  lid: '#F2B58F', lash: '#2A1A14', lidOpen: 0.7, lowerLid: 0.25, tilt: 0,
};
