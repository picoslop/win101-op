# Overlap window manager (t_ovS23)

Windows 1.01's stock top-level windows are tiled: every class-0 window is
placed by the `_TILE` column engine, so the MS-DOS Executive and applications
cannot overlap. t_ovS23 keeps class-0 windows as class-0 and gives them the
popup path instead.

## Model

* A class-0 window created by `CreateWindow` is marked internally (bit 1 of
  `[wnd+33h]`, plus a style high-byte marker) and linked into the popup
  z-order list. The class and the stock input path remain unchanged.
* `SHOWWINDOW` dispatches marked windows to the popup show path; the initial
  `WM_SIZE` is sent from the show path, not from `CreateWindow` (tiled windows
  never got one there, and PageMaker hangs if it arrives early).
* `DESTROYWINDOW`, `BRINGWINDOWTOTOP`, `MOVEWINDOW`, `OPENWND` and the
  activate tail dispatch marked windows to the popup routines.
* `GetWindowLong(GWL_STYLE)` masks the internal marker/popup bits so apps see
  the style they requested. `SetWindowLong(GWL_STYLE)` re-adds them when the
  old style had the marker.
* Minimize uses `OPENICONSLOT` + `MAKEICONIC` and a 64-entry saved-rectangle
  table in `_TEXT`; restore uses `DELICON` + `CLOSEICONSLOT` + `MOVEPOPUP`.

## Resize

The visible painted border and grow box lie a few pixels **outside** the
window object's inner rect. The hit test in `CHECKSYSQUEUE` (`_TEXT:2A20`)
and the popup-z-order scan accept six pixels outside the inner rect on all
four sides. A corner or edge drag is event-driven, moves/resizes the popup,
and raises it. The system-menu **Size** item is removed from USER's menu
resource; use the visible border/grow box, not the menu.

The historical popup-class conversion (`[wnd+33h] |= 0x80`) and the modal
`SYSCOMMAND_SIZE` stub are not used. `_TILE` remains for desktop/icon
painting only.

## GDI side

GDI draws a border around the client area; ADDBORDER (`source/gdi/`) is the
matching GDI change that keeps that border outside the inner rect. The
release GDI is `47d780da…`.

## Known behaviour

* The overlap layout is intentionally not pixel-identical to stock tiled
  Windows.
* Edge/corner resize is the supported resize path; the menu Size item is
  gone.
* The system menu still opens normally (Move / Icon / Zoom / Close / About)
  except for the item removal.
