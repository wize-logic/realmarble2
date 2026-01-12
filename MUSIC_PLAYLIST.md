# Music Playlist System

This project includes a Rocket League-style music playlist that plays background music during gameplay.

## How to Add Songs

1. **Import your music files** into Godot:
   - Drag and drop audio files (`.mp3`, `.ogg`, `.wav`) into the Godot project
   - Recommended location: `res://audio/music/`

2. **Open the World scene**:
   - Open `world.tscn` in the Godot editor

3. **Select the GameplayMusic node**:
   - In the Scene tree, select: `World > GameplayMusic`

4. **Add songs to the playlist**:
   - In the Inspector panel, look for the `Playlist` property
   - Click the array to expand it
   - Change the array size to match the number of songs you want
   - Drag your imported audio files into each array slot
   - Or click each slot and select your audio file from the resource picker

## Settings

The `GameplayMusic` node has these configurable properties:

- **Playlist**: Array of AudioStream resources (your songs)
- **Shuffle**: Enable/disable playlist shuffling (default: true)
- **Volume Db**: Music volume in decibels (default: -15.0)
- **Fade In Duration**: How long to fade in when starting (default: 2.0s)
- **Fade Out Duration**: How long to fade out when stopping (default: 1.5s)

## Behavior

- **When no songs are present**: The game runs in silence (no errors)
- **During gameplay**: Music starts automatically when you host or join a game
- **When paused**: Music pauses automatically
- **When game ends**: Music fades out after the 5-minute timer ends
- **Auto-advance**: Automatically plays the next song when one finishes
- **Loop**: Playlist loops infinitely during gameplay

## Audio Bus

The gameplay music uses the `Music` audio bus. You can adjust the volume in:
- **Project Settings** > **Audio** > **Buses**

Separate from the menu music, so you can control volumes independently!

## Default State

By default, the playlist is **empty** and the game will run silently. This is intentional - add your own music!
