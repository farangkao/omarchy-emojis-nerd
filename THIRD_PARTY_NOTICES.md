# Third-party notices

This plugin builds on the following MIT-licensed projects. Their license
notices apply to the files derived from them.

## Omarchy — https://github.com/basecamp/omarchy

Copyright (c) David Heinemeier Hansson

- `Emojis.qml` is derived from Omarchy's built-in emoji picker
  (`shell/plugins/emojis/Emojis.qml`).
- `emojis.json` is copied from Omarchy's built-in emoji picker.

## Nerd Fonts — https://github.com/ryanoasis/nerd-fonts

Copyright (c) 2014 Ryan L McIntyre

- `nerdfonts.json` is generated from Nerd Fonts v3.5.0 `glyphnames.json`
  (the glyph name → codepoint mapping) by `tools/convert_nerd.py`.
  It contains no font data or font files.

## emoticon-data — https://github.com/w33ble/emoticon-data

Copyright (c) 2014 Joe Fleming

- `kaomoji.tsv` is generated from the repository's `emoticons.json` by
  `tools/convert_kaomoji.py`: the `id` field is dropped and the remaining
  tags and strings are written one kaomoji per line.
