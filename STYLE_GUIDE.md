# RealMarble2 UI Style Guide

This document defines the visual style and design patterns for all UI elements in RealMarble2. Follow these guidelines to maintain consistency across menus, dialogs, and in-game interfaces.

## Core Design Philosophy

- **Dark and Modern**: Semi-transparent dark backgrounds with blue accent colors
- **Clear Hierarchy**: Use font sizes and colors to establish visual importance
- **Consistent Spacing**: Maintain uniform margins and padding throughout
- **Rounded Corners**: All panels and buttons use rounded corners for a modern look
- **Blue Accents**: Primary color is a bright cyan-blue for highlights and borders

---

## Color Palette

### Primary Colors

| Color Name | RGB Value | Hex | Usage |
|------------|-----------|-----|-------|
| **Accent Blue** | `Color(0.3, 0.7, 1, 1)` | `#4DB3FF` | Titles, section headers, borders |
| **Accent Blue (Transparent)** | `Color(0.3, 0.7, 1, 0.6)` | `#4DB3FF99` | Panel borders, hover states |
| **Light Accent Blue** | `Color(0.4, 0.8, 1, 1)` | `#66CCFF` | Pressed button borders |

### Background Colors

| Color Name | RGB Value | Usage |
|------------|-----------|-------|
| **Panel Background** | `Color(0, 0, 0, 0.85)` | Main panel backgrounds |
| **Button Normal** | `Color(0.15, 0.15, 0.2, 0.8)` | Default button state |
| **Button Hover** | `Color(0.2, 0.3, 0.4, 0.9)` | Button hover state |
| **Button Pressed** | `Color(0.3, 0.5, 0.7, 1)` | Button active/pressed state |
| **Line Edit** | `Color(0.1, 0.1, 0.15, 0.9)` | Text input fields |

### Text Colors

| Color Name | RGB Value | Usage |
|------------|-----------|-------|
| **Primary Title** | `Color(0.3, 0.7, 1, 1)` | Main titles and section headers |
| **Primary Text** | `Color(1, 1, 1, 1)` | Button text, labels |
| **Secondary Text** | `Color(0.9, 0.9, 0.9, 1)` | Body text, descriptions |
| **Success/Ready** | `Color(0.3, 1, 0.3, 1)` | Ready states, success messages |

---

## Typography

### Font Sizes

| Element Type | Font Size | Usage |
|--------------|-----------|-------|
| **Main Title** | 32px | Primary screen titles (e.g., "MULTIPLAYER", "OPTIONS") |
| **Section Header** | 24px | Section dividers (e.g., "SENSITIVITY") |
| **Subsection Header** | 20px | Subsection labels (e.g., "YOUR NAME", "JOIN GAME") |
| **Primary Button** | 20px | Main action buttons |
| **Secondary Button** | 18px | Back buttons, less important actions |
| **Body Text** | 16px | Labels, list items, status messages |

### Text Casing

- **Titles and Headers**: ALL UPPERCASE for maximum clarity
- **Button Text**: ALL UPPERCASE for consistency
- **Body Text**: Sentence case or title case as appropriate

---

## Panel Styling

### Main Panels

Use `StyleBoxFlat` with the following properties:

```gdscript
var panel_style = StyleBoxFlat.new()
panel_style.bg_color = Color(0, 0, 0, 0.85)
panel_style.corner_radius_top_left = 12
panel_style.corner_radius_top_right = 12
panel_style.corner_radius_bottom_right = 12
panel_style.corner_radius_bottom_left = 12
panel_style.border_width_left = 3
panel_style.border_width_top = 3
panel_style.border_width_right = 3
panel_style.border_width_bottom = 3
panel_style.border_color = Color(0.3, 0.7, 1, 0.6)
```

**Key Properties:**
- **Background**: Very dark with 85% opacity
- **Corner Radius**: 12px on all corners
- **Border**: 3px blue border with 60% opacity

### Margins

All main panels should use `MarginContainer` with:
- **All margins**: 25px (left, top, right, bottom)

### Separation

Use `VBoxContainer` or `HBoxContainer` with:
- **Separation**: 12-15px between elements

---

## Button Styling

### Normal State

