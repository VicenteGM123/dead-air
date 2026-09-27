// Entry point (bundled to build/game.js by tools/build.mjs): creates the Game, installs the optional wonder-weapon
// system (game.wonder, see the header of src/game/wonder.js) and boots it.

import { Game } from './core/game.js';
import { install as installWonder } from './game/wonder.js';

const game = new Game();
installWonder(game);
game.boot().catch((err) => console.error('[boot]', err));
