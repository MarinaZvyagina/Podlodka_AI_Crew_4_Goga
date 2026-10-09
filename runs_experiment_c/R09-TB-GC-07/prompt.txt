## Ticket: Let users set the navigation toolbar's middle button to "Close Tab"

The navigation toolbar at the bottom (or top) of the browser has a
customizable middle button — users can currently choose between it acting
as a "Home" button or a "New Tab" button, and their choice is remembered the
next time they open the app. This is configured from the toolbar
customization option in Settings > Appearance.

We'd like to add a third choice: "Close Tab", which closes the currently
active tab when tapped. Requirements:

- The new option should appear alongside the existing "Home" and "New Tab"
  choices wherever users currently pick the middle button behaviour, with
  its own icon and label.
- Whatever the user picks must be persisted the same way the existing two
  choices are, so it's still in effect the next time the app launches.
- Tapping the button when "Close Tab" is selected should close the active
  tab, the same way it can already be closed from other places in the app.
- Tapping the button should be measured the same way taps on the other two
  middle-button options already are, so we can compare usage of all three
  choices later.
- Don't change the behaviour of the existing "Home" and "New Tab" choices.