```gdscript
var button_normal = StyleBoxFlat.new()
button_normal.bg_color = Color(0.15, 0.15, 0.2, 0.8)
button_normal.corner_radius_top_left = 8
button_normal.corner_radius_top_right = 8
button_normal.corner_radius_bottom_right = 8
button_normal.corner_radius_bottom_left = 8
button_normal.border_width_left = 2
button_normal.border_width_top = 2
button_normal.border_width_right = 2
button_normal.border_width_bottom = 2
button_normal.border_color = Color(0.3, 0.7, 1, 0.4)
```

### Hover State

```gdscript
var button_hover = StyleBoxFlat.new()
button_hover.bg_color = Color(0.2, 0.3, 0.4, 0.9)
button_hover.corner_radius_top_left = 8
button_hover.corner_radius_top_right = 8
button_hover.corner_radius_bottom_right = 8
button_hover.corner_radius_bottom_left = 8
button_hover.border_width_left = 2
button_hover.border_width_top = 2
button_hover.border_width_right = 2
button_hover.border_width_bottom = 2
button_hover.border_color = Color(0.3, 0.7, 1, 0.8)
```

### Pressed State

```gdscript
var button_pressed = StyleBoxFlat.new()
button_pressed.bg_color = Color(0.3, 0.5, 0.7, 1)
button_pressed.corner_radius_top_left = 8
button_pressed.corner_radius_top_right = 8
button_pressed.corner_radius_bottom_right = 8
button_pressed.corner_radius_bottom_left = 8
button_pressed.border_width_left = 2
button_pressed.border_width_top = 2
button_pressed.border_width_right = 2
button_pressed.border_width_bottom = 2
button_pressed.border_color = Color(0.4, 0.8, 1, 1)
```

**Key Properties:**
- **Corner Radius**: 8px (smaller than panels for hierarchy)
- **Border**: 2px blue border
- **Transitions**: Normal → Hover → Pressed should feel smooth

### Applying Button Styles in TSCN

```gdscript
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_font_sizes/font_size = 20
theme_override_styles/normal = SubResource("StyleBoxFlat_button_normal")
theme_override_styles/hover = SubResource("StyleBoxFlat_button_hover")
theme_override_styles/pressed = SubResource("StyleBoxFlat_button_pressed")
```

---

## Text Input Fields

### LineEdit Styling

```gdscript
var line_edit_style = StyleBoxFlat.new()
line_edit_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
line_edit_style.corner_radius_top_left = 6
line_edit_style.corner_radius_top_right = 6
line_edit_style.corner_radius_bottom_right = 6
line_edit_style.corner_radius_bottom_left = 6
line_edit_style.border_width_left = 2
line_edit_style.border_width_top = 2
line_edit_style.border_width_right = 2
line_edit_style.border_width_bottom = 2
line_edit_style.border_color = Color(0.3, 0.7, 1, 0.4)
```

**Key Properties:**
- **Background**: Darker than buttons (more contrast for input)
- **Corner Radius**: 6px (smaller for subtlety)
- **Font Size**: 16px
- **Text Color**: White

### Applying LineEdit Styles

```gdscript
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_font_sizes/font_size = 16
theme_override_styles/normal = SubResource("StyleBoxFlat_line_edit")
theme_override_styles/focus = SubResource("StyleBoxFlat_line_edit")
```

---

## Dialog / Popup Windows

When creating programmatic dialogs (like the bot count selector):

```gdscript
var dialog = AcceptDialog.new()
dialog.size = Vector2(600, 450)

var panel_style = StyleBoxFlat.new()
panel_style.bg_color = Color(0, 0, 0, 0.85)
panel_style.set_corner_radius_all(12)
panel_style.border_color = Color(0.3, 0.7, 1, 0.6)
panel_style.set_border_width_all(3)

# For buttons within dialogs
var button_style_normal = StyleBoxFlat.new()
button_style_normal.bg_color = Color(0.15, 0.15, 0.2, 0.8)
button_style_normal.set_corner_radius_all(8)
button_style_normal.border_color = Color(0.3, 0.7, 1, 0.4)
button_style_normal.set_border_width_all(2)
```

**Dialog Best Practices:**
- Center dialogs on screen
- Use same panel styling as main menus
- Add 25px margins via MarginContainer
- Use grid layouts for multiple options
- Include title with blue accent color at 24-28px

---

## Layout Patterns

### Standard Menu Layout

