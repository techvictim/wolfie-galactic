# Wolfie Galactic

A block-building space game for Apple TV, iPad, iPhone and Mac. Start on **Wolfie World**, build with
big toy-voxel blocks, make friends with alien critters, drive rovers and hover bikes, and fly
starships up through the sky into space, to the orbiting spaceport and by hyperspace to **Pup Moon**
and **Glimmer**. Friends on the same Wi-Fi can play together.

Written in Swift with RealityKit and SwiftUI. Every model, picture and sound is made by the scripts
in `Tools`, so there's nothing to license.

## Build it

1. Install **Xcode 26** or later, with the tvOS platform (Xcode › Settings › Components).
2. Install the project generator: `brew install xcodegen` (Homebrew: https://brew.sh).
3. In this folder, run `xcodegen`. It makes `WolfieGalactic.xcodeproj`.
   Run it again whenever files are added or removed.
4. Open the project, choose your own team under **Signing & Capabilities** if needed
   (or change `DEVELOPMENT_TEAM` in `project.yml`), pick a target and device, and press Run.
   - `WolfieGalactic-Mac`: quickest to try.
   - `WolfieGalactic-iPad`: iPhone and iPad (iOS 18 or later).
   - `WolfieGalactic-TV`: Apple TV (tvOS 26), with a game controller.

## Automatic builds

- `.github/workflows/build.yml` compiles all three apps on every push.
- `.github/workflows/testflight.yml` signs and uploads to TestFlight after every passing build on `main`.
  It needs three repository secrets from an App Store Connect API key: `ASC_KEY_ID`, `ASC_ISSUER_ID`
  and `ASC_KEY_P8`. Builds are numbered from the run number, and the title screen shows the build.

## Controls

Press **Create / View** on a controller (or **?** on a keyboard) in the game for the controls of whatever
you're doing. The full list is under Controls on the title screen and in the pause menu.

## Make it your own

| File | What to change |
| --- | --- |
| `Resources/blocks.json` | Blocks: name, colour, and which are on the hotbar (255 is the laser). |
| `Resources/planets.json` | Planets: gravity, sky, terrain, trees, crystals, craters, settlements (`city`, `base`, `mine`) and the vehicles parked there. |
| `Resources/critters.json` | Critters: where they live, how they move, their sound and fun fact. |
| `Tools/make_models.py` | Vehicle models (rover, starship, moon buggy, hover bike) from simple shapes. |
| `Tools/make_space.py` | Planets seen from space, the spaceport, and the Comet, Hauler and Zoomer ships. |
| `Tools/make_critters.py` | Critter models and their Critter Book pictures. |
| `Tools/make_crew.py` | The seven Wolfie Military crew members as voxel characters, with their portraits. |
| `Resources/Voices` | The crew's voice clips (`<who>_<kind>_<n>.mp3`), the same generated voices as Wolfie Military. |
| `Tools/make_sounds.py` | Every sound effect and music loop. |
| `Tools/make_title_planet.py`, `Tools/make_icons.py` | The title-screen planet and the app icons. |

Detail models are `.vox` files at 4 small voxels per block edge; open them in
[MagicaVoxel](https://ephtracy.github.io/) to edit by hand.

## How it's organised

| Folder | What's in it |
| --- | --- |
| `Game/World` | Endless worlds made from each planet's seed in 16 × 16 × 96 chunks, settlements, saving |
| `Game/Render` | Meshing only visible faces, streaming chunks in the background, far-away land, avatars, effects |
| `Game/Player`, `Game/Vehicles` | Walking and flying on foot; rovers, hover bikes and ships |
| `Game/Critters` | Critters: wandering, following friends, grumpy Grumblers |
| `Game/Space` | Space around a planet: the planet as a ball of blocks, spaceport, nebulae, galaxies, hyperspace |
| `Game/Net` | Playing together on the same Wi-Fi (Bonjour + TCP, one device hosts) |
| `Game/Audio` | Sound effects and music |
| `Game/Input`, `Game/UI` | Controllers, keyboard and mouse, touch; the HUD and menus |
| `Game/App` | The game loop and the parts of the game (`Game+Vehicles`, `Game+Space`, `Game+Together`, …) |

## Saves

Each planet saves separately (`<planet>.wgworld`). Worlds are rebuilt from the seed, so only changed
chunks are stored. Mac and iPad keep them in Application Support; Apple TV keeps them in its cache
folder for now.
