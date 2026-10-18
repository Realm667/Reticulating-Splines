# Desktop cheat codes

Type a code directly while the singleplayer city view has focus. No console,
input box or Enter key is needed. Case does not matter. Text fields, dialogs,
the main menu and multiplayer sessions do not accept city cheat input.
SCURK also recognizes `vaudeville` while a singleplayer city is loaded.

An ambiguous first letter waits up to 400 ms for another letter. Subsequent
letters can be up to 1.6 seconds apart. An incomplete sequence returns its
keys to the ordinary shortcuts; a held key returns to movement on repeat.
Clicking, losing focus, changing cities or entering multiplayer cancels the
sequence. This prevents a complete code from opening intermediate shortcut
windows or moving the camera. An invalid sequence does not execute a cheat.

## Consolidated behavior in Reticulating Splines

| Code | Effect |
| --- | --- |
| `cass` | Add $250. With random disasters enabled, a 15% roll attempts a firestorm. |
| `fund` | Offer a $10,000 bond at 25% interest. Confirmation is required. The ordinary limit of 50 bonds and signed funds range remain enforced. |
| `imacheat`, `buddamus`, `torg`, `porntipsguzzardo`, `pirntopsguzzardo` | Add $500,000 and unlock inventions and rewards through the existing debug action. |
| `pirn`, then `topsguzzardo` | Two-part Macintosh spelling of the same jackpot. The map/status-bar clicking requirement is omitted. |
| `ardo` | Add another $500,000 after a jackpot in this city session. Loading another city or entering multiplayer clears this permission. |
| `priscilla`, `oivaizmir` | Open the existing Debug window. Repeating the action never closes it. |
| `damn`, `darn`, `heck` | Fill eligible residential 2×2 sites with churches. Sites must be level, dry and free of labels/disasters; vacant sites, trees and 1×1 homes qualify. Larger buildings are preserved to avoid splitting their footprints. |
| `gilmartin` | Open the existing military-base offer. Existing placement and acceptance rules apply. |
| `noah` | Start mass flooding through the existing disaster system. |
| `moses` | End an active flood or mass flood. Other disaster types are unaffected. |
| `mrsoleary` | Start a firestorm. |
| `gomorrah` | Attempt a nuclear meltdown; a suitable plant is required. |
| `uspa87419` | Show a temporary skydiver animation. |
| `vaudeville` | Show a temporary dancing launch arcology using the current graphics pack. Also available from the city view. |

The animations are new renditions of the Easter eggs, not extracted original
animation sequences. They do not create map objects or saved data. There is at
most one animation, and changing the city or entering multiplayer removes it.
Explicit disaster codes follow the existing disaster commands, including their
site requirements. A status message reports success or unavailability.

There is one consolidated behavior per code, independent of the selected theme.
In particular, `cass` uses the Windows/Mac $250 value, not DOS 1.10's $2,500.
The church effect is immediate rather than a persistent alteration of growth.

## Exclusions and multiplayer

`vers`, `memy`, `test`, `porn`, `klatu verata nictu` and `joke` are intentionally
excluded, as are all console/handheld codes and historical exploits. Unverified
codes such as `hell` and `Sim-Sim-Sim` are not accepted. `fund` does not recreate
the corrupt-interest bond exploit.

The local code dispatcher rejects both hosts and clients, including lobby and
reconnect states. A document with `multiplayer.json` is also rejected when no
session is connected. Bond confirmation checks the same policy again and must
refer to the same loaded document. No cheat is sent over the network. Existing
separately authorized host administration remains a separate feature.

## Historical sources

The aliases were consolidated from [SimPage's historical list](https://simpage.net/simcity2/cheats.shtml),
[IGhory's 1997 guide](https://gamefaqs.gamespot.com/pc/198648-simcity-2000/faqs/2100),
[Benjer's guide](https://gamefaqs.gamespot.com/pc/198648-simcity-2000/faqs/33520),
and [version-by-version firsthand checks](https://www.spoonshiro.com/2025/11/the-definitive-simcity-2000-cheats-list.html).
These describe different original releases, not a claim that every code worked
in every DOS, Macintosh or Windows release. The table above is the implemented
RS contract; adaptations and exclusions are explicit.