```
PanelContainer (with panel style)
├── MarginContainer (25px all sides)
    └── VBoxContainer (12-15px separation)
        ├── Title Label (32px, blue)
        ├── HSeparator
        ├── Section Content
        ├── HSeparator
        └── Back Button
```

### Form Layout (Name + Input)

```
VBoxContainer
├── Label (20px, blue, "FIELD NAME")
└── LineEdit (16px, white text)
```

### Button Group Layout

```
VBoxContainer (5-8px separation)
├── PrimaryButton (20px font)
├── PrimaryButton (20px font)
└── BackButton (18px font)
```

---

## Special States

### Ready/Success States

- **Color**: `Color(0.3, 1, 0.3, 1)` - Bright green
- **Usage**: Ready buttons, success messages
- **Icon**: Include ✓ checkmark

### Host Indicator

- **Icon**: 👑 crown emoji
- **Placement**: After player name in lobby lists

### Disabled Buttons

- **Behavior**: Set `button.disabled = true`
- **Visual**: Godot handles automatic dimming

---

## Responsive Sizing

### Main Menu Panels

- **Default Size**: 600x700px
- **Centered**: Use anchor_left/right/top/bottom = 0.5

### Lobby Panels

- **Default Size**: 600x700px
- **Centered**: Use anchor_left/right/top/bottom = 0.5

### Options Menu

- **Default Size**: 500x600px
- **Centered**: Use anchor_left/right/top/bottom = 0.5

### Dialogs

- **Default Size**: 600x450px
- **Can vary based on content**

---

## Component Checklist

When creating a new UI element, ensure:

- [ ] Dark semi-transparent background (0.85 alpha)
- [ ] 12px rounded corners on panels
- [ ] 8px rounded corners on buttons
- [ ] 3px blue border on panels
- [ ] 2px blue border on buttons
- [ ] 25px margins on all sides
- [ ] 12-15px separation in containers
- [ ] Blue accent color for titles (32px)
- [ ] Blue accent color for section headers (20-24px)
- [ ] White text for buttons (20px primary, 18px secondary)
- [ ] ALL UPPERCASE for titles and buttons
- [ ] Consistent hover/pressed states for buttons

---

## Code Templates

### Creating a Styled Panel (GDScript)

```gdscript
var panel = PanelContainer.new()
var panel_style = StyleBoxFlat.new()
panel_style.bg_color = Color(0, 0, 0, 0.85)
panel_style.set_corner_radius_all(12)
panel_style.border_color = Color(0.3, 0.7, 1, 0.6)
panel_style.set_border_width_all(3)
panel.add_theme_stylebox_override("panel", panel_style)

var margin = MarginContainer.new()
margin.add_theme_constant_override("margin_left", 25)
margin.add_theme_constant_override("margin_top", 25)
margin.add_theme_constant_override("margin_right", 25)
margin.add_theme_constant_override("margin_bottom", 25)
panel.add_child(margin)
```

### Creating a Styled Button (GDScript)

```gdscript
var button = Button.new()
button.text = "BUTTON TEXT"
button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
button.add_theme_font_size_override("font_size", 20)

# Apply style boxes (assumes SubResources already defined)
button.add_theme_stylebox_override("normal", button_normal_style)
button.add_theme_stylebox_override("hover", button_hover_style)
button.add_theme_stylebox_override("pressed", button_pressed_style)
```

### Creating a Title Label (GDScript)

```gdscript
var title = Label.new()
title.text = "TITLE TEXT"
title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
title.add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))
title.add_theme_font_size_override("font_size", 32)
```

---

## Files Using This Style

Reference these files for examples of proper styling:

- **Main Menu**: `rl_main_menu.tscn`, `rl_menu_button.tscn`
- **Options Menu**: `world.tscn` (lines 291-384)
- **Multiplayer Lobby**: `lobby_ui.tscn`, `lobby_ui.gd`
- **Bot Selection Dialog**: `world.gd` (`ask_bot_count()` function)

---

## Version History

- **v1.0** (2026-01-15): Initial style guide created
  - Established core color palette
  - Defined panel and button styling
  - Set typography standards
  - Created code templates

---

## Maintenance

When updating the style guide:

1. Document all color changes
2. Update code templates
3. Add new component types as needed
4. Keep examples up to date with actual implementations
5. Version the guide to track changes

---

**Last Updated**: 2026-01-15
**Maintained By**: RealMarble2 Development Team
