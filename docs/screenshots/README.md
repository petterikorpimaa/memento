# Screenshots

Image assets referenced by the top-level [`README.md`](../../README.md). Add
these files here:

| File | Shows |
| --- | --- |
| `hero.gif` | Short loop: tap-to-modal hand-off, drag-reorder, and the delete dissolve. |
| `list.png` | The reminders list at rest. |
| `modal.png` | A tile expanded into the floating modal. |
| `settings.png` | Settings with the compact-view toggle and language picker. |

## Capturing

1. Run on a device or simulator, or `flutter run -d macos`.
2. Take stills with the device or simulator screenshot tool. For the GIF, screen
   record a short interaction.
3. Convert the recording to a compact GIF, for example with ffmpeg and gifski:

   ```bash
   ffmpeg -i recording.mov -vf "fps=24,scale=480:-1" -f yuv4mpegpipe - \
     | gifski -o hero.gif -
   ```

Keep `hero.gif` small (aim for under 5 MB) so it loads quickly on GitHub.
