# Surround Liquid Glass icon

[SurroundIcon.icon](../../Surround/SurroundIcon.icon) is the canonical production
icon for iPhone, iPad, and Mac. It was copied exactly from the approved
[Amber study](Variants/Surround-Amber.icon), shown as **Go 7 Amber** in the
device comparison. Its borderless board uses a warm amber gradient
(`#DAAA5E` → `#B98239`) and brown grid (`#825C32`).

## Edit the production icon

1. Open `Surround/SurroundIcon.icon` from the app repository in Icon Composer.
   You can launch the app from **Xcode > Open Developer Tool > Icon Composer**.
2. Select the document root and **Board and Grid > Board Face** to tune the
   matching board gradients. Select **Board and Grid > Board** for grid colors.
3. Select **Go Stones** to adjust its neutral shadow, currently 50%. Each glass
   stone has a matching opaque layer in **Stone Faces**; update both layers
   together when changing stone gradients. Keep the group order **Stone Faces**,
   **Go Stones**, **Board and Grid**. All groups have translucency disabled.
4. For geometry or edge fades, edit the SVGs inside the production package's
   `Assets/` directory, then reopen the document. If editing a separate SVG,
   replace the corresponding image in Composer; imported files are copied,
   not linked to their original paths.
5. Check Default, Dark, and Mono, including light/dark Clear and Tinted options,
   at small icon sizes and with different wallpapers. Save and rebuild the app.

The studies below remain separate documents. Editing a study or its preview
does not update the production icon.

## Earlier raised-board study

[Surround.icon](Surround.icon) is the earlier refined study, with shaded stones
above a raised golden board and a warm brown backdrop. It is not the production
asset. To tune this study:

1. Open `Surround.icon` in Icon Composer. You can launch the app from
   **Xcode > Open Developer Tool > Icon Composer**.
2. Select the document root in the sidebar to adjust the warm brown background
   gradient.
3. Select **Go Stones** to tune the native glass edges and neutral shadow,
   currently at 60% opacity. Each radius-82 stone has a matching radius-80
   opaque layer in **Stone Faces**. These faces cover the broad highlights to
   leave a thin glass edge. When changing colors or gradient endpoints, update
   each stone and its matching face together.
4. Select **Board Face and Grid > Board** to adjust the lighter grid. This
   group also contains an opaque 812 × 812 **Board Face**. Both layers have
   glass disabled, and the group has no shadow.
5. Select **Board Surface > Raised Gold Board** to tune the underlying glass
   and its neutral shadow, currently at 40%. This 816 × 816 surface leaves a
   thin edge around the smaller Board Face. Update both board layers together
   when changing their gold gradients. All groups have translucency disabled.
6. Use the appearance controls below the canvas to inspect **Default**, **Dark**,
   and **Mono**. The stone and board gradients have separate appearance
   settings, with warmer whites and separated monochrome tones. In Mono
   options, inspect clear and tinted variants in both light and dark
   appearances; one Mono annotation controls all four.
7. Use the preview toolbar to change wallpaper, lighting, and icon size. Check
   the center stones and board lines at small sizes, then save the document.

Keep the sidebar order **Stone Faces**, **Go Stones**, **Board Face and Grid**,
**Board Surface**, from top to bottom. It places each opaque face over its
glass base while keeping the stones above the grid.

## Artwork and previews

`Sources/` contains the board grid, board face, board surface, and five pairs
of stone/face SVGs. Each uses the same 1024 × 1024 canvas so its positioning is
preserved on import. The grid spans centers 144–880 at a pitch of 184; stone
centers use 328, 512, and 696. Radius-82 stones leave 20 pixels between adjacent
stones. The board surface is positioned at `(104, 104)` with corner radius 48;
its face is inset by 2 pixels on each edge.

Edit these files to change the geometry. Then select the corresponding image
layer in Composer and replace or reimport its image, preserving its group and
appearance settings. Composer copies artwork into `Surround.icon/Assets/`;
editing `Sources/` alone does not update the document.

`Previews/` contains native `ictool` renders using generation 26: Default, Dark,
ClearLight, ClearDark, TintedLight, and TintedDark. `Surround-Default-27.png`
shows the same document with native generation 27 rendering. Its finer edge
highlights and shadows differ from generation 26; compare both generations
using Composer's Effects controls.

Earlier drafts remain editable for comparison:

- `Variants/Surround-Original.icon`: the first draft, with
  `Previews/Before-Default.png`.
