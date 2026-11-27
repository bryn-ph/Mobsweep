# Tagger

Quest mob targeting for WoW: Forever. Tagger targets and raid-marks the mobs your tracked quest wants you to kill or loot, and tells you when one is near. Based on RestedXP's targeting macro, without the guide.

Beta. Report bugs on [GitHub](https://github.com/bryn-ph/Tagger/issues).

## Features

- Works on your focused quest, or the first one on your tracker.
- A Tracking panel with one button that targets and marks the nearest quest mob (skull by default). It never picks your old target.
- Turn Tracking on and the button glows when a quest mob is in range, with a short alert and a sound you pick. Another alert when it's marked.
- Full or minimal panel. Minimal is just the button; hover it for the details. Drag the button to move either one.
- The same thing as a `Tagger` macro, if you'd rather put it on your bars.
- Kill quests work on their own. Loot quests need [Questie](https://www.curseforge.com/wow/addons/questie) (its QuestieDB).

Addons can't target or mark on their own, so you still press the button. Tracking needs enemy nameplates on (V) to see mobs.

## Usage

- Tick Tracking on the panel (or right-click the button), and click the button (or its key) when it glows.
- `/tagger` or the minimap button opens the settings, where you can set the Tag key. Right-click the minimap button to turn Tracking on or off.
- `/tagger help` for all commands.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Code: [MIT](LICENSE).

The icon is based on [Bullseye](https://game-icons.net/1x1/skoll/bullseye.html) by Skoll, from [game-icons.net](https://game-icons.net), licensed [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). It has been recoloured and framed.
