# kit/minimal

The one shared look. Include in every page `<head>`:

    <link rel="stylesheet" href="static/minimal/minimal.css">
    <script src="static/minimal/theme.js"></script>          <!-- before first paint, so no flash -->

and, where you want the Colors/Accent picker, `<div id="theme-menu"></div>` plus `<script src="static/minimal/theme-menu.js" defer></script>`.
All three are separate files because each app sends a strict Content-Security-Policy that forbids inline scripts.
Light/dark follows the device unless the visitor picks one. Choices are stored in `localStorage` as `site.colors` and `site.accent`,
shared by every app on the domain (same origin). Only Minimal exists: there is no "Original" style in the new apps.
