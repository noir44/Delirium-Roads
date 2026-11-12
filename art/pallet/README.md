# Поддон асфальтовой смеси — откуда берётся кадр

`frames/delroads_01_16.png` рендерится тем же конвейером, что и гружёные
поддоны Delirium-Items, — он один на все семь:

    E:\mods\Delirium-Items\art\render_pallets.py   сцена и камера PZ
    E:\mods\Delirium-Items\art\compose.py          кладёт груз на ванильный поддон

Пересобрать:

    cd E:\mods\Delirium-Items\art
    blender --background --factory-startup --python render_pallets.py -- rend asphalt
    python compose.py asphalt

`compose.py` сам положит кадр в `Delirium-Roads/art/frames/delroads_01_16.png`
и иконку в `media/textures/Item_DelRoadsPalletAsphalt.png`. Дальше — пак:

    powershell E:\mods\tools\TilePack\build-tilepack.ps1 `
      -Spec E:\mods\Delirium-Roads\art\tiles.json `
      -Media E:\mods\Delirium-Roads\Contents\mods\DeliriumRoads\42\media

Мешки — не модель `DR_AsphaltMix.fbx`: стоячий мешок с завязанным горлом,
положенный набок, даёт клинья и провалы в тень, штабель из него не читается.
Вместо него скруглённые плоские мешки с печатью `art/tex/bagtop.png`
(ASPHALT MIX, 25 kg) — печать только на верхних гранях, по нормали.
