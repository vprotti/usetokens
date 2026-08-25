-- Styles the mounted UseTokens volume: icon view, dark background, icon slots.
-- Window content: 660x400 pt, matching dist/dmg-bg.png (1320x800 @ 144 dpi).
tell application "Finder"
	tell disk "UseTokens"
		open
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set the bounds of container window to {200, 120, 860, 520}
		set viewOptions to the icon view options of container window
		set arrangement of viewOptions to not arranged
		set icon size of viewOptions to 128
		set text size of viewOptions to 13
		set background picture of viewOptions to file ".background:dmg-bg.png"
		set position of item "UseTokens.app" of container window to {165, 228}
		set position of item "Applications" of container window to {495, 228}
		close
		open
		-- give Finder time to flush the .DS_Store
		delay 3
		close
	end tell
end tell
