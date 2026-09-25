# Surround icon comparison on iPhone

This project creates eight independent dummy apps so the icon designs can appear
together on one Home Screen. Each app opens a short description and a static
preview of its design. Compare the actual icons on the Home Screen, where iOS
renders the material and appearance effects.

**Go 7 Amber is the selected production design.** Its complete native document
was copied to [SurroundIcon.icon](../../../Surround/SurroundIcon.icon), the
canonical app asset. Production Debug and Release use `SurroundIcon`; Beta
continues to use `AppIconBeta` and excludes the production native document.
The comparison apps still use their preserved study sources below.

Go 5 Borderless is build 2 with the deeper amber board. Go 6 Brown is a
separate app with the warmer brown palette; build 2 improves grid visibility
with deeper warm-brown lines (`#6B482B`).
Go 7 Amber provides a separate midpoint comparison. Its Default previews
were checked at 512, 60, and 32 pixels in generation 27 and at 60 pixels in
generation 26.

| Home Screen label | Source | Design |
| --- | --- | --- |
| Go 0 Current | [Legacy AppIcon](../../../Surround/Assets.xcassets/AppIcon.appiconset) | Pre-change wood texture and stone artwork, retained as the legacy reference. |
| Go 1 Original | [Surround-Original.icon](../Variants/Surround-Original.icon) | First glass draft, with a flat grid and grouped stones. |
| Go 2 Depth | [Surround-Depth.icon](../Variants/Surround-Depth.icon) | Raised gold board with stronger glass rims and shadows. |
| Go 3 Refined | [Surround.icon](../Surround.icon) | Thinner rims, warmer white stones, and a lighter grid. |
| Go 4 Roomier | [Surround-Roomier-Board.icon](../Variants/Surround-Roomier-Board.icon) | Smaller rounded board and an open grid. |
| Go 5 Borderless | [Surround-Edge-to-Edge.icon](../Variants/Surround-Edge-to-Edge.icon) | Deeper amber gold fills the icon, grid lines fade near the edges, and stone shadows use 50% opacity. |
| Go 6 Brown | [Surround-Brown.icon](../Variants/Surround-Brown.icon) | Warmer brown board with deeper brown grid lines, keeping the Borderless layout and edge fades. |
| Go 7 Amber | [Surround-Amber.icon](../Variants/Surround-Amber.icon) | Selected production design. Midpoint between Borderless and Brown: board `#DAAA5E` → `#B98239`, grid `#825C32`, and the same stones and edge fades. |

The seven glass apps use their native layered `.icon` documents as app icons.
Go 0 Current uses a copy of the legacy PNG asset catalog; its label describes
the icon before production adoption of Amber. The PNG previews inside the apps
are only for identifying designs. Edit the canonical `SurroundIcon.icon` package
for future production changes; editing a comparison study does not update it.

## Build and install

Requires Xcode, an iPhone running iOS 26 or later, Ruby with the `xcodeproj` gem,
and Icon Composer at `/Applications/Icon Composer.app`. Use an Apple development
team configured for signing on this Mac.

Run these commands from this `DeviceComparison` directory:

```sh
ruby generate.rb
xcodebuild -project .build/Comparison.xcodeproj -scheme 'All Icons' -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData -allowProvisioningUpdates build
python3 deploy.py --device '<name-or-UDID>'
```

Use the paired device's name or UDID for the deployment argument. To choose a
different signing team, set it when generating the project:

```sh
SURROUND_ICON_TEAM=YOUR_TEAM_ID ruby generate.rb
```

The labels and source mapping are defined in `variants.json`. Bundle identifiers
use `com.honganhkhoa.Surround.IconStudy.` followed by the variant ID (`current`,
`original`, `depth`, `refined`, `roomier`, `borderless`, `brown`, or `amber`),
allowing all eight apps to coexist with Surround and Surround Beta.

Generated previews, the Xcode project, build products, and logs live under the
ignored `.build/` directory. Regenerate and rebuild after changing artwork.

## Compare and remove

Place the eight Go apps next to one another on the same Home Screen. Compare the
stone silhouette, grid legibility, and shadows at both small and large icon
sizes. Try Default/light, Dark, Clear, and Tinted appearances, including light
and dark variants where available. Use the same wallpaper for each comparison.

To remove the study, delete the eight apps named **Go 0 Current** through
**Go 7 Amber** using **Remove App > Delete App**. These are separate dummy
apps; the installed Surround and Surround Beta apps have their own identities.