- `Variants/Surround-Depth.icon`: the earlier depth treatment, with
  `Previews/Before-Refinement-Default.png` and
  `Previews/Before-Refinement-Default-27.png`.

These PNGs are visual review exports. Continue editing and deliver the layered
`.icon` document for app use.

## Board-edge alternatives

Four studies address the close spacing between the rectangular board and the
rounded icon mask. `Surround.icon` remains the raised-board study above;
Amber was selected for production. All four preserve stone sizes, positions, and gradient fills; the
borderless studies use a softer stone shadow.

- `Variants/Surround-Roomier-Board.icon`: a smaller 744 × 744 board inset by
  140 pixels, with corner radius 112, a matching face inset by 2 pixels, and
  a 25% board shadow. The perimeter grid is removed; three lines per axis
  extend from 184 to 840 through the existing stone centers.
- `Variants/Surround-Edge-to-Edge.icon`: gold fills the icon shape, with no
  separate board slab outline. Five 6-pixel lines per axis run across the full
  1024-pixel canvas at 144, 328, 512, 696, and 880; the native icon mask clips
  their ends. All lines are fully opaque through the board interior. A shared
  alpha mask fades only the portions within 128 pixels of the canvas edges,
  reaching 18% opacity at the boundary; the fades combine at the corners.
  Its Default board uses a deeper amber gradient (`#E2B361` → `#C58F39`),
  shared by the root fill and Board Face. Its **Go Stones** group uses a
  neutral shadow at 50% opacity.
- `Variants/Surround-Brown.icon`: a separate color variant of the edge-to-edge
  study, using a darker warm brown/amber Default board gradient
  (`#D1A05B` → `#AC7539`). The root fill and Board Face share this gradient.
  Its Default grid uses deep warm brown `#6B482B`, darker than the
  edge-to-edge grid's `#986F39`, to stay legible against the darker board.
  Stone colors, 50% stone shadows, grid geometry, edge fades, and Dark/Mono
  settings match the edge-to-edge study.
- `Variants/Surround-Amber.icon`: a midpoint between the edge-to-edge and
  Brown Default palettes, with board gradient `#DAAA5E` → `#B98239` shared by
  the root fill and Board Face, and grid color `#825C32`. These colors are
  rounded sRGB channel midpoints. Stone colors, 50% stone shadows, grid
  geometry, edge fades, and Dark/Mono settings match the borderless studies.

Their editable SVGs are inside each variant's `Assets/` directory. For any
borderless study, edit `Assets/Board.svg` to change line positions, lengths,
or the edge-fade width and opacity stops. In Composer, select
**Board and Grid > Board** to replace that image or tune its appearance fills.
Select the **Go Stones** group and adjust **Shadow** opacity to tune the softer
shadow.

Review renders are in `Previews/Edge-Study/`. The roomier and edge-to-edge
studies have been checked in Default appearance using generation 27 at 512,
60, and 32 pixels, plus generation 26 at 60 pixels. The edge-to-edge study has
also passed review in
all six generation 27 appearances at 60 pixels; alternate previews use
`Edge-to-Edge-{Rendition}-27-60.png`. The roomier board has only been reviewed
in Default; its Dark and Mono settings still need review before adoption.

The Brown study was also checked in generation 27 at 512, 60, and 32 pixels
for Default, in all six appearances at 60 pixels, and generation 26 Default
at 60 pixels. Its native review renders use the `Previews/Edge-Study/Brown-` prefix.

The Amber study was checked in Default appearance at 512, 60, and 32 pixels
in generation 27 and at 60 pixels in generation 26. Its native review renders
use the `Previews/Edge-Study/Amber-` prefix.

## App integration

Building the layered Icon Composer icon requires Xcode 26 or later.

`Surround/SurroundIcon.icon` is included in the app target outside the asset
catalog. Production **Debug** and **Release** configurations set
`ASSETCATALOG_COMPILER_APPICON_NAME` to `SurroundIcon`, matching the document's
filename without its extension. **Beta Debug** and **Beta Release** retain
`AppIconBeta` and exclude `SurroundIcon.icon` from their build inputs.

The old `AppIcon` PNG catalog remains as the pre-change reference used by
**Go 0 Current**. Its name is distinct from the production document. Keep the
production package as the source for future icon changes; the comparison
project continues to use the preserved study documents.

Xcode generates fallback images from the Icon Composer document for older OS
versions. This integration therefore changes the icon on iOS 18 too; the existing
asset-catalog icon is not automatically retained there. See Apple's
[Icon Composer documentation](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
and [creation walkthrough](https://developer.apple.com/videos/play/wwdc2025/361/).
